// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import ApplicationServices

struct DockLayout {
    var frame:NSRect
    var screen:NSScreen
    var orientation:String
    var exact:Bool
    var trusted:Bool
    var visible:Bool
    var autoHide:Bool
    var cornerRadius:CGFloat=18
    var interactionFrame:NSRect?=nil
}
enum DockGeometry {
    static func cocoaRect(topLeft:CGPoint,size:CGSize,primaryTop:CGFloat)->NSRect {
        NSRect(x:topLeft.x,y:primaryTop-topLeft.y-size.height,width:size.width,height:size.height)
    }
    static func nativeFrame(interaction:NSRect,scale:CGFloat,modernDock:Bool)->NSRect {
        let scale=max(1,scale)
        // Recent Dock AX bounds describe its interaction area, five points above
        // the rendered surface. Translate the whole contour; do not resize it.
        let delta:CGFloat=modernDock ? -5 : 0
        func align(_ value:CGFloat)->CGFloat{(value*scale).rounded()/scale}
        let left=align(interaction.minX),right=align(interaction.maxX)
        let bottom=align(interaction.minY+delta),top=align(interaction.maxY+delta)
        return NSRect(x:left,y:bottom,width:right-left,height:top-bottom)
    }
    static func actualTile(itemSizes:[CGSize],configured:CGFloat)->CGFloat {
        let candidates=itemSizes.compactMap{size->CGFloat? in
            guard size.width.isFinite,size.height.isFinite,size.width>=16 else{return nil}
            let extra=size.height-size.width
            guard extra>=12,extra<=24 else{return nil}
            // AX item widths include interaction padding around the visible tile.
            return size.width-(extra<14 ? 2 : 4)
        }.sorted()
        guard !candidates.isEmpty else{return max(12,configured)}
        return candidates[(candidates.count-1)/2]
    }
    static func nativeRadius(tile:CGFloat,frame:NSRect,modernDock:Bool)->CGFloat {
        guard tile.isFinite,tile>0,!frame.isEmpty else{return 0}
        let radius:CGFloat
        if modernDock {
            // Native Dock corner bands change with the actual rendered tile,
            // including Docks compressed below their configured preference.
            switch tile {case ...31:radius=12;case ...47:radius=15;case ...63:radius=22;case ...127:radius=28;default:radius=48}
        }else{radius=(tile*0.3125).rounded()}
        return min(radius,min(frame.width,frame.height)/2)
    }
    static func bottomStrip(screen:NSRect,twoLines:Bool)->NSRect {
        NSRect(x:screen.minX,y:screen.minY,width:screen.width,height:twoLines ? 62 : 42)
    }
    static func estimate(screen:NSRect,visible:NSRect,orientation:String,icon:CGFloat,count:Int)->NSRect {
        let tile=max(16,min(128,icon))
        let length=min((orientation=="bottom" ? screen.width : screen.height)-12,CGFloat(max(3,count))*(tile+9)+30)
        let thickness=max(38,tile+20)
        if orientation=="left" {
            return NSRect(x:screen.minX,y:screen.midY-length/2,width:max(thickness,visible.minX-screen.minX),height:length)
        }
        if orientation=="right" {
            let width=max(thickness,screen.maxX-visible.maxX)
            return NSRect(x:screen.maxX-width,y:screen.midY-length/2,width:width,height:length)
        }
        return NSRect(x:screen.midX-length/2,y:screen.minY,width:length,height:max(thickness,visible.minY-screen.minY))
    }
}
final class DockLayoutReader {
    private var cached:DockLayout?
    private var lastRead=Date.distantPast
    func read()->DockLayout? {
        if Date().timeIntervalSince(lastRead)<0.35{return cached}
        lastRead=Date()
        guard let primary=NSScreen.screens.first else{return nil}
        let defaults=UserDefaults(suiteName:"com.apple.dock")
        let orientation=defaults?.string(forKey:"orientation") ?? "bottom"
        let autohide=defaults?.bool(forKey:"autohide") ?? false
        let trusted=AXIsProcessTrusted()
        if trusted,let measurement=accessibilityFrame(primaryTop:primary.frame.maxY) {
            let interaction=measurement.frame
            let modern=ProcessInfo.processInfo.operatingSystemVersion.majorVersion>=26
            let target=NSScreen.screens.max{a,b in a.frame.intersection(interaction).area < b.frame.intersection(interaction).area} ?? primary
            let rect=orientation=="bottom" ? DockGeometry.nativeFrame(interaction:interaction,scale:target.backingScaleFactor,modernDock:modern) : interaction
            let tile=DockGeometry.actualTile(itemSizes:measurement.sizes,configured:CGFloat(defaults?.double(forKey:"tilesize") ?? 48))
            let radius=DockGeometry.nativeRadius(tile:tile,frame:rect,modernDock:modern)
            // An autohidden Dock can lie mostly outside its screen. Keep its
            // original geometry and never draw it as a permanently visible bar.
            let center=NSPoint(x:rect.midX,y:rect.midY)
            let screen=NSScreen.screens.first(where:{$0.frame.insetBy(dx:-150,dy:-150).contains(center)}) ?? primary
            let intersection=rect.intersection(screen.frame)
            let visible = !intersection.isNull && (orientation=="bottom" ? intersection.height>12 : intersection.width>12)
            cached=DockLayout(frame:rect,screen:screen,orientation:orientation,exact:true,trusted:true,visible:visible,autoHide:autohide,cornerRadius:radius,interactionFrame:interaction)
            return cached
        }
        // Permission-free fallback. The visible frame reliably gives thickness;
        // the Dock's own preferences give a best-effort icon count and width.
        let pinned=defaults?.array(forKey:"persistent-apps") as? [[String:Any]] ?? []
        let others=defaults?.array(forKey:"persistent-others")?.count ?? 0
        let recent=defaults?.array(forKey:"recent-apps")?.count ?? ((defaults?.object(forKey:"show-recents") as? Bool)==false ? 0 : 3)
        let pinnedIDs=Set(pinned.compactMap{($0["tile-data"] as? [String:Any])?["bundle-identifier"] as? String})
        let transient=NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && !pinnedIDs.contains($0.bundleIdentifier ?? "")}.count
        let count=pinned.count+others+recent+transient
        let icon=CGFloat(defaults?.double(forKey:"tilesize") ?? 48)
        let rect=DockGeometry.estimate(screen:primary.frame,visible:primary.visibleFrame,orientation:orientation,icon:icon>0 ? icon : 48,count:count)
        let reserved=orientation=="left" ? primary.visibleFrame.minX-primary.frame.minX : orientation=="right" ? primary.frame.maxX-primary.visibleFrame.maxX : primary.visibleFrame.minY-primary.frame.minY
        // Without AX we cannot determine the transient reveal animation. For an
        // autohidden Dock prefer staying out of the way over covering the edge.
        cached=DockLayout(frame:rect,screen:primary,orientation:orientation,exact:false,trusted:trusted,visible:!autohide || reserved>12,autoHide:autohide)
        return cached
    }
    private func accessibilityFrame(primaryTop:CGFloat)->(frame:NSRect,sizes:[CGSize])? {
        guard let dock=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock").first else{return nil}
        let root=AXUIElementCreateApplication(dock.processIdentifier)
        var visited=0
        func value(_ element:AXUIElement,_ key:CFString)->CFTypeRef?{var result:CFTypeRef?;guard AXUIElementCopyAttributeValue(element,key,&result) == .success else{return nil};return result}
        func frame(_ element:AXUIElement)->NSRect?{
            guard let p=value(element,kAXPositionAttribute as CFString),let s=value(element,kAXSizeAttribute as CFString),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
            var point=CGPoint.zero,size=CGSize.zero
            guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),size.width>0,size.height>0 else{return nil}
            return DockGeometry.cocoaRect(topLeft:point,size:size,primaryTop:primaryTop)
        }
        func visit(_ element:AXUIElement,_ depth:Int)->(frame:NSRect,sizes:[CGSize])? {
            visited+=1;guard visited<220,depth<5 else{return nil}
            let role=value(element,kAXRoleAttribute as CFString) as? String
            if role==kAXListRole as String,let rect=frame(element),max(rect.width,rect.height)>120,min(rect.width,rect.height)>15 {
                let children=value(element,kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
                let sizes=children.compactMap{frame($0)?.size}
                return (rect,sizes)
            }
            let children=value(element,kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
            for child in children {if let found=visit(child,depth+1){return found}}
            return nil
        }
        return visit(root,0)
    }
}

private extension NSRect {
    var area:CGFloat{isNull || isEmpty ? 0 : width*height}
}
