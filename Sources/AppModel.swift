// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ApplicationServices

private final class LyricsSessionGuard:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){
        completionHandler(request.url?.scheme=="https" && request.url?.host=="lrclib.net" ? request : nil)
    }
}
final class AppModel:ObservableObject {
    @Published var dockPadding:Double=0 {didSet{defaults.set(dockPadding,forKey:"dockPadding")}}
    @Published var dockOffset:Double=0 {didSet{defaults.set(dockOffset,forKey:"dockOffset")}}
    @Published var dockCornerRadius:CGFloat=18
    @Published var dockGeometryDetails=""
    @Published var dockStatus="正在读取 Dock 布局…"
    @Published var dockExact=false
    @Published var dockTrusted=false
    @Published var isLoadingLyrics=false
    @Published var snapshot:PlaybackSnapshot?
    @Published var document:LyricsDocument?
    @Published var lyricJumped=false
    @Published var position:Double=0
    @Published var playerName="等待播放器"
    @Published var state="打开任意向 macOS 发布播放信息的播放器"
    @Published var libraryStatus="尚未添加本地歌词来源"
    @Published var roots:[String]=[]
    @Published var fileCount=0
    @Published var matchedFile:URL?
    @Published var overlayVisible=true {didSet{defaults.set(overlayVisible,forKey:"overlayVisible")}}
    @Published var hidePaused=true {didSet{defaults.set(hidePaused,forKey:"hidePaused")}}
    @Published var hideNearDock=true {didSet{defaults.set(hideNearDock,forKey:"hideNearDock")}}
    @Published var twoLines=true {didSet{defaults.set(twoLines,forKey:"twoLines")}}
    @Published var karaokeEnabled=true {didSet{defaults.set(karaokeEnabled,forKey:"karaokeEnabled")}}
    @Published var karaokeColor:Color = .teal {
        didSet {
            guard let color=NSColor(karaokeColor).usingColorSpace(.sRGB) else{return}
            defaults.set([Double(color.redComponent),Double(color.greenComponent),Double(color.blueComponent)],forKey:"karaokeColor")
        }
    }
    @Published var fontSize:Double=22 {didSet{defaults.set(fontSize,forKey:"fontSize")}}
    @Published var opacity:Double=0.88 {didSet{defaults.set(opacity,forKey:"opacity")}}
    @Published var offset:Double=0 {didSet{defaults.set(offset,forKey:"offset")}}
    @Published var placement="dock" {didSet{defaults.set(placement,forKey:"placement")}}
    @Published var theme="glass" {didSet{defaults.set(theme,forKey:"theme")}}
    @Published var display="main" {didSet{defaults.set(display,forKey:"display")}}
    @Published var online=false {didSet{defaults.set(online,forKey:"online");if initialized{reloadLyrics()}}}
    @Published var previewUntil=Date.distantPast
    let library=MusicLibrary()
    private let defaults:UserDefaults
    private let suppliedSession:URLSession?
    private let isPlayerRunning:(String)->Bool
    private let worker=DispatchQueue(label:"local.shorelyrics.library",qos:.userInitiated)
    private let monitor:PlaybackMonitoring
    private var pendingRefresh:(id:UUID,preferOnline:Bool)?
    private let refreshTimeout:TimeInterval
    private var timer:Timer?
    private var generation=0
    private var lastReceived=Date.distantPast
    private var onlineTask:URLSessionDataTask?
    private var manual:[String:String]=[:]
    private var initialized=false
    private var cache:[String:LyricsDocument]=[:]
    private let networkGuard=LyricsSessionGuard()
    private lazy var session:URLSession = {
        if let suppliedSession{return suppliedSession}
        let config=URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies=false;config.httpCookieStorage=nil;config.urlCache=nil
        config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15
        return URLSession(configuration:config,delegate:networkGuard,delegateQueue:nil)
    }()
    init(monitor:PlaybackMonitoring=NowPlayingMonitor(),defaults:UserDefaults = .standard,session:URLSession?=nil,
         isPlayerRunning:@escaping(String)->Bool={ !NSRunningApplication.runningApplications(withBundleIdentifier:$0).isEmpty },refreshTimeout:TimeInterval=6){
        self.monitor=monitor;self.defaults=defaults;self.suppliedSession=session;self.isPlayerRunning=isPlayerRunning;self.refreshTimeout=refreshTimeout
        defaults.register(defaults:["karaokeEnabled":true,"overlayVisible":true,"hidePaused":true,"hideNearDock":true,"twoLines":true,"fontSize":22.0,"opacity":0.88,"offset":0.0,"placement":"dock","theme":"glass","display":"main","online":false])
        overlayVisible=defaults.bool(forKey:"overlayVisible");hidePaused=defaults.bool(forKey:"hidePaused");hideNearDock=defaults.bool(forKey:"hideNearDock");twoLines=defaults.bool(forKey:"twoLines")
        karaokeEnabled=defaults.bool(forKey:"karaokeEnabled")
        if let components=defaults.array(forKey:"karaokeColor") as? [Double],components.count==3,
           components.allSatisfy({$0.isFinite && (0...1).contains($0)}) {
            karaokeColor=Color(.sRGB,red:components[0],green:components[1],blue:components[2],opacity:1)
        }
        fontSize=max(16,min(34,defaults.double(forKey:"fontSize")));opacity=max(0.45,min(1,defaults.double(forKey:"opacity")));offset=max(-5,min(5,defaults.double(forKey:"offset")))
        placement=defaults.string(forKey:"placement") ?? "dock";theme=defaults.string(forKey:"theme") ?? "glass";display=defaults.string(forKey:"display") ?? "main";online=defaults.bool(forKey:"online")
        roots=defaults.stringArray(forKey:"roots") ?? [];manual=defaults.dictionary(forKey:"manualFiles") as? [String:String] ?? [:]
        // This upgrade adds the requested Dock fusion as the initial mode.
        if !defaults.bool(forKey:"dockFusionEnabledV2") {
            placement="dock";theme="glass";defaults.set("dock",forKey:"placement");defaults.set("glass",forKey:"theme");defaults.set(true,forKey:"dockFusionEnabledV2")
        }
        dockPadding=max(-20,min(20,defaults.double(forKey:"dockPadding")));dockOffset=max(-16,min(16,defaults.double(forKey:"dockOffset")))
        initialized=true
        monitor.onSnapshot={ [weak self] in self?.accept($0) }
        monitor.onStatus={ [weak self] in self?.state=$0 }
    }
    func start(){
        if !roots.isEmpty{rescan()}
        monitor.start()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){ [weak self] _ in self?.tick() }
    }
    func stop(){pendingRefresh=nil;generation+=1;isLoadingLyrics=false;timer?.invalidate();monitor.stop();onlineTask?.cancel();session.invalidateAndCancel()}
    private func tick(){
        if Date().timeIntervalSince(lastReceived)>4,snapshot != nil {
            generation+=1;onlineTask?.cancel();snapshot=nil;document=nil;matchedFile=nil;playerName="系统连接中断"
            if pendingRefresh==nil{isLoadingLyrics=false;state="正在重新读取播放信息…"}
        }
        position=snapshot?.elapsed() ?? 0
    }
    private func accept(_ new:PlaybackSnapshot){
        lastReceived=Date()
        let bundle=new.bundle ?? ""
        guard !bundle.isEmpty,let title=new.title,!title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,new.advertisement != true,
              isPlayerRunning(bundle) else{
            if snapshot != nil{generation+=1;onlineTask?.cancel();snapshot=nil;document=nil;matchedFile=nil}
            playerName="等待播放器"
            if pendingRefresh==nil{isLoadingLyrics=false;state=new.error ?? "系统尚未提供当前歌曲信息，可点击“刷新歌词”重试"}
            return
        }
        let changed=snapshot?.key != new.key
        let previous=snapshot
        let now=Date().timeIntervalSince1970
        lyricJumped=previous?.key != new.key || abs((previous?.elapsed(now:now) ?? 0)-new.elapsed(now:now))>0.6
        snapshot=new;position=new.elapsed(now:now)
        playerName=NSRunningApplication.runningApplications(withBundleIdentifier:bundle).first?.localizedName ?? bundle
        let refresh=pendingRefresh
        pendingRefresh=nil
        if changed || refresh != nil {
            if refresh != nil{cache.removeValue(forKey:new.key)}
            if changed{document=nil;matchedFile=nil}
            reloadLyrics(preferOnline:refresh?.preferOnline ?? false,preserveCurrent:!changed && refresh != nil)
        }
    }
    func addRoots(_ paths:[String]){
        roots=Array(Set(roots+paths.map{URL(fileURLWithPath:$0).standardizedFileURL.path})).sorted()
        defaults.set(roots,forKey:"roots");rescan()
    }
    func removeRoot(_ path:String){roots.removeAll{$0==path};defaults.set(roots,forKey:"roots");rescan()}
    func rescan(){
        generation+=1;onlineTask?.cancel();cache.removeAll();libraryStatus="正在整理本地音乐文件…"
        let paths=roots,library=library
        worker.async{ [weak self] in
            let count=library.scan(paths:paths)
            DispatchQueue.main.async{[weak self] in
                guard let self else{return}
                self.fileCount=count;self.libraryStatus=paths.isEmpty ? "可选：添加目录以匹配内嵌歌词" : "\(paths.count) 个目录 · \(count) 个音频文件"
                if self.pendingRefresh==nil{self.reloadLyrics()}
            }
        }
    }
    func reloadLyrics(preferOnline:Bool=false,preserveCurrent:Bool=false){
        generation+=1;let token=generation;onlineTask?.cancel();onlineTask=nil
        guard let track=snapshot else{if pendingRefresh==nil{isLoadingLyrics=false};return}
        isLoadingLyrics=true
        let key=track.key
        let retainedDocument=preserveCurrent ? document : nil,retainedFile=preserveCurrent ? matchedFile : nil
        if !preserveCurrent{document=nil;matchedFile=nil}
        if preferOnline && online{fetchOnline(track,token:token,retainedDocument:retainedDocument,retainedFile:retainedFile);return}
        if let cached=cache[key],online || !cached.source.hasPrefix("在线"){document=cached;matchedFile=cached.file;isLoadingLyrics=false;state=cached.timed ? "同步歌词已就绪" : "已读取歌词 · 无时间轴";return}
        state="正在读取本地歌词…"
        let library=library,selected=manual[key]
        worker.async { [weak self] in
            let result:LocalMatch
            if let selected {
                let url=URL(fileURLWithPath:selected)
                let doc=library.readSelectedFile(url)
                result=LocalMatch(document:doc,file:url,message:doc == nil ? "所选文件没有可读取的歌词，请重新选择" : "已读取手动选择的文件")
            } else {
                result=library.match(title:track.title ?? "",artist:track.artist ?? "",album:track.album ?? "",duration:track.duration ?? 0,fileURL:track.fileURL)
            }
            DispatchQueue.main.async{[weak self] in
                guard let self,self.generation==token,self.snapshot?.key==key else{return}
                if result.document != nil || retainedDocument==nil{self.matchedFile=result.file}
                if let doc=result.document {
                    self.document=doc;self.cache[key]=doc;self.isLoadingLyrics=false;self.state=doc.timed ? "同步歌词已就绪" : "已读取歌词 · 无时间轴"
                    // Keep real local plain text rather than pretending it is synchronized.
                } else if self.online {self.fetchOnline(track,token:token,retainedDocument:retainedDocument,retainedFile:retainedFile)}
                else {self.isLoadingLyrics=false;self.state=result.message+(retainedDocument == nil ? "" : "；继续显示已有歌词")}
            }
        }
    }
    func forceReload(){refreshLyrics()}
    func refreshLyrics(preferOnline:Bool=false){
        guard !preferOnline || online else{state="请先开启在线补充歌词";return}
        generation+=1;onlineTask?.cancel();onlineTask=nil
        if let key=snapshot?.key{cache.removeValue(forKey:key)}
        let library=library;worker.async{library.clearCache()}
        let request=UUID()
        pendingRefresh=(request,preferOnline)
        isLoadingLyrics=true;state="正在重新读取歌曲信息（无需恢复播放）…"
        monitor.refresh()
        DispatchQueue.main.asyncAfter(deadline:.now()+refreshTimeout){[weak self] in
            guard let self,self.pendingRefresh?.id==request else{return}
            self.pendingRefresh=nil;self.isLoadingLyrics=false
            self.state="刷新未读到当前歌曲信息；播放器可能尚未向系统发布信息，请稍后重试"
        }
    }
    private func fetchOnline(_ track:PlaybackSnapshot,token:Int,retainedDocument:LyricsDocument?=nil,retainedFile:URL?=nil){
        guard online,let title=track.title,!title.isEmpty,let artist=track.artist,!artist.isEmpty else{isLoadingLyrics=false;state="在线匹配需要歌名与歌手";return}
        var parts=URLComponents(string:"https://lrclib.net/api/get")!
        var query=[URLQueryItem(name:"track_name",value:title),URLQueryItem(name:"artist_name",value:artist)]
        if let album=track.album,!album.isEmpty{query.append(URLQueryItem(name:"album_name",value:album))}
        if let duration=track.duration,duration>=1,duration<=3600{query.append(URLQueryItem(name:"duration",value:String(Int(duration.rounded()))))}
        parts.queryItems=query
        var request=URLRequest(url:parts.url!);request.setValue("ShoreLyrics/0.1 (macOS)",forHTTPHeaderField:"User-Agent")
        state="正在向 LRCLIB 查询歌词…"
        onlineTask=session.dataTask(with:request){ [weak self] data,response,error in
            var doc:LyricsDocument?,message="在线来源没有匹配到歌词"
            if let error{message="在线查词失败：\(error.localizedDescription)"}
            else if let http=response as? HTTPURLResponse,http.statusCode==200,let data,data.count<=2*1024*1024,let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]{
                if json["instrumental"] as? Bool == true {doc=LyricsDocument(lines:[],plain:"纯音乐",source:"在线 · LRCLIB（纯音乐）")}
                else if let raw=(json["syncedLyrics"] as? String).flatMap({$0.isEmpty ? nil : $0}) ?? json["plainLyrics"] as? String {
                    let parsed=LyricsParser.parse(raw,source:"在线 · LRCLIB");if !parsed.isEmpty{doc=parsed}
                }
            }
            DispatchQueue.main.async{[weak self] in
                guard let self,self.online,self.generation==token,self.snapshot?.key==track.key else{return}
                self.isLoadingLyrics=false
                if let doc{self.document=doc;self.matchedFile=doc.file;self.cache[track.key]=doc;self.state=doc.timed ? "同步歌词已就绪" : "已读取在线歌词 · 无时间轴"}
                else{
                    if let retainedDocument{self.document=retainedDocument;self.matchedFile=retainedFile;self.cache[track.key]=retainedDocument}
                    self.state=message+(retainedDocument==nil ? "" : "；继续显示已有歌词")
                }
            }
        }
        onlineTask?.resume()
    }
    var currentIndex:Int? {document?.index(at:position+offset)}
    var lyricTransitionID:String {"\(snapshot?.key ?? "")|\(currentIndex.map(String.init) ?? "none")|\(primaryLyricText)"}
    var lyricProgress:Double? {lyricProgress(at:position)}
    func lyricProgress(at playbackPosition:Double)->Double? {
        guard karaokeEnabled, previewUntil <= Date(), let doc=document, let index=doc.index(at:playbackPosition+offset),
              !doc.lines[index].text.isEmpty else { return nil }
        var line=doc.lines[index]
        line.text=line.text.components(separatedBy:"\n").first ?? line.text
        line.words=line.words.filter{$0.offset<=line.text.count}
        let end=line.end ?? (index+1 < doc.lines.count ? doc.lines[index+1].time : snapshot?.duration ?? line.time)
        return line.progress(at:playbackPosition+offset,until:end)
    }
    var mainText:String {
        if previewUntil>Date(){return "让每一句，留在眼前。"}
        guard let doc=document else{return snapshot?.title ?? "岸词"}
        if doc.timed {
            guard let index=currentIndex else{return position+offset<(doc.lines.first?.time ?? 0) ? "前奏 · 即将开始" : "间奏"}
            return doc.lines[index].text.isEmpty ? "间奏" : doc.lines[index].text
        }
        return doc.plain.components(separatedBy:.newlines).first(where:{!$0.trimmingCharacters(in:.whitespaces).isEmpty}) ?? "暂无歌词"
    }
    var primaryLyricText:String {mainText.components(separatedBy:"\n").first ?? mainText}
    var secondaryText:String {
        if previewUntil>Date(){return "岸词 SHORE LYRICS · 底部歌词预览"}
        if let doc=document,doc.timed {
            if let index=currentIndex {
                let translation=doc.lines[index].text.components(separatedBy:"\n").dropFirst().joined(separator:" · ")
                if !translation.isEmpty{return translation}
            }
            let next=(currentIndex ?? -1)+1
            return next<doc.lines.count ? doc.lines[next].text : ""
        }
        if let doc=document{return "无时间轴 · 可在设置中查看完整歌词（\(doc.source)）"}
        return state
    }
    var shouldShow:Bool {
        if previewUntil>Date(){return true}
        guard overlayVisible,let snapshot else{return false}
        return !hidePaused || snapshot.playing
    }
    func preview(){previewUntil=Date().addingTimeInterval(10)}
    func requestDockLayoutAccess(){
        _=AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"){NSWorkspace.shared.open(url)}
    }
    func chooseRoots(){
        let panel=NSOpenPanel();panel.title="添加本地歌词来源（可选）";panel.message="播放器读取不受此目录限制。仅在这里匹配音频内嵌歌词和旁挂歌词。";panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=true
        if panel.runModal() == .OK{addRoots(panel.urls.map(\.path))}
    }
    func chooseFile(){
        guard let key=snapshot?.key else{return}
        let panel=NSOpenPanel();panel.title="为当前歌曲选择歌词或音频文件";panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.allowedContentTypes=(Array(MusicLibrary.extensions)+["lrc","srt","txt"]).compactMap{UTType(filenameExtension:$0)}
        if panel.runModal() == .OK,let url=panel.url{manual[key]=url.path;defaults.set(manual,forKey:"manualFiles");cache.removeValue(forKey:key);reloadLyrics()}
    }
    func clearManual(){guard let key=snapshot?.key else{return};manual.removeValue(forKey:key);defaults.set(manual,forKey:"manualFiles");cache.removeValue(forKey:key);reloadLyrics()}
    func revealFile(){if let matchedFile{NSWorkspace.shared.activateFileViewerSelecting([matchedFile])}}
}
