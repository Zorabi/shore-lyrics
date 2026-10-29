// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import AppKit

private final class FakeMonitor:PlaybackMonitoring {
    var onSnapshot:((PlaybackSnapshot)->Void)?
    var onStatus:((String)->Void)?
    var next:PlaybackSnapshot?
    var refreshCount=0
    func start(){if let next{onSnapshot?(next)}}
    func refresh(){refreshCount+=1;if var next{next.capturedAt=Date().timeIntervalSince1970;onSnapshot?(next)}}
    func stop(){}
}
private final class MockLyricsHTTP:URLProtocol {
    struct Reply {var status:Int;var text:String}
    private static let lock=NSLock()
    private static var replies:[Reply]=[]
    private static var requests:[URLRequest]=[]
    static func reset(_ values:[Reply]){lock.lock();replies=values;requests=[];lock.unlock()}
    static var count:Int{lock.lock();defer{lock.unlock()};return requests.count}
    static var last:URLRequest?{lock.lock();defer{lock.unlock()};return requests.last}
    override class func canInit(with request:URLRequest)->Bool{request.url?.host=="lrclib.net"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        Self.lock.lock();Self.requests.append(request)
        let reply=Self.replies.isEmpty ? Reply(status:404,text:"") : Self.replies.removeFirst();Self.lock.unlock()
        if reply.status == -2 {return} // Deliberately stalled transport for timeout/cancel coverage.
        if reply.status<0 {client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet));return}
        let body=try! JSONSerialization.data(withJSONObject:["syncedLyrics":reply.text])
        let response=HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}

