// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

struct LyricWord: Codable, Equatable {
    var time: Double
    var offset: Int
}

struct LyricLine: Codable, Equatable {
    var time: Double
    var text: String
    var end: Double? = nil
    var words: [LyricWord] = []
    func progress(at seconds: Double, until endTime: Double, estimatedSpeed:Double=1) -> Double {
        guard seconds.isFinite, endTime > time, !text.isEmpty else { return 0 }
        if seconds < time { return 0 }
        if seconds >= endTime { return 1 }
        guard !words.isEmpty else {
            // Plain LRC has no word timing: finish the estimated sweep slightly early.
            // Explicit subtitle intervals keep their original pace.
            let speed=end == nil && estimatedSpeed.isFinite ? max(0.5,min(2,estimatedSpeed)) : 1.0
            return min(1,max(0,(seconds-time)/(endTime-time)*speed))
        }
        let count = Double(text.count)
        guard let index = words.lastIndex(where: { $0.time <= seconds }) else { return 0 }
        let word = words[index]
        let nextTime = index+1 < words.count ? words[index+1].time : endTime
        let nextOffset = index+1 < words.count ? words[index+1].offset : text.count
        let fraction = nextTime > word.time ? min(1,max(0,(seconds-word.time)/(nextTime-word.time))) : 1
        return min(1,max(0,(Double(word.offset)+Double(nextOffset-word.offset)*fraction)/count))
    }

}
struct LyricsDocument {
    var lines: [LyricLine]
    var plain: String
    var source: String
    var file: URL? = nil
    var timed: Bool { !lines.isEmpty }
    var isEmpty: Bool { lines.isEmpty && plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func index(at seconds: Double) -> Int? {
        guard seconds.isFinite, let first = lines.first, seconds >= first.time else { return nil }
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= seconds { lo = mid + 1 } else { hi = mid }
        }
        let i = max(0, lo - 1)
        if let end = lines[i].end, seconds >= end { return nil }
        return i
    }
}

