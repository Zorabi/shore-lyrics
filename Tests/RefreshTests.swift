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
    static func defaults()->(UserDefaults,String){let name="local.shorelyrics.tests."+UUID().uuidString;let value=UserDefaults(suiteName:name)!;value.set(true,forKey:"online");return(value,name)}
    static func paused()->PlaybackSnapshot{PlaybackSnapshot(capturedAt:Date().timeIntervalSince1970,playing:false,rate:0,bundle:"test.thirdparty.player",title:"Refresh Song",artist:"Refresh Artist",album:"Test Album",duration:300,position:42)}
    static func main()throws{
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
