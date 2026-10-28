// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let mint=NSColor(srgbRed:0.49,green:0.84,blue:0.72,alpha:1)
let ink=NSColor(srgbRed:0.045,green:0.075,blue:0.085,alpha:1)
let paper=NSColor(srgbRed:0.92,green:0.95,blue:0.91,alpha:1)
func font(_ size:CGFloat,_ weight:NSFont.Weight = .regular)->NSFont {NSFont(name:weight == .bold ? "PingFangSC-Semibold" : "PingFangSC-Regular",size:size) ?? .systemFont(ofSize:size,weight:weight)}
func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ size:CGFloat,_ color:NSColor=paper,_ weight:NSFont.Weight = .regular){
 let para=NSMutableParagraphStyle();para.lineSpacing=size*0.15
 (s as NSString).draw(in:NSRect(x:x,y:y,width:w,height:size*5),withAttributes:[.font:font(size,weight),.foregroundColor:color,.paragraphStyle:para])
}
func box(_ rect:NSRect,_ color:NSColor,_ radius:CGFloat=0){color.setFill();NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill()}
func canvas(_ width:Int,_ height:Int,_ url:URL,_ draw:()->Void){
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState();let bitmapContext=NSGraphicsContext(bitmapImageRep:rep)!;NSGraphicsContext.current=NSGraphicsContext(cgContext:bitmapContext.cgContext,flipped:true);let tr=NSAffineTransform();tr.translateX(by:0,yBy:CGFloat(height));tr.scaleX(by:1,yBy:-1);tr.concat();draw();NSGraphicsContext.restoreGraphicsState()
 try! rep.representation(using:.png,properties:[:])!.write(to:url)
}
func picture(_ url:URL,_ rect:NSRect){
 let image=NSImage(contentsOf:url)!;image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
}
let screenshots=root.appendingPathComponent("docs/screenshots")
// Read raw captures once, remove recording chrome and mask local paths.
for name in ["01-playing","02-sources","03-appearance","03b-appearance-controls","04-privacy"] {
 let url=screenshots.appendingPathComponent(name+".png")
 let raw=root.appendingPathComponent("build/captures/"+name+"-native.png")
 try! FileManager.default.createDirectory(at:raw.deletingLastPathComponent(),withIntermediateDirectories:true)
 if !FileManager.default.fileExists(atPath:raw.path){try! FileManager.default.copyItem(at:url,to:raw)}
 let image=NSImage(contentsOf:raw)!;let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
 let topInset=cg.height==1544 ? 64 : 0
 let cut=cg.cropping(to:CGRect(x:0,y:topInset,width:cg.width,height:cg.height-topInset))!
 let cropped=NSImage(cgImage:cut,size:NSSize(width:cut.width,height:cut.height))
 canvas(cut.width,cut.height,url){
  cropped.draw(in:NSRect(x:0,y:0,width:cut.width,height:cut.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
  if name=="02-sources" {box(NSRect(x:488,y:695,width:1150,height:42),.white);text("[本地音乐目录 · 路径已隐藏]",495,699,1100,20,.gray)}
  if name=="04-privacy" {box(NSRect(x:590,y:848,width:1200,height:48),.white);text("[本地音频文件 · 路径已隐藏]",598,855,1100,22,.gray)}
 }
}
let out=root.appendingPathComponent("docs/promo")
func wave(_ x:CGFloat,_ y:CGFloat,_ scale:CGFloat){
 for (i,h) in [14,30,52,84,42,68,28,12].enumerated(){box(NSRect(x:x+CGFloat(i)*scale*9,y:y-CGFloat(h)*scale/2,width:3*scale,height:CGFloat(h)*scale),mint,1.5*scale)}
}
// Tight crops retain the real Dock and remove neighboring application content.
for name in ["dock-fusion","dock-original"] {
 let raw=root.appendingPathComponent("build/captures/"+name+"-native.png")
 let target=screenshots.appendingPathComponent(name+".png")
 if FileManager.default.fileExists(atPath:raw.path) {
  let source=NSImage(contentsOf:raw)!;let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil)!
  let crop=cg.cropping(to:CGRect(x:0,y:10,width:cg.width,height:cg.height-10))!
  let bitmap=NSBitmapImageRep(cgImage:crop)
  try! bitmap.representation(using:.png,properties:[:])!.write(to:target)
 }
}
func dockImage(_ name:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat){
 let url=screenshots.appendingPathComponent(name+".png")
 let source=NSImage(contentsOf:url)!;let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil)!
 picture(url,NSRect(x:x,y:y,width:width,height:width*CGFloat(cg.height)/CGFloat(cg.width)))
}
canvas(2400,1600,out.appendingPathComponent("shore-lyrics-hero.png")){
 box(NSRect(x:0,y:0,width:2400,height:1600),ink)
 text("SHORE LYRICS  /  macOS",96,65,1200,25,mint)
 text("岸词",90,170,1100,128,paper,.bold)
 text("让歌词，停靠在 Dock。",96,365,1180,62,paper,.bold)
 text("系统媒体信息 · 音频内嵌歌词 · 本地优先",100,495,1180,29,mint)
 text("跟随正在播放的音乐，逐行同步。\n鼠标靠近时自动让位，随时访问 Dock。",100,600,1150,31,paper.withAlphaComponent(0.7))
 wave(115,780,1.0)
 text("融入桌面，专注音乐。",250,755,900,32,mint)
 picture(screenshots.appendingPathComponent("01-playing.png"),NSRect(x:1320,y:100,width:980,height:772))
 box(NSRect(x:96,y:915,width:2208,height:1),paper.withAlphaComponent(0.15))
 text("01  歌词融合",100,955,1800,29,mint,.bold)
 text("应用内置预览 · 实机截图",1780,960,550,23,paper.withAlphaComponent(0.5))
 dockImage("dock-fusion",96,1020,2208)
 text("02  原始 Dock",100,1190,1800,29,mint,.bold)
 dockImage("dock-original",96,1255,2208)
 box(NSRect(x:96,y:1475,width:2208,height:1),paper.withAlphaComponent(0.15))
 text("Apple Silicon  /  macOS 13+",100,1510,1200,24,paper.withAlphaComponent(0.6))
 text("OPEN SOURCE  ·  AGPL v3.0",1700,1510,650,24,mint)
}
canvas(1600,1600,out.appendingPathComponent("shore-lyrics-square.png")){
 box(NSRect(x:0,y:0,width:1600,height:1600),ink)
 text("SHORE LYRICS",90,75,1300,27,mint)
 text("岸词",84,185,1200,140,paper,.bold)
 text("让歌词，停靠在 Dock。",90,410,1450,65,paper,.bold)
 text("系统媒体信息  /  内嵌歌词  /  本地优先",95,535,1400,29,mint)
 text("播放音乐时",95,720,1400,32,paper,.bold)
 dockImage("dock-fusion",80,805,1440)
 text("访问 Dock 时，歌词自动让位",95,1015,1400,32,paper,.bold)
 dockImage("dock-original",80,1100,1440)
 text("Dock 实机截图 · 歌词为应用内置预览",95,1270,1400,23,paper.withAlphaComponent(0.5))
 box(NSRect(x:90,y:1400,width:1420,height:1),paper.withAlphaComponent(0.18))
 text("原生 macOS  ·  AGPL v3.0",95,1455,1400,31,mint)
 text("兼容发布 macOS 系统媒体信息的播放器与浏览器",95,1525,1400,23,paper.withAlphaComponent(0.6))
}
canvas(2400,2400,out.appendingPathComponent("shore-lyrics-features.png")){
 box(NSRect(x:0,y:0,width:2400,height:2400),ink)
 text("岸词  /  功能一览",90,65,1800,68,paper,.bold)
 text("播放、来源、外观、隐私，每一处都清楚。",95,175,2200,29,mint)
 let items=[("01-playing","01  正在播放","当前歌词与完整歌词，一眼看清。"),("02-sources","02  歌词来源","内嵌、旁挂、手动关联与可选在线补词。"),("03-appearance","03  显示与外观","Dock 融合与配色，按你的习惯调整。"),("04-privacy","04  隐私与诊断","权限用途、匹配状态与开源协议。")]
 for (i,item) in items.enumerated(){
  let x:CGFloat=i%2==0 ? 90 : 1250;let y:CGFloat=i<2 ? 290 : 1290
  text(item.1,x,y,1050,31,mint,.bold)
  text(item.2,x,y+57,1050,24,paper.withAlphaComponent(0.65))
  picture(screenshots.appendingPathComponent(item.0+".png"),NSRect(x:x,y:y+110,width:1060,height:834))
 }
 text("真实应用截图 · 本地路径已隐藏",95,2320,1500,23,paper.withAlphaComponent(0.45))
 text("SHORE LYRICS  /  v0.2.5",1790,2320,550,23,mint)
}
print("Rendered screenshots and three promotional PNGs")