enum LyricsParser {
    static func text(_ data: Data) -> String? {
        if data.starts(with: [0xFF,0xFE]) || data.starts(with: [0xFE,0xFF]) { return String(data: data, encoding: .utf16) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .init(rawValue: 0x80000632)) ?? String(data: data, encoding: .isoLatin1)
    }
    static func parse(_ raw: String, source: String, file: URL? = nil) -> LyricsDocument {
        let raw = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        if raw.contains("-->") { let srt = parseSRT(raw, source: source, file: file); if srt.timed { return srt } }
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?\]"#)
        let offsetRE = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        var offset = 0.0
        if let m = offsetRE.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)), let r = Range(m.range(at: 1), in: raw) { offset = (Double(raw[r]) ?? 0) / 1000 }
        let wordStamp = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?>"#)
        var result: [LyricLine] = []
        for line in raw.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            let matches = stamp.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let body = stamp.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            var cleaned = "", words: [LyricWord] = [], cursor = body.startIndex
            for mark in wordStamp.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let r = Range(mark.range, in: body) else { continue }
                cleaned += body[cursor..<r.lowerBound]
                func value(_ i: Int) -> String { Range(mark.range(at:i), in:body).map { String(body[$0]) } ?? "" }
                let fraction = value(3), sec = Double(value(2)) ?? 0
                let time = (Double(value(1)) ?? 0)*60+sec+(Double(fraction) ?? 0)/pow(10,Double(fraction.count))-offset
                if sec < 60, time >= (words.last?.time ?? -.infinity) {
                    words.append(LyricWord(time:max(0,time),offset:cleaned.count))
                }
                cursor = r.upperBound
            }
            cleaned += body[cursor...]
            for m in matches {
                func part(_ i: Int) -> String { Range(m.range(at: i), in: line).map { String(line[$0]) } ?? "" }
                guard let min = Double(part(1)), let sec = Double(part(2)), sec < 60 else { continue }
                let fraction = part(3), decimal = fraction.isEmpty ? 0 : (Double(fraction) ?? 0) / pow(10, Double(fraction.count))
                // Positive LRC offsets advance the lyric clock.
                result.append(LyricLine(time: max(0,min * 60 + sec + decimal - offset), text: cleaned, words: words))
            }
        }
        result.sort { $0.time < $1.time }
        var merged: [LyricLine] = []
        for line in result {
            if let last = merged.last, abs(last.time-line.time) < 0.001 {
                if !line.text.isEmpty && !last.text.components(separatedBy: "\n").contains(line.text) {
                    merged[merged.count-1].words = []
                    merged[merged.count-1].text += (last.text.isEmpty ? "" : "\n") + line.text
                }
            } else { merged.append(line) }
        }
        let plain = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[offset:") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[ar:") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[ti:") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[al:") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return LyricsDocument(lines: merged, plain: plain, source: source, file: file)
    }
    private static func parseSRT(_ raw: String, source: String, file: URL?) -> LyricsDocument {
        let regex = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2}):(\d{2})[,\.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,\.](\d{3})"#)
        let rows = raw.components(separatedBy: "\n")
        var result: [LyricLine] = []
        for i in rows.indices {
            let row = rows[i]
            guard let m = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { continue }
            func number(_ n: Int) -> Double { Range(m.range(at: n), in: row).flatMap { Double(row[$0]) } ?? 0 }
            let start = number(1)*3600+number(2)*60+number(3)+number(4)/1000
            let end = number(5)*3600+number(6)*60+number(7)+number(8)/1000
            guard end > start else { continue }
            var body: [String] = [], j = i+1
            while j < rows.count && !rows[j].trimmingCharacters(in: .whitespaces).isEmpty { body.append(rows[j]); j+=1 }
            result.append(LyricLine(time:start,text:body.joined(separator:"\n").replacingOccurrences(of:#"<[^>]+>"#,with:"",options:.regularExpression),end:end))
        }
        return LyricsDocument(lines:result.sorted { $0.time < $1.time },plain:raw,source:source,file:file)
    }
}

struct AudioTags {
    var title = "", artist = "", album = ""
    var lyrics: [(String, String)] = []
    var duration: Double = 0
}

enum NativeTags {
    static func read(_ url: URL) -> AudioTags {
        guard let handle = try? FileHandle(forReadingFrom:url) else { return AudioTags() }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount:10), prefix.count >= 4 else { return AudioTags() }
        if prefix.starts(with:[0x49,0x44,0x33]),prefix.count == 10 {
            let bytes = [UInt8](prefix)
            let size = syncSafe(Array(bytes[6..<10]))
            guard size <= 16*1024*1024, let body = try? handle.read(upToCount:size), body.count == size else { return AudioTags() }
            return id3(version:Int(bytes[3]), flags:bytes[5], bytes:[UInt8](body))
        }
        if prefix.starts(with:[0x66,0x4c,0x61,0x43]) {
            try? handle.seek(toOffset:4)
            return flac(handle)
        }
        if prefix.count >= 8, String(data:prefix.subdata(in:4..<8),encoding:.ascii) == "ftyp" {
            return mp4(handle)
        }
        return AudioTags()
    }
    private static func mp4(_ handle:FileHandle)->AudioTags {
        var tags=AudioTags()
        guard let length=try? handle.seekToEnd() else{return tags}
        func walk(_ start:UInt64,_ end:UInt64,_ depth:Int) {
            guard depth<10,start<=end else{return}
            var position=start
            while position+8<=end {
                try? handle.seek(toOffset:position)
                guard let data=try? handle.read(upToCount:8),data.count==8 else{return}
                let bytes=[UInt8](data),kind=be(Array(bytes[4..<8]))
                var size=UInt64(be(Array(bytes[0..<4]))),header:UInt64=8
                if size==1 {
                    guard let extra=try? handle.read(upToCount:8),extra.count==8 else{return}
                    size=extra.reduce(UInt64(0)){($0<<8)|UInt64($1)};header=16
                } else if size==0 {size=end-position}
                guard size>=header,size<=end-position else{return}
                let content=position+header,limit=position+size
                if [0x6d6f6f76,0x75647461,0x696c7374].contains(kind) {walk(content,limit,depth+1)}
                else if kind==0x6d657461,content+4<=limit {walk(content+4,limit,depth+1)}
                else if [0xa96c7972,0xa96e616d,0xa9415254,0xa9616c62].contains(kind),limit-content<=8*1024*1024 {
                    try? handle.seek(toOffset:content)
                    if let payload=try? handle.read(upToCount:Int(limit-content)) {
                        let b=[UInt8](payload);var offset=0
                        while offset+16<=b.count {
                            let count=be(Array(b[offset..<offset+4])),type=be(Array(b[offset+4..<offset+8]))
                            guard count>=16,count<=b.count-offset else{break}
                            if type==0x64617461 {
                                let encoding=be(Array(b[offset+8..<offset+12]))&0xffffff
                                let text=String(data:Data(b[offset+16..<offset+count]),encoding:encoding==2 ? .utf16BigEndian : .utf8) ?? ""
                                if kind==0xa96c7972,!text.isEmpty {tags.lyrics.append(("音频内嵌 · M4A",text))}
                                if kind==0xa96e616d {tags.title=text};if kind==0xa9415254 {tags.artist=text};if kind==0xa9616c62 {tags.album=text}
                            }
                            offset+=count
                        }
                    }
                }
                position=limit
            }
        }
        walk(0,length,0)
        return tags
    }
    static func syncSafe(_ b:[UInt8]) -> Int { b.reduce(0) { ($0 << 7) | Int($1 & 0x7f) } }
    static func be(_ b:[UInt8]) -> Int { b.reduce(0) { ($0 << 8) | Int($1) } }
    static func decode(_ b:[UInt8], encoding:UInt8) -> String {
        let data=Data(b)
        let enc:String.Encoding = encoding == 0 ? .isoLatin1 : encoding == 1 ? .utf16 : encoding == 2 ? .utf16BigEndian : .utf8
        return (String(data:data,encoding:enc) ?? "").trimmingCharacters(in:CharacterSet(charactersIn:"\0"))
    }
    static func terminated(_ b:[UInt8], from start:Int, encoding:UInt8) -> (text:[UInt8], next:Int)? {
        guard start <= b.count else { return nil }
        let unit = (encoding == 1 || encoding == 2) ? 2 : 1
        var i=start
        while i+unit <= b.count {
            if b[i] == 0 && (unit == 1 || b[i+1] == 0) { return (Array(b[start..<i]), i+unit) }
            i += unit
        }
        return nil
    }
    static func id3(version:Int, flags:UInt8, bytes input:[UInt8]) -> AudioTags {
        guard version == 3 || version == 4 else { return AudioTags() }
        var b=input, tags=AudioTags(), pos=0
        // v2.3 applies unsynchronisation to the entire tag; v2.4 per frame.
        if version == 3 && flags & 0x80 != 0 { b=deunsync(b) }
        if flags & 0x40 != 0 {
            guard b.count >= 4 else { return tags }
            pos = version == 4 ? syncSafe(Array(b[0..<4])) : be(Array(b[0..<4]))+4
            guard pos >= 4 && pos <= b.count else { return tags }
        }
        while pos+10 <= b.count {
            let id=String(bytes:b[pos..<pos+4],encoding:.ascii) ?? ""
            if id.isEmpty || b[pos] == 0 { break }
            let size=version == 4 ? syncSafe(Array(b[pos+4..<pos+8])) : be(Array(b[pos+4..<pos+8]))
            let formatFlags=b[pos+9]
            guard size > 0, size <= b.count-pos-10 else { break }
            var payload=Array(b[pos+10..<pos+10+size]);pos+=10+size
            if (version == 3 && formatFlags & 0xc0 != 0) || (version == 4 && formatFlags & 0x0c != 0) { continue }
            if version == 4 && (formatFlags & 2 != 0 || flags & 0x80 != 0) { payload=deunsync(payload) }
            // Group identifiers and data length indicators precede the actual payload.
            if (version == 3 && formatFlags & 0x20 != 0) || (version == 4 && formatFlags & 0x40 != 0) { if !payload.isEmpty { payload.removeFirst() } }
            if version == 4 && formatFlags & 1 != 0 { guard payload.count>=4 else {continue};payload.removeFirst(4) }
            guard let encoding=payload.first, encoding <= 3 else {continue}
            if ["TIT2","TPE1","TALB"].contains(id) {
                let text=decode(Array(payload.dropFirst()),encoding:encoding)
                if id == "TIT2" {tags.title=text};if id == "TPE1" {tags.artist=text};if id == "TALB" {tags.album=text}
            } else if id == "USLT",payload.count>=4,let description=terminated(payload,from:4,encoding:encoding) {
                let text=decode(Array(payload.dropFirst(description.next)),encoding:encoding)
                if !text.isEmpty {tags.lyrics.append(("音频内嵌 · ID3 USLT",text))}
            } else if id == "SYLT",payload.count>=6,payload[4] == 2,let description=terminated(payload,from:6,encoding:encoding) {
                var i=description.next, result:[String]=[]
                while i<payload.count,let text=terminated(payload,from:i,encoding:encoding),text.next+4<=payload.count {
                    let millis=be(Array(payload[text.next..<text.next+4]));i=text.next+4
                    let lyric=decode(text.text,encoding:encoding).replacingOccurrences(of:"\n",with:" ").trimmingCharacters(in:.whitespaces)
                    result.append(String(format:"[%02d:%02d.%03d]%@",millis/60000,(millis/1000)%60,millis%1000,lyric))
                }
                if !result.isEmpty {tags.lyrics.insert(("音频内嵌 · ID3 SYLT",result.joined(separator:"\n")),at:0)}
            }
        }
        return tags
    }
    private static func deunsync(_ b:[UInt8])->[UInt8] {
        var out:[UInt8]=[],i=0
        while i<b.count {out.append(b[i]);if b[i]==0xff && i+1<b.count && b[i+1]==0 {i+=1};i+=1}
        return out
    }
    private static func flac(_ handle:FileHandle)->AudioTags {
        var tags=AudioTags(),total=0
        while total<32*1024*1024 {
            guard let header=try? handle.read(upToCount:4),header.count==4 else {break}
            let h=[UInt8](header),last=h[0]&0x80 != 0,type=h[0]&0x7f,size=be(Array(h[1..<4]));total+=size+4
            guard size<=16*1024*1024 else {break}
            if type == 4 {
                guard let data=try? handle.read(upToCount:size),data.count==size else {break}
                let b=[UInt8](data);var i=0
                func integer()->Int? {guard i+4<=b.count else{return nil};let v=Int(b[i]) | Int(b[i+1])<<8 | Int(b[i+2])<<16 | Int(b[i+3])<<24;i+=4;return v}
                guard let vendor=integer(),vendor<=b.count-i else{break};i+=vendor
                guard let count=integer(),count<=100000 else{break}
                for _ in 0..<count {
                    guard let size=integer(),size<=b.count-i else{break}
                    let value=String(bytes:b[i..<i+size],encoding:.utf8) ?? "";i+=size
                    guard let equal=value.firstIndex(of:"=") else{continue}
                    let key=value[..<equal].uppercased(),text=String(value[value.index(after:equal)...])
                    switch key {
                    case "TITLE":tags.title=text
                    case "ARTIST":tags.artist=text
                    case "ALBUM":tags.album=text
                    case "LYRICS","UNSYNCEDLYRICS","SYNCEDLYRICS":tags.lyrics.append(("音频内嵌 · FLAC",text))
                    default:break
                    }
                }
            } else {let offset=handle.offsetInFile;try? handle.seek(toOffset:offset+UInt64(size))}
            if last {break}
        }
        return tags
    }
}

func normalized(_ value:String)->String {
    value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
        .unicodeScalars.filter{CharacterSet.alphanumerics.contains($0)}.map(String.init).joined()
}
