// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AppKit

/// Offline layout previews use only synthetic metadata and isolated preferences.
@main enum InterfacePreview {
    static func main()throws {
        _=NSApplication.shared
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        for dark in [false,true] {
            for width:CGFloat in [820,1100] {
                for page in Page.allCases {
                    let suite="dongx.shorelyrics.interface-preview."+UUID().uuidString
                    let prefs=UserDefaults(suiteName:suite)!
                    let model=AppModel(defaults:prefs)
                    model.theme="custom";model.customLyricColor=Color(red:1,green:0.85,blue:0.65)
                    model.customSecondaryColor=Color(red:0.65,green:0.75,blue:0.9)
                    model.customBackgroundColor=Color(red:0.08,green:0.12,blue:0.2)
                    model.snapshot=PlaybackSnapshot(capturedAt:Date().timeIntervalSince1970,playing:false,rate:0,bundle:"dongx.exampleplayer",title:"用于检查页面边界的示例歌曲名称",artist:"示例歌手",album:"用于检查长文本排版的示例专辑名称",duration:180,position:30)
                    model.position=30;model.playerName="示例播放器"
                    model.document=LyricsParser.parse("[00:01]这是一句用于检查长歌词显示的示例文字\n[00:40]这是下一句示例歌词",source:"在线 · 这是用于检查长来源名称是否挤出页面边界的测试来源")
                    model.roots=["/示例目录/用于检查长路径换行的音乐文件夹/本地歌曲","/示例目录/第二个本地歌曲文件夹"]
                    model.fileCount=1234;model.libraryStatus="2 个目录 · 1234 个音频文件"
                    model.state="这是用于验证状态信息自动换行的长文本。在线来源未能匹配到歌词时继续使用已有歌词，操作按钮应始终留在卡片范围内。"
                    let root=SettingsView(model:model,page:page).environment(\.colorScheme,dark ? .dark : .light)
                    let view=NSHostingView(rootView:root)
                    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:1700),styleMask:[.borderless],backing:.buffered,defer:false)
                    window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
                    window.contentView=view;view.frame=NSRect(x:0,y:0,width:width,height:1700)
                    view.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.03))
                    guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{fatalError("Unable to render preview")}
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    let name="interface-\(page.rawValue)-\(Int(width))-\(dark ? "dark" : "light").png"
                    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
                    window.close();model.stop();prefs.removePersistentDomain(forName:suite)
                }
            }
        }
        for dark in [false,true] {
            for format in OnlineLyricsSource.Format.allCases {
                var source=OnlineLyricsSource(name:"示例来源",urlTemplate:"https://lyrics.example.com/api?title={title}&artist={artist}&album={album}&duration={duration}")
                source.format=format
                let root=OnlineSourceEditor(source:source,save:{_ in}).environment(\.colorScheme,dark ? .dark : .light)
                let view=NSHostingView(rootView:root)
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:760),styleMask:[.borderless],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
                window.contentView=view;view.frame=NSRect(x:0,y:0,width:540,height:760)
                view.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date(timeIntervalSinceNow:0.03))
                let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("interface-editor-\(format.rawValue)-\(dark ? "dark" : "light").png"))
                window.close()
            }
        }
        print("Rendered 20 offline interface previews")
    }
}
