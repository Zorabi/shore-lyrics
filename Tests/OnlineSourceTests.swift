// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import AppKit

private final class SourceHTTP:URLProtocol {
    struct Reply {var status:Int=200;var body:Data}
    private static let lock=NSLock()
    private static var replies:[Reply]=[]
    private static var requests:[URLRequest]=[]
    static func reset(_ values:[Reply]){lock.lock();replies=values;requests=[];lock.unlock()}
    static var urls:[URL]{lock.lock();defer{lock.unlock()};return requests.compactMap{$0.url}}
    static func json(_ body:[String:Any],status:Int=200)->Reply{Reply(status:status,body:try! JSONSerialization.data(withJSONObject:body))}
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        Self.lock.lock();Self.requests.append(request)
        let reply=Self.replies.isEmpty ? Reply(status:404,body:Data()) : Self.replies.removeFirst();Self.lock.unlock()
        if reply.status == -1{return}
        let response=HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:reply.body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}
private final class SourceMonitor:PlaybackMonitoring {
    var onSnapshot:((PlaybackSnapshot)->Void)?
    var onStatus:((String)->Void)?
    let track:PlaybackSnapshot
    init(_ track:PlaybackSnapshot){self.track=track}
    func start(){onSnapshot?(track)}
    func refresh(){onSnapshot?(track)}
    func stop(){}
}
private final class ReloadCountingTable:NSTableView {
    var reloadCount=0
    override func reloadData(){reloadCount+=1;super.reloadData()}
}
@main enum OnlineSourceTests {
    static var checks=0
    static func check(_ value:@autoclosure()->Bool,_ message:String){guard value() else{fatalError(message)};checks+=1}
    static func wait(_ message:String,_ predicate:()->Bool){
        let end=Date(timeIntervalSinceNow:2)
        while !predicate() && Date()<end{RunLoop.current.run(until:Date(timeIntervalSinceNow:0.005))}
        check(predicate(),message)
    }
    static func bytes(_ value:Any)->Data{try! JSONSerialization.data(withJSONObject:value)}
    static func main() throws {
        let track=PlaybackSnapshot(capturedAt:Date().timeIntervalSince1970,playing:false,rate:0,title:"晴天",artist:"歌手",album:"专辑",duration:200,position:42)
        let sources=OnlineLyricsSource.defaults
        check(sources.count==6 && sources.filter{$0.enabled}.map{$0.id}==["netease","qq","kugou","lrclib"],"first four default providers are enabled in requested order")
        var custom=OnlineLyricsSource(name:"测试来源",urlTemplate:"https://lyrics.example.test/query?title={title}&artist={artist}&album={album}&duration={duration}",syncedPath:"data.0.lrc",plainPath:"data.0.text")
        check(custom.validationError==nil,"custom source accepts valid HTTPS template and nested paths")
        var injection=track;injection.title="歌名&secret=value/#?";injection.artist="A+B / C"
        let request=try custom.request(for:injection)
        let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
        check(query.count==4 && query.first?.value==injection.title,"metadata cannot inject query parameters")
        check(request.url?.host=="lyrics.example.test" && !request.httpShouldHandleCookies,"custom requests use configured origin without cookies")
        let valid=custom
        for url in ["http://lyrics.example.test/?t={title}&a={artist}","https://user:pass@lyrics.example.test/?t={title}&a={artist}","https://{title}.example.test/?a={artist}","https://lyrics.example.test/?t={title}&a={artist}&x={unknown}"] {
            custom.urlTemplate=url;check(custom.validationError != nil,"invalid or unsafe URL template rejected")
        }
        custom=valid
        let customDoc=custom.response(bytes(["data":[["lrc":"[00:01]同步文本","text":"纯文本"]]]),track:track).document
        check(customDoc?.timed==true && customDoc?.lines.first?.text=="同步文本","nested JSON prefers synced lyric field")
        check(custom.response(bytes(["data":[["lrc":"","text":"纯文本"]]]),track:track).document?.plain=="纯文本","empty synced field falls back to configured plain field")
        check(custom.response(Data("not json".utf8),track:track).document==nil,"malformed JSON is a miss")
        custom.format = .text
        check(custom.response(Data("[00:01]直接文本".utf8),track:track).document?.timed==true,"raw LRC endpoint is supported")
        check(custom.response(Data(repeating:0,count:2*1024*1024+1),track:track).document==nil,"oversized response is rejected")
        custom=valid
        check(OnlineLyricsSource.allowsRedirect(from:URL(string:"https://a.test/q"),to:URL(string:"https://a.test/next")),"same-origin HTTPS redirect is allowed")
        check(!OnlineLyricsSource.allowsRedirect(from:URL(string:"https://a.test/q"),to:URL(string:"https://b.test/next")),"cross-origin redirect is rejected")
        check(!OnlineLyricsSource.allowsRedirect(from:URL(string:"https://a.test/q"),to:URL(string:"http://a.test/next")),"HTTPS downgrade is rejected")
        var reordered=sources.reversed().map{$0};reordered.insert(custom,at:0)
        let restored=OnlineLyricsSource.restored(try JSONEncoder().encode(reordered))
        check(restored.map{$0.id}==reordered.map{$0.id},"custom sources and priority order survive persistence")
        check(OnlineLyricsSource.restored(bytes(["invalid":true]))==sources,"corrupt settings fall back to built-in defaults")
        let netease=sources.first{$0.kind == .netease}!,qq=sources.first{$0.kind == .qq}!,kugou=sources.first{$0.kind == .kugou}!,amll=sources.first{$0.kind == .amll}!
        let song:[String:Any]=["id":123,"name":"晴天","artists":[["name":"歌手"]],"album":["name":"专辑"],"duration":200000]
        let search=bytes(["result":["songs":[song]]])
        check(netease.response(search,track:track).followup?.url?.path=="/api/song/lyric","NetEase matches track metadata before lyric request")
        var wrong=song;wrong["artists"]=[["name":"其他歌手"]]
        check(netease.response(bytes(["result":["songs":[wrong]]]),track:track).followup==nil,"wrong artist is not selected")
        wrong=song;wrong["duration"]=10000
        check(netease.response(bytes(["result":["songs":[wrong]]]),track:track).followup==nil,"wrong duration is not selected")
        check(netease.response(bytes(["result":["songs":[song,song]]]),track:track).followup==nil,"ambiguous versions are not selected")
        check(netease.response(bytes(["lrc":["lyric":"[00:01]歌词"]]),track:track,followup:true).document?.timed==true,"NetEase lyric payload is parsed")
        check(amll.response(search,track:track).followup?.url?.path.hasSuffix("/ncm-lyrics/123.eslrc")==true,"AMLL uses verified NetEase song ID without downloading an index")
        let eslrc="[00:01.00]你[00:01.50]好[00:02.00]"
        let esDoc=amll.response(Data(eslrc.utf8),track:track,followup:true).document
        check(esDoc?.lines.count==1 && esDoc?.lines[0].text=="你好" && esDoc?.lines[0].words.count==3,"AMLL ESLRC inline timestamps become one word-timed line")
        let translated=LyricsParser.parse(eslrc+"\n[00:01.00]Hello",source:"test")
        check(translated.lines[0].words.count==3 && translated.lines[0].text=="你好\nHello","translation merging retains primary word timestamps")
        let qqSearch=bytes(["data":["song":["list":[["songname":"晴天","songmid":"abc123","singer":[["name":"歌手"]],"interval":200,"albumname":"专辑"]]]]])
        check(qq.response(qqSearch,track:track).followup?.value(forHTTPHeaderField:"Referer")=="https://y.qq.com/","QQ search resolves a matching lyric request")
        let qqDoc=qq.response(bytes(["retcode":0,"lyric":"[00:01]你&#38;我&#10;[00:02]歌词"]),track:track,followup:true).document
        check(qqDoc?.lines.count==2 && qqDoc?.lines[0].text=="你&我","QQ lyrics decode XML entities")
        let kugouSearch=bytes(["candidates":[["song":"晴天","singer":"歌手","id":"456","accesskey":"temporary-key","duration":200000]]])
        check(kugou.response(kugouSearch,track:track).followup?.url?.path=="/download","Kugou candidates resolve LRC download request")
        check(kugou.response(bytes(["content":Data("[00:01]酷狗歌词".utf8).base64EncodedString()]),track:track,followup:true).document?.timed==true,"Kugou base64 LRC is decoded")
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[SourceHTTP.self]
        let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
        let lookup=OnlineLyricsLookup(session:session)
        var second=custom;second.id=UUID().uuidString;second.name="第二来源";second.urlTemplate="https://second.example.test/?title={title}&artist={artist}"
        SourceHTTP.reset([SourceHTTP.json([:],status:404),SourceHTTP.json(["data":[["lrc":"[00:01]第二来源命中"]]])])
        var completions=0;var result:LyricsDocument?
        lookup.start(track:track,sources:[custom,second],timeout:0.1,onSource:{_ in},completion:{doc,_ in completions+=1;result=doc})
        wait("providers fall back sequentially"){completions==1}
        check(SourceHTTP.urls.map{$0.host!}==["lyrics.example.test","second.example.test"] && result?.source=="在线 · 第二来源","fallback respects source priority and attribution")
        SourceHTTP.reset([.init(status:-1,body:Data()),SourceHTTP.json(["data":[["lrc":"[00:01]超时回退"]]])])
        completions=0;result=nil
        lookup.start(track:track,sources:[custom,second],timeout:0.04,onSource:{_ in},completion:{doc,_ in completions+=1;result=doc})
        wait("timed out provider advances to next source"){completions==1}
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
        check(completions==1 && result?.lines.first?.text=="超时回退","expired timers cannot complete an operation twice")
        let suite="dongx.shorelyrics.source-tests."+UUID().uuidString
        let modelPrefs=UserDefaults(suiteName:suite)!
        defer{modelPrefs.removePersistentDomain(forName:suite)}
        modelPrefs.set(true,forKey:"online")
        modelPrefs.set(try JSONEncoder().encode([custom,second]),forKey:"onlineSources")
        modelPrefs.set(second.id,forKey:"selectedOnlineSource")
        var live=track;live.bundle="test.player"
        SourceHTTP.reset([SourceHTTP.json(["data":[["lrc":"[00:01]指定来源"]]])])
        let model=AppModel(monitor:SourceMonitor(live),defaults:modelPrefs,session:session,isPlayerRunning:{_ in true})
        defer{model.stop()}
        model.start()
        wait("explicit source selection matches only that provider"){!model.isLoadingLyrics && model.mainText=="指定来源"}
        check(SourceHTTP.urls.count==1 && SourceHTTP.urls[0].host=="second.example.test","explicit selection skips higher priority source")
        model.online=false
        wait("online switch cancels and finishes offline lookup"){!model.isLoadingLyrics}
        let count=SourceHTTP.urls.count
        model.moveOnlineSources(from:IndexSet(integer:1),to:0)
        check(model.onlineSources.first?.id==second.id && SourceHTTP.urls.count==count,"reordering while offline persists without network requests")
        let saved=OnlineLyricsSource.restored(modelPrefs.data(forKey:"onlineSources"))
        check(saved.first?.id==second.id,"drag reorder writes priority configuration")
        model.moveOnlineSource(second.id,to:custom.id)
        check(model.onlineSources[1].id==second.id,"dragging first source onto second row puts it in second position")
        model.moveOnlineSource(second.id,to:custom.id)
        check(model.onlineSources[0].id==second.id,"dragging second source onto first row puts it in first position")
        let order=model.onlineSources.map{$0.id}
        model.moveOnlineSource("missing-id",to:custom.id)
        check(model.onlineSources.map{$0.id}==order,"invalid or external drag payload cannot alter ordering")
        model.restoreOnlineSourcesDefaults()
        check(model.onlineSources.prefix(6).map{$0.id}==sources.map{$0.id},"restoring defaults applies requested built-in order")
        check(model.onlineSources.filter{$0.enabled && $0.builtIn}.map{$0.id}==["netease","qq","kugou","lrclib"],"restoring defaults enables first four providers")
        check(model.onlineSources.contains{$0.id==custom.id} && model.onlineSources.contains{$0.id==second.id},"restoring built-in defaults preserves custom providers")
        let native=OnlineSourceTable(model:model,sources:model.onlineSources,edit:{_ in})
        let coordinator=native.makeCoordinator(),table=ReloadCountingTable()
        table.dataSource=coordinator;coordinator.table=table
        coordinator.refresh(native)
        let reloads=table.reloadCount
        for _ in 0..<10{coordinator.refresh(native)}
        check(table.reloadCount==reloads,"playback refreshes cannot reload native rows during a drag")
        check(coordinator.numberOfRows(in:table)==model.onlineSources.count,"native table includes every source")
        let writer=coordinator.tableView(table,pasteboardWriterForRow:0) as? NSPasteboardItem
        check(writer?.string(forType:NSPasteboard.PasteboardType("dongx.shorelyrics.source"))==model.onlineSources[0].id,"native drag writes a source identifier onto pasteboard")
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("enabled"))
        let checkbox=coordinator.tableView(table,viewFor:column,row:0)?.subviews.first as? NSButton
        check(checkbox?.focusRingType == NSFocusRingType.none && checkbox?.state == .on,"native checkbox uses enabled state without a focus ring")
        model.removeOnlineSource(second)
        check(model.selectedOnlineSource.isEmpty && !model.onlineSources.contains{$0.id==second.id},"removing selected custom source restores automatic selection")
        print("PASS: \(checks) online source checks (mocked HTTP; no external requests)")
    }
}
