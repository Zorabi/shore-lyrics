// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import AppKit

struct PlaybackSnapshot: Codable {
    var capturedAt: Double
    var playing: Bool
    var rate: Double
    var bundle: String?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var position: Double?
    var fileURL: String?
    var advertisement: Bool?
    var error: String?
    var key: String { [bundle ?? "",title ?? "",artist ?? "",album ?? "",String(Int((duration ?? 0).rounded()))].joined(separator:"\u{1f}") }
    func elapsed(now: Double = Date().timeIntervalSince1970) -> Double {
        let anchor = position ?? 0
        let extra = playing ? max(0,min(3,now-capturedAt))*max(0,min(rate,4)) : 0
        let result=max(0,anchor+extra)
        return (duration ?? 0)>0 ? min(duration!,result) : result
    }
}
protocol PlaybackMonitoring:AnyObject {
    var onSnapshot:((PlaybackSnapshot)->Void)? {get set}
    var onStatus:((String)->Void)? {get set}
    func start()
    func refresh()
    func stop()
}
final class NowPlayingMonitor:PlaybackMonitoring {
    var onSnapshot: ((PlaybackSnapshot)->Void)?
    var onStatus: ((String)->Void)?
    private var process: Process?
    private var pipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer=Data()
    private var bufferGeneration=0
    private var sessionGeneration=0
    private let queue=DispatchQueue(label:"local.shorelyrics.nowplaying")
    private var stopped=false
    private let scriptURL:URL?
    init(scriptURL:URL?=nil){self.scriptURL=scriptURL}
    func start() {
        guard process == nil, !stopped else{return}
        guard let script=scriptURL ?? Bundle.main.url(forResource:"NowPlaying",withExtension:"js") else{onStatus?("系统读取脚本缺失，请重新构建应用");return}
        sessionGeneration+=1
        let token=sessionGeneration
        queue.async{[weak self] in self?.buffer.removeAll();self?.bufferGeneration=token}
        let task=Process(),out=Pipe(),err=Pipe()
        task.executableURL=URL(fileURLWithPath:"/usr/bin/osascript")
        task.arguments=["-l","JavaScript",script.path]
        task.standardOutput=out;task.standardError=err
        process=task;pipe=out;errorPipe=err
        out.fileHandleForReading.readabilityHandler={ [weak self] handle in
            let data=handle.availableData
            guard !data.isEmpty else{return}
            self?.queue.async{ [weak self] in self?.consume(data,token:token) }
        }
        err.fileHandleForReading.readabilityHandler={handle in _=handle.availableData}
        task.terminationHandler={ [weak self] ended in
            DispatchQueue.main.async {
                guard let self,token==self.sessionGeneration,self.process === ended else{return}
                self.detach()
                if !self.stopped {
                    self.onStatus?("系统读取已断开，正在重新连接…")
                    DispatchQueue.main.asyncAfter(deadline:.now()+2){[weak self] in
                        guard let self,self.sessionGeneration==token else{return}
                        self.start()
                    }
                }
            }
        }
        do{try task.run()}catch{detach();onStatus?("无法启动系统读取：\(error.localizedDescription)")}
    }
    private func consume(_ data:Data,token:Int) {
        guard token==bufferGeneration else{return}
        buffer.append(data)
        if buffer.count>2*1024*1024 {buffer.removeAll();return}
        while let newline=buffer.firstIndex(of:10) {
            let line=buffer[..<newline];buffer.removeSubrange(...newline)
            guard let snapshot=try? JSONDecoder().decode(PlaybackSnapshot.self,from:Data(line)),snapshot.capturedAt.isFinite,snapshot.rate.isFinite else{continue}
            DispatchQueue.main.async{[weak self] in
                guard let self,!self.stopped,token==self.sessionGeneration else{return}
                self.onSnapshot?(snapshot)
            }
        }
    }
    private func detach(){
        process?.terminationHandler=nil
        pipe?.fileHandleForReading.readabilityHandler=nil
        errorPipe?.fileHandleForReading.readabilityHandler=nil
        if process?.isRunning==true{process?.terminate()}
        process=nil;pipe=nil;errorPipe=nil
    }
    func refresh(){
        // A new reader creates a fresh system request, including when paused.
        sessionGeneration+=1;detach();stopped=false;start()
    }
    func stop(){stopped=true;sessionGeneration+=1;detach()}
    deinit{stop()}
}
