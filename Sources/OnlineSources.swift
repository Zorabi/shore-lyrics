// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

struct OnlineLyricsSource:Codable,Equatable,Identifiable {
    enum Kind:String,Codable {case lrclib,netease,qq,kugou,amll,custom}
    enum Format:String,Codable,CaseIterable {case json,text}
    var id=UUID().uuidString
    var name:String
    var kind:Kind = .custom
    var enabled=true
    var builtIn=false
    var urlTemplate=""
    var format:Format = .json
    var syncedPath="syncedLyrics"
    var plainPath="plainLyrics"

    static let defaults:[OnlineLyricsSource]=[
        .init(id:"netease",name:"网易云音乐",kind:.netease,builtIn:true),
        .init(id:"qq",name:"QQ 音乐",kind:.qq,builtIn:true),
        .init(id:"kugou",name:"酷狗音乐",kind:.kugou,builtIn:true),
        .init(id:"lrclib",name:"LRCLIB",kind:.lrclib,builtIn:true),
        .init(id:"amll",name:"AMLL 社区歌词库",kind:.amll,enabled:false,builtIn:true),
        .init(id:"lyrics-ovh",name:"lyrics.ovh",enabled:false,builtIn:true,
              urlTemplate:"https://api.lyrics.ovh/v1/{artist}/{title}",syncedPath:"",plainPath:"lyrics")
    ]
    static func restored(_ data:Data?)->[OnlineLyricsSource] {
        guard let data,let saved=try? JSONDecoder().decode([OnlineLyricsSource].self,from:data) else{return defaults}
        var seen=Set<String>()
        var sources=saved.filter{seen.insert($0.id).inserted}.compactMap { source -> OnlineLyricsSource? in
            if var original=defaults.first(where:{$0.id==source.id}) {original.enabled=source.enabled;return original}
            guard !source.builtIn,source.kind == .custom,source.validationError==nil else{return nil}
            return source
        }
        for source in defaults where !seen.contains(source.id) {sources.append(source)}
        return sources
    }
    var validationError:String? {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return "请填写来源名称"}
        guard kind == .custom else{return nil}
        guard urlTemplate.contains("{title}"),urlTemplate.contains("{artist}") else{return "地址需包含 {title} 和 {artist} 占位符"}
        let authority=urlTemplate.components(separatedBy:"://").dropFirst().joined(separator:"://").prefix{ !"/?#".contains($0) }
        guard !authority.contains("{") else{return "占位符只能用于路径或查询参数，不能用于域名"}
        let sample=Self.expand(urlTemplate,values:["title":"title","artist":"artist","album":"album","duration":"100"])
        guard !sample.contains("{"),!sample.contains("}"),let url=URL(string:sample),Self.allowed(url) else{return "请填写有效的 HTTPS 地址；不支持账号密码、片段或未知占位符"}
        if format == .json,syncedPath.isEmpty && plainPath.isEmpty {return "请至少填写一个歌词字段路径"}
        for path in [syncedPath,plainPath] where !path.isEmpty {
            if path.split(separator:".",omittingEmptySubsequences:false).contains(where:{$0.isEmpty}) {return "字段路径使用点号分隔，例如 data.lrc.lyric"}
        }
        return nil
    }
    static func allowed(_ url:URL)->Bool {
        url.scheme?.lowercased()=="https" && !(url.host ?? "").isEmpty && url.user==nil && url.password==nil && url.fragment==nil
    }
    static func allowsRedirect(from original:URL?,to target:URL?)->Bool {
        guard let original,let target,allowed(original),allowed(target) else{return false}
        return original.host?.lowercased()==target.host?.lowercased() && (original.port ?? 443)==(target.port ?? 443)
    }
    private static func expand(_ template:String,values:[String:String])->String {
        values.reduce(template){result,item in
            result.replacingOccurrences(of:"{\(item.key)}",with:item.value.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? "")
        }
    }
    func request(for track:PlaybackSnapshot)throws->URLRequest {
        guard validationError==nil else{throw SourceError.invalidConfiguration}
        let url:URL
        switch kind {
        case .lrclib:
            var parts=URLComponents(string:"https://lrclib.net/api/get")!
            var query=[URLQueryItem(name:"track_name",value:track.title),URLQueryItem(name:"artist_name",value:track.artist)]
            if let album=track.album,!album.isEmpty{query.append(.init(name:"album_name",value:album))}
            if let duration=track.duration,duration>=1,duration<=3600 {query.append(.init(name:"duration",value:String(Int(duration.rounded()))))}
            parts.queryItems=query;url=parts.url!
        case .netease,.amll:
            var parts=URLComponents(string:"https://music.163.com/api/search/get")!
            parts.queryItems=[.init(name:"s",value:[track.title,track.artist].compactMap{$0}.joined(separator:" ")),.init(name:"type",value:"1"),.init(name:"limit",value:"10")]
            url=parts.url!
        case .qq:
            var parts=URLComponents(string:"https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
            parts.queryItems=[.init(name:"w",value:[track.title,track.artist].compactMap{$0}.joined(separator:" ")),.init(name:"format",value:"json"),.init(name:"p",value:"1"),.init(name:"n",value:"10")]
            url=parts.url!
        case .kugou:
            var parts=URLComponents(string:"https://lyrics.kugou.com/search")!
            parts.queryItems=[.init(name:"ver",value:"1"),.init(name:"man",value:"yes"),.init(name:"client",value:"pc"),.init(name:"keyword",value:[track.title,track.artist].compactMap{$0}.joined(separator:" "))]
            url=parts.url!
        case .custom:
            let duration=track.duration.flatMap{$0.isFinite && $0>=0 && $0<=86400 ? String(Int($0.rounded())) : nil} ?? ""
            let expanded=Self.expand(urlTemplate,values:["title":track.title ?? "","artist":track.artist ?? "","album":track.album ?? "","duration":duration])
            guard let value=URL(string:expanded),Self.allowed(value) else{throw SourceError.invalidConfiguration}
            url=value
        }
        var request=URLRequest(url:url)
        request.setValue("ShoreLyrics/\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev") (macOS)",forHTTPHeaderField:"User-Agent")
        request.httpShouldHandleCookies=false
        if kind == .qq{request.setValue("https://y.qq.com/",forHTTPHeaderField:"Referer")}
        return request
    }
    enum SourceError:Error {case invalidConfiguration}
    struct Response {
        var document:LyricsDocument?
        var followup:URLRequest?
    }
    static func value(at path:String,in object:Any)->Any? {
        guard !path.isEmpty else{return nil}
        var value:Any=object
        for part in path.split(separator:".") {
            if let dict=value as? [String:Any],let next=dict[String(part)] {value=next}
            else if let array=value as? [Any],let index=Int(part),array.indices.contains(index) {value=array[index]}
            else{return nil}
        }
        return value
    }
    static func decodedEntities(_ value:String)->String {
        var text=value
        let regex=try! NSRegularExpression(pattern:"&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            guard let digits=Range(match.range(at:1),in:text),let range=Range(match.range,in:text) else{continue}
            let token=String(text[digits]),hex=token.hasPrefix("x")
            if let number=UInt32(hex ? String(token.dropFirst()) : token,radix:hex ? 16 : 10),let scalar=UnicodeScalar(number){text.replaceSubrange(range,with:String(scalar))}
        }
        for (entity,replacement) in [("&lt;","<"),("&gt;",">"),("&quot;","\""),("&apos;","'"),("&amp;","&")] {text=text.replacingOccurrences(of:entity,with:replacement)}
        return text
    }
    private static func matchesDuration(_ value:Double?,track:PlaybackSnapshot)->Bool {
        guard let value,let duration=track.duration,duration>0 else{return true}
        return abs(value-duration)<=max(4,duration*0.025)
    }
    func response(_ data:Data,track:PlaybackSnapshot,followup:Bool=false)->Response {
        guard data.count<=2*1024*1024 else{return Response()}
        let source="在线 · \(name)"
        func document(_ text:String?)->LyricsDocument? {
            guard let text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
            let parsed=LyricsParser.parse(text,source:source)
            return parsed.isEmpty ? nil : parsed
        }
        if kind == .amll,followup {return Response(document:document(LyricsParser.text(data)))}
        if kind == .custom,format == .text {return Response(document:document(LyricsParser.text(data)))}
        guard let json=try? JSONSerialization.jsonObject(with:data) else{return Response()}
        if kind == .netease || kind == .amll {
            if followup {
                let doc=document(Self.value(at:"lrc.lyric",in:json) as? String)
                return Response(document:doc)
            }
            let songs=Self.value(at:"result.songs",in:json) as? [[String:Any]] ?? []
            let title=normalized(track.title ?? ""),artist=normalized(track.artist ?? "")
            let candidates=songs.filter { song in
                guard normalized(song["name"] as? String ?? "")==title else{return false}
                let artists=(song["artists"] ?? song["ar"]) as? [[String:Any]] ?? []
                guard artists.contains(where:{normalized($0["name"] as? String ?? "")==artist}) else{return false}
                if let millis=(song["duration"] ?? song["dt"]) as? Double,let duration=track.duration,duration>0 {
                    return abs(millis/1000-duration)<=max(4,duration*0.025)
                }
                return true
            }
            // Refuse ambiguous versions instead of returning an arbitrary performance.
            let albumMatches=candidates.filter { song in
                let album=(song["album"] ?? song["al"]) as? [String:Any]
                return !(track.album ?? "").isEmpty && normalized(album?["name"] as? String ?? "")==normalized(track.album ?? "")
            }
            let matches=albumMatches.isEmpty ? candidates : albumMatches
            guard matches.count==1,let id=matches[0]["id"] as? Int,id>0 else{return Response()}
            if kind == .amll {
                let url=URL(string:"https://raw.githubusercontent.com/amll-dev/amll-ttml-db/refs/heads/main/ncm-lyrics/\(id).eslrc")!
                return Response(followup:URLRequest(url:url))
            }
            var parts=URLComponents(string:"https://music.163.com/api/song/lyric")!
            parts.queryItems=[.init(name:"id",value:String(id)),.init(name:"lv",value:"-1"),.init(name:"tv",value:"-1")]
            var request=URLRequest(url:parts.url!);request.setValue("ShoreLyrics/\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev") (macOS)",forHTTPHeaderField:"User-Agent");request.httpShouldHandleCookies=false
            return Response(followup:request)
        }
        if kind == .qq {
            if followup {
                guard let body=json as? [String:Any],(body["retcode"] as? Int ?? body["code"] as? Int ?? -1)==0,let lyric=body["lyric"] as? String else{return Response()}
                let raw=lyric.contains("[") || lyric.contains("&#") ? lyric : Data(base64Encoded:lyric).flatMap{String(data:$0,encoding:.utf8)} ?? ""
                return Response(document:document(Self.decodedEntities(raw)))
            }
            let songs=Self.value(at:"data.song.list",in:json) as? [[String:Any]] ?? []
            let candidates=songs.filter { song in
                let artists=song["singer"] as? [[String:Any]] ?? []
                return normalized(Self.decodedEntities(song["songname"] as? String ?? ""))==normalized(track.title ?? "") && artists.contains{normalized($0["name"] as? String ?? "")==normalized(track.artist ?? "")} && Self.matchesDuration(song["interval"] as? Double,track:track)
            }
            let albumMatches=candidates.filter{!(track.album ?? "").isEmpty && normalized($0["albumname"] as? String ?? "")==normalized(track.album ?? "")}
            let matches=albumMatches.isEmpty ? candidates : albumMatches
            guard matches.count==1,let mid=matches[0]["songmid"] as? String,!mid.isEmpty else{return Response()}
            var parts=URLComponents(string:"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
            parts.queryItems=[.init(name:"songmid",value:mid),.init(name:"format",value:"json"),.init(name:"nobase64",value:"1")]
            var request=URLRequest(url:parts.url!);request.setValue("https://y.qq.com/",forHTTPHeaderField:"Referer");request.httpShouldHandleCookies=false
            return Response(followup:request)
        }
        if kind == .kugou {
            if followup {
                guard let content=Self.value(at:"content",in:json) as? String,let bytes=Data(base64Encoded:content),let lyric=LyricsParser.text(bytes) else{return Response()}
                return Response(document:document(lyric))
            }
            let candidates=(Self.value(at:"candidates",in:json) as? [[String:Any]] ?? []).filter {song in
                normalized(song["song"] as? String ?? "")==normalized(track.title ?? "") && normalized(song["singer"] as? String ?? "")==normalized(track.artist ?? "") && Self.matchesDuration((song["duration"] as? Double).map{$0/1000},track:track)
            }
            guard let candidate=candidates.first,let id=candidate["id"] as? String,let access=candidate["accesskey"] as? String,!id.isEmpty,!access.isEmpty else{return Response()}
            var parts=URLComponents(string:"https://lyrics.kugou.com/download")!
            parts.queryItems=[.init(name:"ver",value:"1"),.init(name:"client",value:"pc"),.init(name:"id",value:id),.init(name:"accesskey",value:access),.init(name:"fmt",value:"lrc"),.init(name:"charset",value:"utf8")]
            return Response(followup:URLRequest(url:parts.url!))
        }
        if kind == .lrclib,(json as? [String:Any])?["instrumental"] as? Bool == true {
            return Response(document:LyricsDocument(lines:[],plain:"纯音乐",source:source+"（纯音乐）"))
        }
        let synced=kind == .lrclib ? "syncedLyrics" : syncedPath
        let plain=kind == .lrclib ? "plainLyrics" : plainPath
        return Response(document:document(Self.value(at:synced,in:json) as? String) ?? document(Self.value(at:plain,in:json) as? String))
    }
}

/// One active request at a time; a provider's search and lyric request share one deadline.
final class OnlineLyricsLookup {
    private let session:URLSession
    private var task:URLSessionDataTask?
    private var deadline:DispatchWorkItem?
    private var revision=0
    init(session:URLSession){self.session=session}
    func cancel(){revision+=1;task?.cancel();task=nil;deadline?.cancel();deadline=nil}
    deinit{task?.cancel();deadline?.cancel()}
    func start(track:PlaybackSnapshot,sources:[OnlineLyricsSource],timeout:TimeInterval,
               onSource:@escaping(OnlineLyricsSource)->Void,completion:@escaping(LyricsDocument?,String)->Void){
        cancel()
        func attempt(_ index:Int,_ lastMessage:String) {
            guard index<sources.count else{self.cancel();completion(nil,lastMessage);return}
            self.cancel()
            let token=self.revision,source=sources[index]
            onSource(source)
            func next(_ message:String){guard token==self.revision else{return};attempt(index+1,message)}
            let deadline=DispatchWorkItem{[weak self] in
                guard let self,self.revision==token else{return}
                next("\(source.name) 查询超时，请重试")
            }
            self.deadline=deadline
            DispatchQueue.main.asyncAfter(deadline:.now()+timeout,execute:deadline)
            func send(_ original:URLRequest,_ followup:Bool) {
                guard token==self.revision else{return}
                var request=original;request.timeoutInterval=min(10,timeout)
                self.task=self.session.dataTask(with:request){[weak self] data,response,error in
                    let parsed:OnlineLyricsSource.Response
                    if error==nil,(response as? HTTPURLResponse)?.statusCode==200,let data {
                        parsed=source.response(data,track:track,followup:followup)
                    }else{parsed = .init()}
                    DispatchQueue.main.async {
                        guard let self,self.revision==token else{return}
                        if let document=parsed.document {
                            self.cancel();completion(document,"")
                        }else if let request=parsed.followup,!followup {send(request,true)}
                        else{next(error==nil ? "\(source.name) 没有匹配到歌词" : "\(source.name) 查询失败，请重试")}
                    }
                }
                self.task?.resume()
            }
            do{try send(source.request(for:track),false)}catch{next("\(source.name) 配置无效")}
        }
        attempt(0,"没有启用的在线来源")
    }
}
