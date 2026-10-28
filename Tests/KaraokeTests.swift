// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit

@main enum KaraokeTests {
    static var checks=0
    static func check(_ condition:Bool,_ message:String) {
        guard condition else{fatalError(message)}
        checks+=1
    }
    static func main() throws {
        let font=NSFont.systemFont(ofSize:28,weight:.semibold)
        let mixed=KaraokeGlyphLayout(text:"Wi岸词",font:font)
        let widths=zip(mixed.boundaries.dropFirst(),mixed.boundaries).map(-)
        check(widths[0]>widths[1]*2,"wide and narrow Latin glyphs use actual widths")
        check(abs(mixed.frontier(progress:0.25).edge-mixed.boundaries[1])<0.001,"quarter progress ends at first actual glyph boundary")
        check(abs(mixed.frontier(progress:0.375).edge-(mixed.boundaries[1]+mixed.boundaries[2])/2)<0.001,"partial character follows glyph width")
        check(abs(mixed.frontier(progress:1).edge-mixed.width)<0.01,"completed mask reaches last glyph")
        let emoji=KaraokeGlyphLayout(text:"你👨‍👩‍👧‍👦好é",font:font)
        check(emoji.boundaries.count==5,"composed emoji use grapheme rather than UTF16 indexing")
        check(emoji.boundaries.allSatisfy{$0.isFinite},"composed text produces finite glyph positions")

        func render(_ progress:Double?, glow:Bool, previous:Double?=nil)->NSBitmapImageRep {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            let view=GlyphTextView(frame:NSRect(x:0,y:0,width:640,height:80))
            view.font=font;view.layout=KaraokeGlyphLayout(text:"岸词",font:font)
            view.color = .white;view.highlight = .systemTeal;view.glow=glow
            if let previous {view.progress=previous;view.draw(view.bounds)}
            view.progress=progress;view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        let plainFrame=render(nil,glow:false), litFrame=render(0.2,glow:true)
        let pair=KaraokeGlyphLayout(text:"岸词",font:font)
        let edge=(640-pair.width)/2+pair.frontier(progress:0.2).edge
        var unsungUnchanged=true
        for y in 0..<80 {
            for x in Int(ceil(edge))+1..<640 {
                if plainFrame.colorAt(x:x,y:y) != litFrame.colorAt(x:x,y:y) {unsungUnchanged=false}
            }
        }
        check(unsungUnchanged,"leading light never pre-colors the unsung part of the current glyph")
        let settled=render(0.7,glow:false), shining=render(0.7,glow:true)
        let stableEnd=Int(floor((640-pair.width)/2+pair.frontier(progress:0.7).edge-font.pointSize*0.55))-1
        var sungUnchanged=true
        for y in 0..<80 {
            for x in 0..<max(0,stableEnd) {
                if settled.colorAt(x:x,y:y) != shining.colorAt(x:x,y:y) {sungUnchanged=false}
            }
        }
        check(sungUnchanged,"completed glyphs retain selected color behind the leading light")
        let repeated=render(0.3,glow:true,previous:0.2), fresh=render(0.3,glow:true)
        let bytes=repeated.bytesPerRow*repeated.pixelsHigh
        check(Data(bytes:repeated.bitmapData!,count:bytes)==Data(bytes:fresh.bitmapData!,count:bytes),"new frame replaces previous glow without accumulation")

        let changing=GlyphTextView(frame:NSRect(x:0,y:0,width:640,height:80))
        changing.text="旧歌词";changing.font=font
        changing.layout=KaraokeGlyphLayout(text:changing.text,font:font)
        changing.progress=0.9;changing.highlight = .systemPink
        changing.prepareForLineChange(animated:true)
        let oldWidth=changing.layout!.width
        changing.text="下一句更长的歌词";changing.layout=KaraokeGlyphLayout(text:changing.text,font:font)
        changing.progress=0;changing.highlight = .systemOrange
        check(changing.outgoingFrame?.layout.width==oldWidth && changing.outgoingFrame?.progress==0.9,"outgoing lyric freezes layout and playback position")
        check(changing.outgoingFrame?.highlight == NSColor.systemPink,"outgoing lyric freezes its color independently of new line")
        var allFramesVisible=true
        for _ in 0..<8 {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:640,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            changing.draw(changing.bounds)
            NSGraphicsContext.restoreGraphicsState()
            var visible=0
            for y in stride(from:0,to:80,by:2) {
                for x in stride(from:0,to:640,by:2) {
                    if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.1{visible+=1}
                }
            }
            if visible<20{allFramesVisible=false}
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.04))
        }
        check(allFramesVisible,"every sampled frame remains visible throughout line transition")
        changing.prepareForLineChange(animated:true)
        check(changing.outgoingFrame?.layout.width==changing.layout?.width,"rapid line changes replace rather than stack outgoing frames")
        changing.prepareForLineChange(animated:false)
        check(changing.outgoingFrame==nil,"seek and reduced motion cancel transition immediately")

        let image=NSImage(size:NSSize(width:640,height:240))
        image.lockFocus()
        let rows:[(String,Double?,NSColor,Bool)]=[
            ("Wi 岸词 · 歌声流动",0.32,.systemTeal,false),
            ("Wi 岸词 · 歌声流动",0.63,.systemPink,true),
            ("第一行随音乐染色",0.52,.systemOrange,true),
            ("第二行保持原色",nil,.systemTeal,false)
        ]
        for (index,row) in rows.enumerated() {
            let y=CGFloat(3-index)*60
            let dark=index==0 || index==2
            (dark ? NSColor(calibratedWhite:0.08,alpha:1) : NSColor(calibratedWhite:0.96,alpha:1)).setFill()
            NSRect(x:0,y:y,width:640,height:60).fill()
            let view=GlyphTextView(frame:NSRect(x:0,y:0,width:600,height:48))
            view.font=font;view.text=row.0;view.layout=KaraokeGlyphLayout(text:row.0,font:font)
            view.progress=row.1;view.highlight=row.2;view.color=dark ? .white : .black;view.glow=row.3
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.translateBy(x:20,y:y+6)
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo:nil)
            view.draw(view.bounds)
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            NSGraphicsContext.restoreGraphicsState()
        }
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        var coloredPixels=0, neutralPixels=0
        for y in stride(from:0,to:bitmap.pixelsHigh,by:4) {
            for x in stride(from:0,to:bitmap.pixelsWide,by:4) {
                guard let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{continue}
                let maximum=max(color.redComponent,max(color.greenComponent,color.blueComponent))
                let minimum=min(color.redComponent,min(color.greenComponent,color.blueComponent))
                if maximum-minimum>0.25{coloredPixels+=1}
                if maximum<0.1{neutralPixels+=1}
            }
        }
        check(coloredPixels>100,"native draw produces colored lyric glyphs")
        check(neutralPixels>100,"native draw retains neutral text and dark background")
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        try bitmap.representation(using:.png,properties:[:])!.write(to:output)
        check(bitmap.pixelsWide>=640 && bitmap.pixelsHigh>=240,"native renderer creates visual verification image")
        print("PASS: \(checks) glyph layout and rendering checks")
    }
}
