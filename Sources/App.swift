// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import SwiftUI
import Combine

private final class LyricsPanel:NSPanel {
    override var canBecomeKey:Bool{false}
    override var canBecomeMain:Bool{false}
}
final class OverlayController {
    let model:AppModel
    private let panel:LyricsPanel
    private let surface=NSVisualEffectView()
    private let host:NSHostingView<OverlayView>
    private let dockReader=DockLayoutReader()
    private var timer:Timer?
    init(model:AppModel){
        self.model=model
        host=NSHostingView(rootView:OverlayView(model:model))
        panel=LyricsPanel(contentRect:NSRect(x:0,y:0,width:850,height:70),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="岸词 · Dock 歌词"
        panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=false
        panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.ignoresMouseEvents=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        let container=NSView(frame:panel.contentView!.bounds)
        container.wantsLayer=true;container.layer?.masksToBounds=true;container.layer?.cornerCurve = .continuous
        surface.frame=container.bounds;surface.autoresizingMask=[.width,.height]
        surface.material = .popover;surface.blendingMode = .behindWindow;surface.state = .active
        host.frame=container.bounds;host.autoresizingMask=[.width,.height]
        container.addSubview(surface);container.addSubview(host);panel.contentView=container
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self] _ in self?.update()}
    }
    private func update(){
        guard let primary=NSScreen.screens.first else{return}
        let layout=dockReader.read()
        if let layout {
            let label=layout.exact ? "已精确跟随 Dock · \(layout.orientation=="bottom" ? "底部融合" : "侧边贴靠")" : "正在估算 Dock 布局 · 可授权精确跟随"
            if model.dockStatus != label{model.dockStatus=label}
            if model.dockExact != layout.exact{model.dockExact=layout.exact}
            if model.dockTrusted != layout.trusted{model.dockTrusted=layout.trusted}
            if model.dockCornerRadius != layout.cornerRadius{model.dockCornerRadius=layout.cornerRadius}
        }
        guard model.shouldShow else{panel.orderOut(nil);return}
        let mouse=NSEvent.mouseLocation
        let fused=model.placement=="dock"
        var screen=model.display=="mouse" ? NSScreen.screens.first(where:{$0.frame.contains(mouse)}) ?? primary : primary
        if fused,let layout{screen=layout.screen}
        let frame=screen.frame,visible=screen.visibleFrame
        let height:CGFloat=model.twoLines ? 116 : 76
        let width=min(900,max(320,frame.width-100))
        var rect=NSRect(x:frame.midX-width/2,y:visible.minY+12,width:width,height:height)
        if fused,let layout{
            if !layout.visible && model.previewUntil<Date(){panel.orderOut(nil);return}
            if layout.orientation=="bottom" {
                rect=layout.frame.insetBy(dx:-CGFloat(model.dockPadding),dy:0)
                rect.origin.y+=CGFloat(model.dockOffset)
                // A preview can reveal the expected position for an autohidden Dock.
                if !layout.visible{rect.origin.y=screen.frame.minY}
            } else {
                rect.origin.x=layout.orientation=="left" ? visible.minX+10 : visible.maxX-width-10
                rect.origin.y=frame.midY-height/2
            }
        }else if model.placement=="bottom"{rect=DockGeometry.bottomStrip(screen:frame,twoLines:model.twoLines)}
        rect.size.width=max(160,rect.width);rect.size.height=max(38,rect.height)
        panel.level=model.placement=="above" ? .floating : .statusBar
        panel.hasShadow = model.placement=="above"
        if panel.frame != rect{panel.setFrame(rect,display:true)}
        panel.contentView?.layer?.cornerRadius=model.placement=="bottom" ? 0 : fused && layout?.orientation=="bottom" ? min(layout?.cornerRadius ?? 18,min(rect.width,rect.height)/2) : 18
        if let layout {
            let detail="Dock \(NSStringFromRect(layout.frame)) · 面板 \(NSStringFromRect(rect)) · R \(String(format:"%.1f",layout.cornerRadius))"
            if model.dockGeometryDetails != detail{model.dockGeometryDetails=detail}
        }
        surface.isHidden=model.theme != "glass"
        surface.alphaValue=fused ? 1 : model.opacity
        let dockZone=layout?.frame.insetBy(dx:-24,dy:-20)
        let pointerNearDock=dockZone?.contains(mouse) ?? false
        let pointerNearLyrics=rect.insetBy(dx:-16,dy:-10).contains(mouse)
        // Fusion always yields to the pointer so icons stay visible when used.
        if (fused || model.hideNearDock) && model.previewUntil<Date() && (pointerNearLyrics || pointerNearDock){panel.orderOut(nil);return}
        if !panel.isVisible{panel.orderFrontRegardless()}
    }
    func stop(){timer?.invalidate();panel.orderOut(nil)}
}
final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=AppModel()
    private var overlay:OverlayController?
    private var settings:NSWindow?
    private var status:NSStatusItem?
    private var visibleItem:NSMenuItem?
    private var menuTimer:Timer?
    func applicationDidFinishLaunching(_ notification:Notification){
        let args=CommandLine.arguments
        for i in args.indices where args[i]=="--add-root" && i+1<args.count {model.addRoots([args[i+1]])}
        if args.contains("--diagnose"){
            model.start()
            Timer.scheduledTimer(withTimeInterval:6,repeats:false){[weak self] _ in
                guard let self else{return}
                let report:[String:Any]=[
                    "hasTrack":self.model.snapshot != nil,
                    "player":self.model.playerName,
                    "bundle":self.model.snapshot?.bundle ?? "",
                    "playing":self.model.snapshot?.playing ?? false,
                    "position":self.model.position,
                    "localFileMatched":self.model.matchedFile != nil,
                    "hasLyrics":self.model.document != nil,
                    "timed":self.model.document?.timed ?? false,
                    "lineCount":self.model.document?.lines.count ?? 0,
                    "source":self.model.document?.source ?? "",
                    "fileCount":self.model.fileCount,
                    "state":self.model.state,
                    "online":self.model.online
                ]
                if let json=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),let text=String(data:json,encoding:.utf8){print(text)}
                NSApplication.shared.terminate(nil)
            }
            return
        }
        configureMenu();overlay=OverlayController(model:model);model.start();showSettings()
    }
    private func configureMenu(){
        let main=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu(title:"岸词")
        appMenu.addItem(withTitle:"关于岸词",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        let settings=NSMenuItem(title:"岸词设置…",action:#selector(showSettings),keyEquivalent:",");settings.target=self;appMenu.addItem(settings)
        let refresh=NSMenuItem(title:"刷新歌词",action:#selector(refreshLyrics),keyEquivalent:"r");refresh.target=self;appMenu.addItem(refresh)
        appMenu.addItem(.separator())
        let services=NSMenuItem(title:"服务",action:nil,keyEquivalent:"")
        let servicesMenu=NSMenu(title:"服务");services.submenu=servicesMenu;appMenu.addItem(services);NSApp.servicesMenu=servicesMenu
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"隐藏岸词",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        let hideOthers=appMenu.addItem(withTitle:"隐藏其他应用",action:#selector(NSApplication.hideOtherApplications(_:)),keyEquivalent:"h")
        hideOthers.keyEquivalentModifierMask=[.command,.option]
        appMenu.addItem(withTitle:"全部显示",action:#selector(NSApplication.unhideAllApplications(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"退出岸词",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu=appMenu;main.addItem(appItem)
        let file=NSMenuItem(),fileMenu=NSMenu(title:"文件")
        fileMenu.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        file.submenu=fileMenu;main.addItem(file)
        let edit=NSMenuItem(),editMenu=NSMenu(title:"编辑")
        editMenu.addItem(withTitle:"撤销",action:Selector(("undo:")),keyEquivalent:"z")
        let redo=editMenu.addItem(withTitle:"重做",action:Selector(("redo:")),keyEquivalent:"z")
        redo.keyEquivalentModifierMask=[.command,.shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        editMenu.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        editMenu.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        editMenu.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        edit.submenu=editMenu;main.addItem(edit)
        let windowItem=NSMenuItem(),windowMenu=NSMenu(title:"窗口")
        windowMenu.addItem(withTitle:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"缩放",action:#selector(NSWindow.performZoom(_:)),keyEquivalent:"")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle:"前置全部窗口",action:#selector(NSApplication.arrangeInFront(_:)),keyEquivalent:"")
        windowItem.submenu=windowMenu;main.addItem(windowItem);NSApp.windowsMenu=windowMenu
        NSApp.mainMenu=main
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status?.button?.image=NSImage(systemSymbolName:"waveform.path",accessibilityDescription:"岸词")
        status?.button?.toolTip="岸词 · 系统播放器同步歌词"
        let menu=NSMenu()
        func item(_ title:String,_ action:Selector)->NSMenuItem{let row=NSMenuItem(title:title,action:action,keyEquivalent:"");row.target=self;menu.addItem(row);return row}
        _=item("打开岸词设置…",#selector(showSettings));menu.addItem(.separator())
        visibleItem=item("显示底部歌词",#selector(toggleOverlay))
        _=item("刷新歌词",#selector(refreshLyrics));_=item("预览歌词条",#selector(previewOverlay));_=item("选择歌词 / 音频…",#selector(chooseFile));_=item("添加歌词匹配目录…",#selector(chooseRoots))
        menu.addItem(.separator());_=item("退出岸词",#selector(quit))
        status?.menu=menu
        menuTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in guard let self else{return};self.visibleItem?.state=self.model.overlayVisible ? .on : .off}
    }
    @objc func showSettings(){
        if settings==nil{
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="岸词 · 设置";window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false
            window.minSize=NSSize(width:850,height:680);window.delegate=self
            window.contentView=NSHostingView(rootView:SettingsView(model:model));window.center();settings=window
        }
        NSApp.activate(ignoringOtherApps:true);settings?.deminiaturize(nil);settings?.makeKeyAndOrderFront(nil)
    }
    @objc func toggleOverlay(){model.overlayVisible.toggle()}
    @objc func refreshLyrics(){model.forceReload()}
    @objc func previewOverlay(){model.preview()}
    @objc func chooseFile(){showSettings();model.chooseFile()}
    @objc func chooseRoots(){showSettings();model.chooseRoots()}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationWillTerminate(_ notification:Notification){model.stop();overlay?.stop();menuTimer?.invalidate()}
}
@main enum ShoreLyricsMain {
    static func migratePreferencesIfNeeded(){
        guard Bundle.main.bundleIdentifier == "dongx.shorelyrics" else{return}
        let defaults=UserDefaults.standard
        let marker="dongxIdentityMigrationV1"
        guard !defaults.bool(forKey:marker) else{return}
        let existing=defaults.persistentDomain(forName:"dongx.shorelyrics") ?? [:]
        let legacy=(defaults.persistentDomain(forName:"local.shorelyrics.app") ?? [:]).merging(defaults.persistentDomain(forName:"local.dongx.shorelyrics") ?? [:]){_,new in new}
        for (key,value) in legacy where existing[key] == nil{defaults.set(value,forKey:key)}
        defaults.set(true,forKey:marker)
    }
    static func main(){migratePreferencesIfNeeded();let app=NSApplication.shared;app.setActivationPolicy(CommandLine.arguments.contains("--diagnose") ? .accessory : .regular);let delegate=AppDelegate();app.delegate=delegate;app.run();withExtendedLifetime(delegate){}}
}