@main enum RefreshTests {
    static var checks=0
    static func check(_ condition:@autoclosure()->Bool,_ description:String){guard condition()else{fputs("FAIL: \(description)\n",stderr);exit(1)};checks+=1}
    static func wait(_ description:String,timeout:TimeInterval=3,_ predicate:()->Bool){
        let deadline=Date().addingTimeInterval(timeout)
        while !predicate() && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        check(predicate(),description)
    }
    static func session()->URLSession{let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockLyricsHTTP.self];return URLSession(configuration:config)}
    static func defaults()->(UserDefaults,String){let name="local.shorelyrics.tests."+UUID().uuidString;let value=UserDefaults(suiteName:name)!;value.set(true,forKey:"online");value.set(try! JSONEncoder().encode(OnlineLyricsSource.defaults.map{source in var item=source;item.enabled=item.id=="lrclib";return item}),forKey:"onlineSources");return(value,name)}
    static func paused()->PlaybackSnapshot{PlaybackSnapshot(capturedAt:Date().timeIntervalSince1970,playing:false,rate:0,bundle:"test.thirdparty.player",title:"Refresh Song",artist:"Refresh Artist",album:"Test Album",duration:300,position:42)}
    static func main()throws{
        do{
            let(prefs,name)=defaults()
            let model=AppModel(monitor:FakeMonitor(),defaults:prefs,session:session())
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.document=LyricsParser.parse("[00:01]原文\n[00:01]翻译\n[00:03]下一句",source:"test")
            model.position=2
            check(model.primaryLyricText=="原文" && model.secondaryText=="翻译","bilingual lyrics keep translation on uncolored secondary row")
            check(model.lyricProgress != nil,"karaoke enabled by default")
            check(model.karaokeSpeed==1.2,"default ordinary LRC sweep speed is 120 percent")
            let identity=model.lyricTransitionID
            check(abs((model.lyricProgress(at:2.5) ?? 0)-0.9)<0.001,"display frame projects progress without changing model position")
            check(model.position==2,"display frame never advances paused playback state")
            for time in [1.0,1.5,2.0,2.5,2.99] {
                check(abs((model.lyricProgress(at:time) ?? -1)-min(1,(time-1)/2*1.2))<0.001,"plain lyric display uses faster estimation without changing playback time")
            }
            model.position=1.25
            check(abs((model.lyricProgress ?? 0)-0.15)<0.001,"backward seek aligns immediately without interpolation")
            model.position=3.1
            check(model.lyricTransitionID != identity,"line identity follows timestamps for transitions")

            model.karaokeSpeed=1
            check(abs((model.lyricProgress(at:2) ?? 0)-0.5)<0.001,"speed setting updates ordinary LRC immediately")
            model.karaokeSpeed=1.6
            model.karaokeEnabled=false
            check(model.lyricProgress==nil && !prefs.bool(forKey:"karaokeEnabled"),"karaoke toggle disables highlight and persists")
            model.karaokeColor = .red
            let restored=AppModel(monitor:FakeMonitor(),defaults:prefs,session:session())
            defer{restored.stop()}
            check(restored.karaokeSpeed==1.6,"custom sweep speed persists across model initialization")
            check(!restored.karaokeEnabled && (prefs.array(forKey:"karaokeColor") as? [Double])?.first==1,"custom highlight color persists")
        }
        // Online priority overrides embedded lyrics, with local fallback and cache isolation.
        do{
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer{try? FileManager.default.removeItem(at:folder)}
            let audio=folder.appendingPathComponent("embedded.mp3")
            let payload:[UInt8]=[3]+Array("eng".utf8)+[0]+Array("[00:01]文件内嵌歌词".utf8)
            func big(_ n:Int)->[UInt8]{[UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]}
            let frame=Array("USLT".utf8)+big(payload.count)+[0,0]+payload
            let size=frame.count
            let header:[UInt8]=[73,68,51,3,0,0,UInt8((size>>21)&127),UInt8((size>>14)&127),UInt8((size>>7)&127),UInt8(size&127)]
            try Data(header+frame).write(to:audio)
            var track=paused();track.fileURL=audio.absoluteString
            let monitor=FakeMonitor();monitor.next=track
            let(prefs,name)=defaults()
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true})
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            MockLyricsHTTP.reset([])
            model.start()
            wait("local embedded lyrics load without network by default"){!model.isLoadingLyrics && model.mainText=="文件内嵌歌词"}
            check(MockLyricsHTTP.count==0 && !model.preferOnlineLyrics,"online priority is opt in")
            MockLyricsHTTP.reset([.init(status:200,text:"[00:01]网络歌词")])
            model.preferOnlineLyrics=true
            wait("enabling online priority replaces embedded lyrics"){!model.isLoadingLyrics && model.mainText=="网络歌词"}
            check(MockLyricsHTTP.count==1 && prefs.bool(forKey:"preferOnlineLyrics"),"priority is persisted and ignores local document cache")
            model.preferOnlineLyrics=false
            wait("disabling priority restores embedded lyrics instead of online cache"){!model.isLoadingLyrics && model.mainText=="文件内嵌歌词"}
            check(MockLyricsHTTP.count==1,"restoring local priority needs no new online request")
            MockLyricsHTTP.reset([.init(status:404,text:"")])
            model.preferOnlineLyrics=true
            wait("online miss falls back to embedded lyrics"){MockLyricsHTTP.count==1 && !model.isLoadingLyrics}
            check(model.mainText=="文件内嵌歌词" && model.matchedFile==audio,"online miss preserves local lyrics and matched file")
            MockLyricsHTTP.reset([.init(status:500,text:"")])
            model.reloadLyrics()
            wait("online service failure falls back to local lyrics"){MockLyricsHTTP.count==1 && !model.isLoadingLyrics}
            check(model.mainText=="文件内嵌歌词","server failure retains embedded lyrics")
            MockLyricsHTTP.reset([.init(status:-1,text:"")])
            model.reloadLyrics()
            wait("transport failure finishes online priority lookup"){MockLyricsHTTP.count==1 && !model.isLoadingLyrics}
            check(model.mainText=="文件内嵌歌词" && model.state.contains("失败"),"offline network error keeps local fallback")
            model.online=false
            wait("online off ignores stored online priority"){!model.isLoadingLyrics}
            check(MockLyricsHTTP.count==1 && model.mainText=="文件内嵌歌词","online privacy switch still prevents requests")
            let restored=AppModel(monitor:FakeMonitor(),defaults:prefs,session:session())
            defer{restored.stop()}
            check(restored.preferOnlineLyrics && !restored.online,"online priority persists independently of online permission")
            let unchangedAudio=try Data(contentsOf:audio)
            check(unchangedAudio==Data(header+frame),"online preference never modifies embedded audio")
        }
        do{
            MockLyricsHTTP.reset([.init(status:200,text:"[00:01]已有网络歌词")])
            let monitor=FakeMonitor();monitor.next=paused();let(prefs,name)=defaults()
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true},onlineTimeout:0.2)
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.start()
            wait("online document available before refresh retry"){model.mainText=="已有网络歌词" && !model.isLoadingLyrics}
            MockLyricsHTTP.reset([.init(status:-2,text:"")])
            model.refreshLyrics(preferOnline:true)
            wait("online refresh starts without restarting metadata reader"){MockLyricsHTTP.count==1}
            check(model.isMatchingOnline && model.isLoadingLyrics && monitor.refreshCount==0,"online retry has separate loading state and leaves playback connection intact")
            check(model.mainText=="已有网络歌词","online refresh retains current lyric until new result arrives")
            MockLyricsHTTP.reset([.init(status:200,text:"[00:01]重新匹配成功")])
            model.refreshLyrics(preferOnline:true)
            wait("in-flight online refresh can be canceled and retried"){!model.isMatchingOnline && !model.isLoadingLyrics && model.mainText=="重新匹配成功"}
            MockLyricsHTTP.reset([.init(status:-2,text:"")])
            model.refreshLyrics(preferOnline:true)
            wait("online deadline releases loading states",timeout:1){!model.isMatchingOnline && !model.isLoadingLyrics && model.state.contains("超时")}
            check(model.mainText=="重新匹配成功","online timeout retains previously matched lyric")
            MockLyricsHTTP.reset([.init(status:-2,text:"")])
            model.refreshLyrics(preferOnline:true)
            wait("another online attempt can start after timeout"){MockLyricsHTTP.count==1}
            model.online=false
            wait("turning online off cancels stalled request"){!model.isMatchingOnline && !model.isLoadingLyrics}
            check(!model.online && monitor.refreshCount==0,"online retries never restart the player metadata connection")
        }
        // A paused first lookup may fail; refreshing the unchanged song must retry.
        do{
            MockLyricsHTTP.reset([.init(status:404,text:""),.init(status:200,text:"[00:01.00]刷新成功"),.init(status:200,text:"[00:02.00]再次更新"),.init(status:404,text:"")])
            let monitor=FakeMonitor();monitor.next=paused();let(prefs,name)=defaults()
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true})
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.start()
            wait("paused startup attempts online matching"){MockLyricsHTTP.count==1 && !model.isLoadingLyrics}
            check(model.snapshot?.playing==false,"matching never resumes playback")
            check(model.document==nil && model.state.contains("没有匹配"),"first miss has a recoverable state")
            model.forceReload()
            wait("refresh retries the exact same paused track after a miss"){MockLyricsHTTP.count==2 && model.document?.lines.first?.text=="刷新成功" && !model.isLoadingLyrics}
            check(monitor.refreshCount==1,"refresh restarts the playback metadata reader")
            check(model.position==42 && model.snapshot?.playing==false,"paused position remains frozen after refresh")
            model.forceReload()
            wait("manual refresh bypasses a successful in-memory lyric cache"){MockLyricsHTTP.count==3 && model.document?.lines.first?.text=="再次更新"}
            model.refreshLyrics(preferOnline:true)
            wait("failed online retry preserves an existing good lyric"){MockLyricsHTTP.count==4 && !model.isLoadingLyrics && model.document?.lines.first?.text=="再次更新" && model.state.contains("继续显示")}
            let query=MockLyricsHTTP.last?.url?.absoluteString ?? ""
            check(!query.contains("/Users/") && !query.contains("file://"),"online retry sends no local filesystem path")
        }
        // Refresh works without an existing snapshot; it waits for a fresh one.
        do{
            MockLyricsHTTP.reset([.init(status:200,text:"[00:03.00]暂停启动补读")])
            let monitor=FakeMonitor();let(prefs,name)=defaults()
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true},refreshTimeout:0.5)
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.start();model.forceReload()
            check(model.isLoadingLyrics,"refresh with no track enters a visible loading state")
            monitor.onSnapshot?(PlaybackSnapshot(capturedAt:Date().timeIntervalSince1970,playing:false,rate:0))
            check(model.isLoadingLyrics,"a transient empty system sample does not cancel refresh")
            monitor.onSnapshot?(paused())
            wait("fresh paused metadata completes a pending refresh"){model.document?.lines.first?.text=="暂停启动补读" && !model.isLoadingLyrics}
        }
        // Missing system metadata must time out, not leave the refresh disabled.
        do{
            MockLyricsHTTP.reset([]);let monitor=FakeMonitor();let(prefs,name)=defaults()
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true},refreshTimeout:0.06)
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.start();model.forceReload()
            wait("refresh without published metadata ends its spinner",timeout:1){!model.isLoadingLyrics}
            check(model.state.contains("未读到") && MockLyricsHTTP.count==0,"no stale song or network query is invented")
        }
        // Online-off is honored even by the explicit online-refresh entry point.
        do{
            MockLyricsHTTP.reset([]);let monitor=FakeMonitor();monitor.next=paused();let(prefs,name)=defaults();prefs.set(false,forKey:"online")
            let model=AppModel(monitor:monitor,defaults:prefs,session:session(),isPlayerRunning:{_ in true})
            defer{model.stop();prefs.removePersistentDomain(forName:name)}
            model.start();wait("offline paused lookup finishes"){model.snapshot != nil && !model.isLoadingLyrics}
            model.refreshLyrics(preferOnline:true)
            check(MockLyricsHTTP.count==0 && monitor.refreshCount==0 && model.state.contains("开启"),"explicit online refresh cannot override the privacy switch")
        }
        // Exercise the real reader lifecycle: restart twice, reject old callbacks.
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:temp)}
        let script=temp.appendingPathComponent("snapshot.js")
        try """
        ObjC.import('Foundation');
        function run(){const out=$.NSFileHandle.fileHandleWithStandardOutput;for(let i=0;i<40;i++){const text=$.NSString.alloc.initWithUTF8String(JSON.stringify({capturedAt:Date.now()/1000,playing:false,rate:0,bundle:'test.player',title:'Paused',position:42})+'\\n');out.writeData(text.dataUsingEncoding($.NSUTF8StringEncoding));$.NSThread.sleepForTimeInterval(0.03);}}
        """.write(to:script,atomically:true,encoding:.utf8)
        let real=NowPlayingMonitor(scriptURL:script);var snapshots=0
        real.onSnapshot={_ in snapshots+=1};real.start()
        wait("real metadata reader starts"){snapshots>=1}
        real.refresh();real.refresh();let before=snapshots
        wait("real metadata reader survives rapid refreshes"){snapshots>before}
        real.stop();let stopped=snapshots
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        check(snapshots==stopped,"stopped or superseded readers cannot publish late callbacks")
        print("PASS: \(checks) refresh and paused-startup checks (mocked HTTP; no external requests)")
    }
}
