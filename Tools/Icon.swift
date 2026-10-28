// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import Foundation
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let tile=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:206,yRadius:206)
NSGradient(starting:NSColor(srgbRed:0.12,green:0.18,blue:0.20,alpha:1),ending:NSColor(srgbRed:0.035,green:0.075,blue:0.09,alpha:1))!.draw(in:tile,angle:130)
let mint=NSColor(srgbRed:0.56,green:0.89,blue:0.76,alpha:1)
mint.setFill()
let heights:[CGFloat]=[95,172,300,414,292,196,330,210,105]
for (i,height) in heights.enumerated(){
    NSBezierPath(roundedRect:NSRect(x:230+CGFloat(i)*64,y:560-height/2,width:36,height:height),xRadius:18,yRadius:18).fill()
}
NSColor(white:0.97,alpha:0.92).setFill()
NSBezierPath(roundedRect:NSRect(x:294,y:271,width:436,height:18),xRadius:9,yRadius:9).fill()
NSColor(white:0.97,alpha:0.34).setFill()
NSBezierPath(roundedRect:NSRect(x:367,y:223,width:290,height:14),xRadius:7,yRadius:7).fill()
image.unlockFocus()
let fm=FileManager.default
try fm.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,128,256,512]{
    for scale in [1,2]{
        let pixels=size*scale
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix=scale==2 ? "@2x" : ""
        try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
