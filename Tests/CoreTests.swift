// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

@main enum CoreTests {
    static var count=0
    static func check(_ condition:@autoclosure()->Bool,_ message:String){guard condition() else{fputs("FAIL: \(message)\n",stderr);exit(1)};count+=1}
    static func sync(_ n:Int)->[UInt8]{[UInt8((n>>21)&127),UInt8((n>>14)&127),UInt8((n>>7)&127),UInt8(n&127)]}
    static func big(_ n:Int)->[UInt8]{[UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]}
    static func frame(_ id:String,_ content:[UInt8],version:Int=3)->[UInt8]{Array(id.utf8)+(version==4 ? sync(content.count) : big(content.count))+[0,0]+content}
    static func main()throws{
        let doc=LyricsParser.parse("[offset:+100]\n[00:01.50][00:03.250]你好\n[00:01.50]Hello\n[00:07.000]",source:"test")
        check(doc.lines.count==3,"multiple timestamps and translations merge")
        check(abs(doc.lines[0].time-1.4)<0.001,"offset and hundredths")
        check(doc.lines[0].text=="你好\nHello","translations retained")
        check(doc.index(at:1.3)==nil,"intro is not first lyric")
        check(doc.index(at:1.4)==0,"exact timestamp boundary")
        check(doc.index(at:6.9)==2,"blank interlude marker")
        check(doc.index(at:.nan)==nil,"non-finite playback rejected")
        let plain=LyricsParser.parse("第一行\n第二行",source:"test")
        check(!plain.timed && plain.plain=="第一行\n第二行","plain text never invents timings")
        let srt=LyricsParser.parse("1\n00:00:01,250 --> 00:00:02,500\n<b>第一句</b>\n\n2\n00:00:04,000 --> 00:00:05,000\n第二句",source:"test")
        check(srt.lines.count==2 && srt.lines[0].text=="第一句","SRT parses times and markup")
        check(srt.index(at:2.7)==nil,"SRT gaps remain gaps")
        let enhanced=LyricsParser.parse("[00:01.00]<00:01.00>你<00:01.50>好",source:"test")
        check(enhanced.lines.first?.text=="你好","enhanced LRC words remain readable")
        let singing=enhanced.lines[0]
        check(singing.words.count==2 && singing.words[1].offset==1,"enhanced LRC retains word timing")
        check(abs(singing.progress(at:1.25,until:2)-0.25)<0.001,"word highlight interpolates within syllable")
        check(singing.progress(at:0,until:2)==0 && singing.progress(at:3,until:2)==1,"highlight clamps at boundaries")
        check(abs(singing.progress(at:1.75,until:2)-0.75)<0.001,"last syllable ends at next line")
        let shifted=LyricsParser.parse("[offset:100]\n[00:01.00]<00:01.00>你<00:01.50>好",source:"test")
        check(abs(shifted.lines[0].words[1].time-1.4)<0.001,"word timestamps respect LRC offset")
        check(abs(doc.lines[1].progress(at:5.025,until:6.9)-0.5)<0.001,"plain LRC estimates line sweep")
        let estimated=LyricLine(time:1,text:"普通歌词")
        check(abs(estimated.progress(at:3,until:5,estimatedSpeed:1.38)-0.69)<0.001,"plain LRC honors custom sweep speed")
        check(estimated.progress(at:4.6,until:5,estimatedSpeed:1.38)==1,"estimated sweep completes early without overshooting")
        check(estimated.progress(at:0,until:5)==0,"faster estimate still waits for line start")
        check(abs(srt.lines[0].progress(at:1.875,until:2.5,estimatedSpeed:2)-0.5)<0.001,"SRT explicit interval keeps original speed")
        check(abs(singing.progress(at:1.25,until:2,estimatedSpeed:2)-0.25)<0.001,"word timestamps ignore estimation speed setting")
        check(abs(estimated.progress(at:3,until:5,estimatedSpeed:0.5)-0.25)<0.001,"ordinary lyrics support slower sweep speeds")
        let uslt=[UInt8(3)]+Array("eng".utf8)+[0]+Array("[00:01.25]内嵌歌词".utf8)
        let tags=NativeTags.id3(version:3,flags:0,bytes:frame("TIT2",[3]+Array("测试歌曲".utf8))+frame("USLT",uslt))
        check(tags.title=="测试歌曲" && tags.lyrics.count==1,"ID3 title and USLT")
        check(LyricsParser.parse(tags.lyrics[0].1,source:"test").timed,"USLT can hold synced LRC")
        let utf16=Array("描述".data(using:.utf16)!)+[0,0]+Array("[00:02.00]双字节歌词".data(using:.utf16)!)
        let wide=NativeTags.id3(version:4,flags:0,bytes:frame("USLT",[1]+Array("zho".utf8)+utf16,version:4))
        check(wide.lyrics.first?.1.contains("双字节歌词")==true,"UTF16 aligned description terminator")
        let sylt:[UInt8]=[3]+Array("eng".utf8)+[2,1,0]+Array("Hello".utf8)+[0]+big(1250)+Array("World".utf8)+[0]+big(2500)
        let synced=NativeTags.id3(version:3,flags:0,bytes:frame("SYLT",sylt))
        let syltDoc=LyricsParser.parse(synced.lyrics.first?.1 ?? "",source:"test")
        check(syltDoc.lines.count==2 && syltDoc.lines[0].time==1.25,"SYLT millisecond timestamps")
        let malformed=NativeTags.id3(version:3,flags:0,bytes:Array("USLT".utf8)+[255,255,255,255,0,0,3])
        check(malformed.lyrics.isEmpty,"oversized malformed ID3 frame rejected")
        check(normalized("G.E.M. 邓紫棋")==normalized("gem邓紫棋"),"metadata matching normalization")
        let tmp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:tmp)}
        let mp3=tmp.appendingPathComponent("Singer - Test.mp3")
        let body=frame("TIT2",[3]+Array("Test".utf8))+frame("TPE1",[3]+Array("Singer".utf8))+frame("USLT",uslt)
        try Data(Array("ID3".utf8)+[3,0,0]+sync(body.count)+body).write(to:mp3)
        let library=MusicLibrary();check(library.scan(paths:[tmp.path])==1,"selected directory indexes media only")
        let found=library.match(title:"Test",artist:"Singer",album:"",duration:0,fileURL:nil)
        check(found.document?.timed==true,"local matching reaches embedded timed lyrics")
        check(library.match(title:"Test",artist:"Other singer",album:"",duration:0,fileURL:nil).document==nil,"different artist cannot match same title")
        let direct=MusicLibrary()
        check(direct.match(title:"Test",artist:"Singer",album:"",duration:0,fileURL:mp3.absoluteString).document?.timed==true,"published file URL works with zero folder restrictions")
        let sidecar=mp3.deletingPathExtension().appendingPathExtension("lrc")
        try "[00:00.50]旁挂歌词".write(to:sidecar,atomically:true,encoding:.utf8)
        check(direct.match(title:"Test",artist:"Singer",album:"",duration:0,fileURL:mp3.absoluteString).document?.source.contains("LRC")==true,"published file's sidecar works outside roots")
        // Build a small FLAC metadata block with a Vorbis lyrics comment.
        func little(_ n:Int)->[UInt8]{[UInt8(n&255),UInt8((n>>8)&255),UInt8((n>>16)&255),UInt8((n>>24)&255)]}
        let comment=Array("LYRICS=[00:01.00]FLAC test".utf8)
        let block=little(0)+little(1)+little(comment.count)+comment
        let flac=tmp.appendingPathComponent("sample.flac")
        try Data(Array("fLaC".utf8)+[0x84,UInt8((block.count>>16)&255),UInt8((block.count>>8)&255),UInt8(block.count&255)]+block).write(to:flac)
        check(NativeTags.read(flac).lyrics.first?.1.contains("FLAC test")==true,"FLAC native lyrics")
        // Nested MP4 ©lyr/data atoms, including the meta full-box header.
        func atom(_ code:[UInt8],_ bytes:[UInt8])->[UInt8]{big(bytes.count+8)+code+bytes}
        let dataAtom=atom(Array("data".utf8),[0,0,0,1,0,0,0,0]+Array("[00:02.00]MP4 test".utf8))
        let lyricAtom=atom([0xa9,0x6c,0x79,0x72],dataAtom)
        let meta=atom(Array("meta".utf8),[0,0,0,0]+atom(Array("ilst".utf8),lyricAtom))
        let m4a=tmp.appendingPathComponent("sample.m4a")
        try Data(atom(Array("ftyp".utf8),Array("M4A ".utf8)+[0,0,0,0])+atom(Array("moov".utf8),atom(Array("udta".utf8),meta))).write(to:m4a)
        check(NativeTags.read(m4a).lyrics.first?.1.contains("MP4 test")==true,"M4A native lyrics without external libraries")
        // Timing interpolation: pause, stale anchors, duration clamping.
        var clock=PlaybackClock()
        var sample=PlaybackSnapshot(capturedAt:100,playing:true,rate:1,title:"Clock",duration:300,position:10)
        clock.update(sample,now:100)
        var previousPosition=clock.elapsed(now:100)
        for index in 1...30 {
            let now=100+Double(index)*0.35
            sample.capturedAt=now
            sample.position=10+now-100-(index.isMultiple(of:2) ? 0.55 : 0)
            let before=clock.elapsed(now:now)
            check(!clock.update(sample,now:now),"subsecond media correction is not a seek")
            let after=clock.elapsed(now:now)
            check(after>=before && after>=previousPosition,"jittering media snapshots cannot rewind lyric progress")
            previousPosition=after
        }
        check(abs(clock.elapsed(now:110.5)-20.5)<0.75,"smoothed lyric clock remains close to media time")
        sample.capturedAt=111;sample.position=5
        check(clock.update(sample,now:111) && clock.elapsed(now:111)==5,"real backward seek aligns immediately")
        sample.capturedAt=112;sample.position=50
        check(clock.update(sample,now:112) && clock.elapsed(now:112)==50,"real forward seek aligns immediately")
        sample.capturedAt=113;sample.playing=false;sample.position=51
        clock.update(sample,now:113)
        check(clock.elapsed(now:115)==51,"smoothed clock freezes immediately on pause")
        sample.capturedAt=115;sample.playing=true;sample.rate=2
        clock.update(sample,now:115)
        check(clock.elapsed(now:116)==53,"resuming honors changed playback speed")
        var snap=PlaybackSnapshot(capturedAt:100,playing:true,rate:1,position:10)
        check(snap.elapsed(now:101)==11,"playing clock interpolates")
        check(snap.elapsed(now:200)==13,"stale samples cannot extrapolate forever")
        snap.playing=false;check(snap.elapsed(now:101)==10,"pause freezes position")
        snap.playing=true;snap.duration=10.5;check(snap.elapsed(now:101)==10.5,"clock clamps to duration")
        let bottom=DockGeometry.cocoaRect(topLeft:CGPoint(x:200,y:1102),size:CGSize(width:1200,height:67),primaryTop:1169)
        check(bottom==NSRect(x:200,y:0,width:1200,height:67),"Dock coordinates convert from top-left into AppKit")
        let external=DockGeometry.cocoaRect(topLeft:CGPoint(x:-1600,y:-800),size:CGSize(width:800,height:70),primaryTop:1169)
        check(external.minX == -1600 && external.minY == 1899,"external displays preserve negative/global coordinates")
        let screen=NSRect(x:0,y:0,width:1800,height:1169),visible=NSRect(x:0,y:67,width:1800,height:1062)
        let estimate=DockGeometry.estimate(screen:screen,visible:visible,orientation:"bottom",icon:47,count:20)
        check(estimate.height==67 && estimate.midX==900 && estimate.minY==0,"permission-free fallback matches Dock thickness and center")
        let crowded=DockGeometry.estimate(screen:screen,visible:visible,orientation:"bottom",icon:120,count:100)
        check(crowded.width<=screen.width-12,"large Docks stay within the screen")
        let left=DockGeometry.estimate(screen:screen,visible:NSRect(x:70,y:0,width:1730,height:1130),orientation:"left",icon:50,count:12)
        check(left.minX==0 && left.width==70,"left Dock estimation follows reserved region")
        let right=DockGeometry.estimate(screen:screen,visible:NSRect(x:0,y:0,width:1730,height:1130),orientation:"right",icon:50,count:12)
        check(right.maxX==1800 && right.width==70,"right Dock estimation follows reserved region")
        let liveInteraction=NSRect(x:238,y:10,width:1324,height:61)
        let native=DockGeometry.nativeFrame(interaction:liveInteraction,scale:2,modernDock:true)
        check(native==NSRect(x:238,y:5,width:1324,height:61),"measured Dock retains its width and height at the real bottom gap")
        let actualTile=DockGeometry.actualTile(itemSizes:Array(repeating:CGSize(width:49,height:61),count:5),configured:47)
        check(actualTile==47,"AX padding is removed from the live tile measurements")
        check(DockGeometry.nativeRadius(tile:actualTile,frame:native,modernDock:true)==15,"live Dock corner band is 15pt instead of a fixed 22pt")
        let crowdedTile=DockGeometry.actualTile(itemSizes:[CGSize(width:35,height:51),CGSize(width:35,height:51),CGSize(width:88,height:104)],configured:64)
        check(crowdedTile==31,"crowded Dock measures actual small icons rather than the magnified item or preference")
        check(DockGeometry.nativeRadius(tile:31,frame:native,modernDock:true)==12,"small Dock uses its native corner band")
        check(DockGeometry.nativeRadius(tile:51,frame:native,modernDock:true)==22,"medium Dock uses its native corner band")
        let externalNative=DockGeometry.nativeFrame(interaction:NSRect(x:-1600,y:1200,width:800,height:71),scale:2,modernDock:true)
        check(externalNative.origin==NSPoint(x:-1600,y:1195),"Dock floor translation preserves external-display global coordinates")
        check(DockGeometry.nativeFrame(interaction:liveInteraction,scale:2,modernDock:false)==liveInteraction,"legacy Dock layout does not receive the modern translation")
        let strip=DockGeometry.bottomStrip(screen:screen,twoLines:true)
        check(strip.minY==screen.minY && strip.width==screen.width && strip.height==62,"bottom mode is an edge-to-edge strip on the physical screen edge")
        check(strip.maxY<visible.minY+12,"bottom strip is distinct from the above-Dock floating panel")
        if let rootIndex=CommandLine.arguments.firstIndex(of:"--music-root"),rootIndex+1<CommandLine.arguments.count {
            let root=URL(fileURLWithPath:CommandLine.arguments[rootIndex+1])
            let files=(FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)?.allObjects as? [URL]) ?? []
            for ext in ["mp3","m4a"] {
                let sample=Array(files.filter{$0.pathExtension==ext}.prefix(12))
                var withLyrics=0
                for file in sample {if NativeTags.read(file).lyrics.contains(where:{!$0.1.isEmpty}){withLyrics+=1}}
                check(!sample.isEmpty && withLyrics>0,"real \(ext) files contain readable native lyrics")
                print("Real \(ext) sample: \(withLyrics)/\(sample.count) with native embedded lyrics")
            }
        }
        print("PASS: \(count) checks")
    }
}
