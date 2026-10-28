// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import AVFoundation

struct AudioFile: Codable {
    var path: String
    var title: String
    var artist: String
    var album: String = ""
    var duration: Double = 0
    var modified: Double = 0
    var url: URL {URL(fileURLWithPath:path)}
}
struct LocalMatch {
    var document: LyricsDocument?
    var file: URL?
    var message: String
}
final class MusicLibrary {
    static let extensions:Set<String>=["mp3","m4a","mp4","flac","ogg","opus","wav","aiff","aif","aac","ape","wma"]
    private(set) var files:[AudioFile]=[]
    private(set) var roots:[URL]=[]
    // All access is serialized by the model's libraryQueue.
    private var tagsCache:[String:AudioTags]=[:]
    private var directFiles=Set<String>()
    func scan(paths:[String])->Int {
        roots=paths.map{URL(fileURLWithPath:$0).resolvingSymlinksInPath().standardizedFileURL}
        var seen=Set<String>(),result:[AudioFile]=[]
        for root in roots {
            guard let iterator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.contentModificationDateKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else{continue}
            for case let url as URL in iterator {
                guard Self.extensions.contains(url.pathExtension.lowercased()),isApproved(url),seen.insert(url.path).inserted else{continue}
                guard let attr=try? url.resourceValues(forKeys:[.isRegularFileKey,.contentModificationDateKey]),attr.isRegularFile==true else{continue}
                let stem=url.deletingPathExtension().lastPathComponent
                let parts=stem.components(separatedBy:" - ")
                let title=parts.count>1 ? parts.dropFirst().joined(separator:" - ") : stem
                let artist=parts.count>1 ? parts[0] : ""
                result.append(AudioFile(path:url.path,title:title,artist:artist,modified:attr.contentModificationDate?.timeIntervalSince1970 ?? 0))
            }
        }
        files=result;tagsCache.removeAll();return result.count
    }
    func isApproved(_ url:URL)->Bool {
        let path=url.resolvingSymlinksInPath().standardizedFileURL.path
        return directFiles.contains(path) || roots.contains{path == $0.path || path.hasPrefix($0.path+"/")}
    }
    func match(title:String,artist:String,album:String,duration:Double,fileURL:String?)->LocalMatch {
        guard !normalized(title).isEmpty else{return LocalMatch(document:nil,file:nil,message:"等待播放器提供歌曲名称")}
        var candidates:[(AudioFile,Int)]=[]
        let wanted=normalized(title),wantedArtist=normalized(artist)
        if let fileURL,let url=URL(string:fileURL),url.isFileURL,Self.extensions.contains(url.pathExtension.lowercased()),FileManager.default.isReadableFile(atPath:url.path) {
            directFiles.insert(url.resolvingSymlinksInPath().standardizedFileURL.path)
            candidates.append((AudioFile(path:url.path,title:title,artist:artist),1000))
        }
        for file in files {
            let name=normalized(file.title),stem=normalized(file.url.deletingPathExtension().lastPathComponent)
            var score=name==wanted ? 100 : stem==wanted ? 95 : (stem.contains(wanted) && wanted.count>=2) ? 40 : 0
            if score>0 {
                let localArtist=normalized(file.artist)
                if !wantedArtist.isEmpty && !localArtist.isEmpty {
                    if localArtist==wantedArtist {score+=35}
                    else if artistsMatch(artist,file.artist) {score+=15}
                    else {score-=45}
                }
                if score>=35 {candidates.append((file,score))}
            }
        }
        candidates.sort{$0.1 != $1.1 ? $0.1>$1.1 : $0.0.path<$1.0.path}
        var verified:[(AudioFile,Int)]=[]
        for (file,base) in candidates.prefix(14) {
            let tags=loadTags(file.url)
            let tagTitle=normalized(tags.title),tagArtist=normalized(tags.artist),tagAlbum=normalized(tags.album)
            if !tagTitle.isEmpty && tagTitle != wanted {continue}
            if !wantedArtist.isEmpty && !tagArtist.isEmpty && !artistsMatch(artist,tags.artist) {continue}
            var score=base+(tagTitle==wanted ? 100 : 0)
            if !album.isEmpty && tagAlbum==normalized(album){score+=30}
            if duration>0 && tags.duration>0 {
                if abs(duration-tags.duration)>max(4,duration*0.025){continue}
                score+=20
            }
            verified.append((file,score))
        }
        // If the filename has no title at all, inspect native metadata as a fallback.
        // This scans tag headers, never audio content; confined to chosen roots.
        if verified.isEmpty {
            for file in files {
                let tags=loadTags(file.url)
                guard normalized(tags.title)==wanted else{continue}
                let actualArtist=normalized(tags.artist)
                guard wantedArtist.isEmpty || actualArtist.isEmpty || artistsMatch(artist,tags.artist) else{continue}
                let score=100+(actualArtist==wantedArtist ? 40 : 0)+(normalized(tags.album)==normalized(album) && !album.isEmpty ? 25 : 0)
                verified.append((file,score))
            }
        }
        verified.sort{$0.1 != $1.1 ? $0.1>$1.1 : $0.0.path<$1.0.path}
        guard let best=verified.first else{return LocalMatch(document:nil,file:nil,message:files.isEmpty ? "添加音乐目录后，可读取音频内嵌歌词" : "没有匹配到本地音频，可手动选择当前歌曲文件")}
        if verified.count>1 && verified[1].1==best.1 && verified[1].0.path != best.0.path {
            return LocalMatch(document:nil,file:nil,message:"找到多个同名版本，请用“选择歌词 / 音频”指定当前版本")
        }
        let document=readLyrics(best.0.url)
        return LocalMatch(document:document,file:best.0.url,message:document == nil ? "匹配到音频，但没有找到内嵌或旁挂歌词" : "已匹配本地音频")
    }
    func loadTags(_ url:URL)->AudioTags {
        if let cached=tagsCache[url.path]{return cached}
        var tags=NativeTags.read(url)
        // AVFoundation covers additional standard metadata when native tags are absent.
        if tags.title.isEmpty || tags.artist.isEmpty || tags.lyrics.isEmpty {
            let asset=AVURLAsset(url:url,options:[AVURLAssetPreferPreciseDurationAndTimingKey:false])
            for item in asset.commonMetadata {
                guard let key=item.commonKey?.rawValue,let value=item.stringValue else{continue}
                if key=="title" && tags.title.isEmpty {tags.title=value}
                if key=="artist" && tags.artist.isEmpty {tags.artist=value}
                if key=="albumName" && tags.album.isEmpty {tags.album=value}
            }
            if tags.lyrics.isEmpty,let lyrics=asset.lyrics,!lyrics.isEmpty {tags.lyrics.append(("音频内嵌 · 系统元数据",lyrics))}
        }
        tagsCache[url.path]=tags
        return tags
    }
    func readLyrics(_ url:URL)->LyricsDocument? {
        if ["lrc","srt","txt"].contains(url.pathExtension.lowercased()) {
            guard let size=(try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<=8*1024*1024,
                  let data=try? Data(contentsOf:url),let raw=LyricsParser.text(data) else{return nil}
            let doc=LyricsParser.parse(raw,source:"本地歌词 · \(url.pathExtension.uppercased())",file:url)
            return doc.isEmpty ? nil : doc
        }
        var docs:[LyricsDocument]=[]
        let directory=url.deletingLastPathComponent()
        let stem=url.deletingPathExtension().lastPathComponent.lowercased()
        if let entries=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) {
            for sidecar in entries.sorted(by:{$0.path<$1.path}) where ["lrc","srt","txt"].contains(sidecar.pathExtension.lowercased()) && sidecar.deletingPathExtension().lastPathComponent.lowercased()==stem {
                // Do not follow sidecars pointing outside user-approved directories.
                if (isApproved(sidecar) || (directFiles.contains(url.resolvingSymlinksInPath().standardizedFileURL.path) && sidecar.resolvingSymlinksInPath().deletingLastPathComponent()==url.resolvingSymlinksInPath().deletingLastPathComponent())),let doc=readLyrics(sidecar){docs.append(doc)}
            }
        }
        for (source,raw) in loadTags(url).lyrics {
            let doc=LyricsParser.parse(raw,source:source,file:url)
            if !doc.isEmpty {docs.append(doc)}
        }
        return docs.first(where:{$0.timed}) ?? docs.first
    }
    func readSelectedFile(_ url:URL)->LyricsDocument? {
        directFiles.insert(url.resolvingSymlinksInPath().standardizedFileURL.path)
        return readLyrics(url)
    }
    func clearCache(){tagsCache.removeAll()}
}

private func artistsMatch(_ lhs:String,_ rhs:String)->Bool {
    if normalized(lhs)==normalized(rhs){return true}
    func tokens(_ value:String)->Set<String> {
        let separated=value.replacingOccurrences(of:#"(?i)\s*(?:[/&、,，;；]|\bfeat\.?|\bft\.?|\bfeaturing\b|\band\b)\s*"#,with:"\u{1f}",options:.regularExpression)
        return Set(separated.components(separatedBy:"\u{1f}").map(normalized).filter{!$0.isEmpty})
    }
    let a=tokens(lhs),b=tokens(rhs)
    return !a.isDisjoint(with:b)
}
