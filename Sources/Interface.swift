// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AppKit

private let mint=Color(red:0.49,green:0.84,blue:0.72)
private let ink=Color(red:0.07,green:0.10,blue:0.13)

struct OverlayView:View {
    @ObservedObject var model:AppModel
    var paper:Bool{model.theme=="paper"}
    var fused:Bool{model.placement=="dock"}
    var compact:Bool{fused || model.placement=="bottom"}
    var glass:Bool{model.theme=="glass"}
    var body:some View {
        VStack(spacing:compact ? 3 : 7){
            KaraokeText(model:model,color:model.theme=="custom" ? model.customLyricColor : glass ? .primary : paper ? Color(red:0.12,green:0.15,blue:0.15) : .white,fontSize:compact ? min(24,model.fontSize) : model.fontSize,rounded:true)
            if model.twoLines && !model.secondaryText.isEmpty {
                Text(model.secondaryText.replacingOccurrences(of:"\n",with:" · "))
                    .font(.system(size:compact ? 12 : max(13,model.fontSize*0.66))).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundColor(model.theme=="custom" ? model.customSecondaryColor : glass ? .secondary : paper ? .black.opacity(0.65) : .white.opacity(0.7))
            }
        }
            .padding(.horizontal,26).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background((model.theme=="custom" ? model.customBackgroundColor : glass ? Color.clear : paper ? Color(red:0.98,green:0.97,blue:0.93) : model.theme=="pine" ? Color(red:0.05,green:0.15,blue:0.12) : ink).opacity(model.opacity))
            .clipShape(RoundedRectangle(cornerRadius:model.placement=="bottom" ? 0 : fused ? model.dockCornerRadius : 18,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:model.placement=="bottom" ? 0 : fused ? model.dockCornerRadius : 18).stroke(glass ? .clear : paper ? .black.opacity(0.09) : .white.opacity(0.12),lineWidth:1))
            .padding(compact ? 0 : 3)
    }
}

private struct SidebarFocusAppearance:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 14.0,*) {content.focusEffectDisabled()}
        else {content}
    }
}

enum Page:String,CaseIterable {
    case playing="正在播放",sources="歌词来源",appearance="显示与外观",privacy="隐私与诊断"
    var icon:String{switch self{case .playing:return "waveform";case .sources:return "folder";case .appearance:return "rectangle.bottomthird.inset.filled";case .privacy:return "checkmark.shield"}}
}
struct SettingsView:View {
    @ObservedObject var model:AppModel
    @State private var page:Page
    init(model:AppModel,page:Page = .playing){self.model=model;self._page=State(initialValue:page)}
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:28){
                HStack(spacing:10){
                    Image(systemName:"waveform.path").font(.system(size:26,weight:.medium)).foregroundColor(.teal)
                    VStack(alignment:.leading,spacing:2){Text("岸词").font(.system(size:22,weight:.semibold));Text("SHORE LYRICS").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.5).foregroundColor(.secondary)}
                }.padding(.top,20).padding(.horizontal,18)
                VStack(spacing:5){ForEach(Page.allCases,id:\.self){item in
                    Button{page=item} label: {HStack(spacing:11){Image(systemName:item.icon).frame(width:18);Text(item.rawValue);Spacer()}.font(.system(size:13,weight:page==item ? .semibold : .regular)).padding(.horizontal,13).frame(height:40).background(page==item ? Color.teal.opacity(0.13) : .clear).cornerRadius(9)}
                        .buttonStyle(.plain).modifier(SidebarFocusAppearance()).padding(.horizontal,10).accessibilityAddTraits(page==item ? .isSelected : [])
                }}
                Spacer()
                VStack(alignment:.leading,spacing:7){
                    Label(model.online ? "在线匹配已开启" : "本地优先 · 在线关闭",systemImage:model.online ? "network" : "lock.shield").font(.system(size:11,weight:.medium))
                    Label(model.document?.source ?? "暂无歌词来源",systemImage:"text.alignleft")
                        .font(.system(size:11,weight:.medium))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .help("当前歌词来源："+(model.document?.source ?? "暂无歌词"))
                        .accessibilityLabel("当前歌词来源："+(model.document?.source ?? "暂无歌词"))
                    Text("\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版") · © 2026 dongx").font(.system(size:10)).foregroundColor(.secondary)
                }.padding(18)
            }.frame(width:178).background(Color(nsColor:.windowBackgroundColor))
            Divider()
            GeometryReader{geometry in
                ScrollView{
                    VStack(alignment:.leading,spacing:22){
                        switch page{
                        case .playing:playingPage
                        case .sources:sourcesPage
                        case .appearance:appearancePage
                        case .privacy:privacyPage
                        }
                    }.frame(width:max(0,geometry.size.width-56),alignment:.leading).padding(28)
                }.background(Color(nsColor:.controlBackgroundColor))
            }
        }.frame(minWidth:820,minHeight:640).tint(.teal)
    }
    private func heading(_ title:String,_ subtitle:String)->some View {
        VStack(alignment:.leading,spacing:7){Text(title).font(.system(size:24,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)}
    }
    private func pill(_ text:String,icon:String)->some View {
        Label(text,systemImage:icon).font(.system(size:10,weight:.medium)).lineLimit(1).truncationMode(.middle).padding(.horizontal,9).padding(.vertical,5).background(Color.teal.opacity(0.09)).cornerRadius(6)
    }
    private var playingPage:some View {
        VStack(alignment:.leading,spacing:12){
            HStack(alignment:.top){heading("随系统，随音乐。","跟随 macOS 正在播放的应用，不限定播放器或音乐目录。");Spacer();Button("预览歌词条"){model.preview()}}
            VStack(alignment:.leading,spacing:16){
                HStack{
                    Circle().fill(model.snapshot?.playing==true ? mint : Color.white.opacity(0.35)).frame(width:7,height:7)
                    Text(model.playerName).font(.system(size:12,weight:.medium)).foregroundColor(.white)
                    Spacer();Text(model.snapshot == nil ? "等待播放" : model.snapshot?.playing==true ? "正在播放" : "已暂停").font(.system(size:11)).foregroundColor(.white.opacity(0.65))
                }
                VStack(alignment:.leading,spacing:7){
                    Text(model.snapshot?.title ?? "从喜欢的一首歌开始").font(.system(size:27,weight:.semibold)).foregroundColor(.white).lineLimit(2)
                    Text([model.snapshot?.artist,model.snapshot?.album].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:"  /  ")).font(.system(size:13)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }
                VStack(spacing:6){
                    ProgressView(value:min(1,max(0,model.position/max(1,model.snapshot?.duration ?? 1)))).tint(mint)
                        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.lyricJumped || model.snapshot?.playing != true ? nil : .linear(duration:0.1),value:model.position)
                    HStack{Text(clock(model.position));Spacer();Text(clock(model.snapshot?.duration ?? 0))}.font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.65))
                }
                Divider().overlay(.white.opacity(0.1))
                KaraokeText(model:model,color:.white.opacity(0.85),fontSize:21)
                    .frame(maxWidth:.infinity,alignment:.center).padding(.top,2)
                Text(model.secondaryText).font(.system(size:12)).foregroundColor(.white.opacity(0.65)).lineLimit(2).frame(maxWidth:.infinity,alignment:.center)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(ink).cornerRadius(12)
            card{VStack(alignment:.leading,spacing:10){
                ViewThatFits(in:.horizontal){
                    HStack(spacing:16){
                        lyricsSourceBadges
                        Spacer(minLength:0)
                        lyricsActions.fixedSize()
                    }
                    VStack(alignment:.leading,spacing:10){
                        lyricsSourceBadges
                        HStack{Spacer(minLength:0);lyricsActions.fixedSize()}
                    }
                }
                Text(model.state).font(.system(size:12)).foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }}
            if let doc=model.document{
                card(verticalPadding:10){lyricsList(doc)}
            }else{
                card{VStack(alignment:.leading,spacing:9){
                    Label("还没有找到歌词",systemImage:"text.bubble").font(.system(size:14,weight:.medium))
                    Text("音频内嵌歌词、同名 LRC / SRT，或可选的在线匹配。歌曲信息读取始终跟随系统。").font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                    Button("管理歌词来源"){page = .sources}.padding(.top,4)
                }}
            }
            footer(verticalPadding:4){Text("播放、暂停和跳转请在播放器中操作。岸词只读取信息。").font(.system(size:10)).foregroundColor(.secondary)}
        }
    }
    private var lyricsSourceBadges:some View {
        HStack(spacing:8){
            pill(model.document?.source ?? "等待歌词来源",icon:model.document == nil ? "text.magnifyingglass" : "text.alignleft")
            if let doc=model.document{pill(doc.timed ? "有时间轴" : "无时间轴",icon:doc.timed ? "clock" : "text.justify").fixedSize()}
        }
    }
    private var lyricsActions:some View {
        HStack{
            Button{model.chooseFile()} label:{Label("选择歌词 / 音频",systemImage:"doc.badge.plus")}.disabled(model.snapshot == nil)
            if model.isLoadingLyrics{ProgressView().controlSize(.small).frame(width:14).accessibilityLabel("正在匹配歌词")}
            Button{model.forceReload()} label:{Label("刷新歌词",systemImage:"arrow.clockwise")}.disabled(model.isLoadingLyrics).help("重新读取当前歌曲并重试匹配，暂停时也可使用（⌘R）")
        }
    }
    @ViewBuilder private func lyricsList(_ doc:LyricsDocument)->some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text("完整歌词").font(.system(size:13,weight:.semibold));Spacer();if model.matchedFile != nil{Button("在访达中显示"){model.revealFile()}.font(.system(size:11))}}
            if doc.timed {
                ScrollViewReader{proxy in
                    ScrollView{
                        LazyVStack(alignment:.leading,spacing:3){ForEach(Array(doc.lines.enumerated()),id:\.offset){index,line in
                            HStack(alignment:.top,spacing:15){Text(clock(line.time)).font(.system(size:10,design:.monospaced)).foregroundColor(.secondary).frame(width:36,alignment:.leading);Text(line.text.isEmpty ? "间奏" : line.text).font(.system(size:14,weight:model.currentIndex==index ? .semibold : .regular)).foregroundColor(model.currentIndex==index ? .teal : .primary).textSelection(.enabled);Spacer(minLength:0)}
                                .padding(10).background(model.currentIndex==index ? Color.teal.opacity(0.09) : .clear).cornerRadius(7).id(index)
                        }}.padding(5)
                    }.frame(height:170).onChange(of:model.currentIndex){index in
                        guard let index else{return}
                        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion{proxy.scrollTo(index,anchor:.center)}else{withAnimation(.easeOut(duration:0.2)){proxy.scrollTo(index,anchor:.center)}}
                    }
                }
            }else{ScrollView{Text(doc.plain).font(.system(size:14)).lineSpacing(7).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(12)}.frame(height:170)}
        }
    }
    private var sourcesPage:some View {
        VStack(alignment:.leading,spacing:22){
            heading("歌词，从哪里来？","播放器信息读取面向所有系统媒体来源；下面的设置只决定到哪里找歌词。")
            card{
                VStack(alignment:.leading,spacing:12){
                    Label("当前播放器提供的文件路径",systemImage:"music.note").font(.system(size:14,weight:.semibold))
                    Text("如果播放器发布本地音频路径，直接读取该文件的内嵌歌词及同名旁挂歌词，不限定目录。流媒体通常不提供可访问的音频文件。").font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                    pill("自动读取 · 只读访问",icon:"checkmark.circle")
                }
            }
            card{VStack(alignment:.leading,spacing:12){
                HStack{Text("本地匹配目录").font(.system(size:15,weight:.semibold));Spacer();Button{model.chooseRoots()} label: {Label("添加目录",systemImage:"plus")}}
                Text("播放器没有给出文件路径时，用歌名、歌手与专辑在这些目录中匹配。可添加多个目录；不会修改音频文件。").font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                ForEach(model.roots,id:\.self){path in
                    HStack(spacing:10){Image(systemName:"folder.fill").foregroundColor(.teal);VStack(alignment:.leading,spacing:4){Text(URL(fileURLWithPath:path).lastPathComponent).font(.system(size:13,weight:.medium));Text(path).font(.system(size:10)).foregroundColor(.secondary).textSelection(.enabled).lineLimit(2)};Spacer();Button{model.removeRoot(path)} label: {Image(systemName:"minus.circle")}.buttonStyle(.borderless).help("仅移除匹配目录，不删除文件").accessibilityLabel("移除目录 \(path)")}.padding(14).background(Color(nsColor:.windowBackgroundColor)).cornerRadius(10)
                }
                HStack{Text(model.libraryStatus).font(.system(size:11)).foregroundColor(.secondary);Spacer();Button("重新扫描"){model.rescan()}.font(.system(size:11))}
            }}
            card{
                VStack(alignment:.leading,spacing:12){
                    HStack{Toggle("在线补充歌词",isOn:$model.online).toggleStyle(.switch);Spacer();if model.isMatchingOnline{ProgressView().controlSize(.small).accessibilityLabel("正在匹配在线歌词")};Button(model.isMatchingOnline ? "重新在线匹配" : "刷新在线匹配"){model.refreshLyrics(preferOnline:true)}.disabled(!model.online).help("重新查询在线歌词；查询中点击可取消旧请求并重试")}
                    Toggle("优先使用在线歌词",isOn:$model.preferOnlineLyrics).disabled(!model.online)
                    Text("开启后，在线匹配成功时优先显示在线歌词；查询期间及匹配失败时使用本地歌词。关闭后仅在本地无歌词时自动查询。此选项只改变显示来源，不修改歌词或音频文件。")
                        .font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("点击“刷新在线匹配”会主动重新查询。按启用的来源和优先级发送歌名、歌手，以及匹配所需的专辑与时长，对方可见网络来源 IP。不会发送文件路径、音频内容或账号信息。").font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }
            card{OnlineSourcesView(model:model)}
            footer{VStack(alignment:.leading,spacing:22){
            HStack{Button("为当前歌曲手动选择文件"){model.chooseFile()}.disabled(model.snapshot == nil);Button("恢复自动匹配"){model.clearManual()}.disabled(model.snapshot == nil)}
            Text("支持 MP3 USLT / SYLT、M4A 内嵌歌词、FLAC Vorbis 注释，以及 LRC、SRT、纯文本。没有时间戳的歌词按原文显示，不虚构同步进度。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            }}
        }
    }
    private var appearancePage:some View {
        VStack(alignment:.leading,spacing:22){
            HStack{heading("留在视线边缘。","Dock 融合使用原生毛玻璃；精确跟随 Dock 尺寸可选授权辅助功能。");Spacer();Button("预览 10 秒"){model.preview()}}
            card{VStack(alignment:.leading,spacing:17){
                Toggle("显示底部歌词条",isOn:$model.overlayVisible)
                Toggle("暂停时隐藏",isOn:$model.hidePaused)
                Toggle("鼠标靠近歌词条或 Dock 时让位",isOn:$model.hideNearDock).disabled(model.placement=="dock")
                if model.placement=="dock"{Text("融合模式始终让位，方便访问 Dock 图标。").font(.system(size:10)).foregroundColor(.secondary)}
                Toggle("显示第二行（翻译或下一句）",isOn:$model.twoLines)
            }}
            card{VStack(alignment:.leading,spacing:14){
                Toggle("歌词流光效果",isOn:$model.karaokeEnabled)
                ColorPicker("流光颜色",selection:$model.karaokeColor,supportsOpacity:false)
                    .disabled(!model.karaokeEnabled)
                    .modifier(SidebarFocusAppearance())
                VStack(alignment:.leading,spacing:6){
                    HStack{Text("普通 LRC 扫光速度");Spacer();Text("\(Int((model.karaokeSpeed*100).rounded()))%").foregroundColor(.secondary)}
                    Slider(value:$model.karaokeSpeed,in:0.5...2,step:0.01).accessibilityLabel("普通 LRC 扫光速度")
                    Text("100% 按整句时长推进；数值越大，染色完成越早。不影响逐字时间戳、SRT 或换句时间。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                }.disabled(!model.karaokeEnabled)
                Text("仅为第一行大歌词染色，第二行保留原色。增强 LRC 跟随逐字时间，普通歌词按句时长估算。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            }}
            card{VStack(alignment:.leading,spacing:12){
                Label(model.dockStatus,systemImage:model.dockExact ? "checkmark.circle" : "rectangle.dashed").font(.system(size:12,weight:.medium))
                Text("融合模式覆盖原 Dock 区域，自动跟随尺寸和屏幕，鼠标靠近时还原图标。无需权限可估算布局；允许辅助功能后可精确读取 Dock 位置、大小及自动隐藏状态。左右侧 Dock 使用内侧贴靠布局。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                if !model.dockGeometryDetails.isEmpty{Text(model.dockGeometryDetails).font(.system(size:10,design:.monospaced)).foregroundColor(.secondary).textSelection(.enabled)}
                if !model.dockExact{Button("允许精确读取 Dock 布局…"){model.requestDockLayoutAccess()}}
            }}
            card{VStack(alignment:.leading,spacing:18){
                Picker("显示位置",selection:$model.placement){Text("Dock 上方").tag("above");Text("与 Dock 融合").tag("dock");Text("屏幕底边窄条").tag("bottom")}
                Text(model.placement=="dock" ? "覆盖 Dock 图标区域，鼠标靠近即还原图标。" : model.placement=="bottom" ? "全宽窄条紧贴屏幕最底边，位于 Dock 之上。" : "独立浮窗位于 Dock 上沿之外，不覆盖 Dock。").font(.system(size:10)).foregroundColor(.secondary)
                Picker("显示屏幕",selection:$model.display){Text("主屏幕").tag("main");Text("跟随鼠标所在屏幕").tag("mouse")}.disabled(model.placement=="dock")
                Picker("歌词配色",selection:$model.theme){Text("系统毛玻璃").tag("glass");Text("墨色").tag("ink");Text("松绿").tag("pine");Text("暖纸").tag("paper");Text("自定义").tag("custom")}.pickerStyle(.segmented)
                if model.theme=="custom" {
                    ColorPicker("主歌词颜色",selection:$model.customLyricColor,supportsOpacity:false).modifier(SidebarFocusAppearance())
                    ColorPicker("第二行文字颜色",selection:$model.customSecondaryColor,supportsOpacity:false).modifier(SidebarFocusAppearance())
                    ColorPicker("歌词背景颜色",selection:$model.customBackgroundColor,supportsOpacity:false).modifier(SidebarFocusAppearance())
                    Text("自定义颜色自动保存；切换预设不会清除自定义颜色。背景透明度由下方滑块控制，流光颜色在上方单独设置。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                    VStack(spacing:6){
                        Text("让喜欢的歌，留在视线边缘").font(.system(size:18,weight:.medium)).foregroundColor(model.customLyricColor)
                        if model.twoLines{Text("第二行歌词颜色预览").font(.system(size:12)).foregroundColor(model.customSecondaryColor)}
                    }.frame(maxWidth:.infinity).padding(.vertical,18).background(model.customBackgroundColor.opacity(model.opacity)).cornerRadius(12)
                        .accessibilityLabel("自定义歌词配色预览")
                }
                VStack(alignment:.leading){HStack{Text("字号");Spacer();Text("\(Int(model.fontSize)) pt").foregroundColor(.secondary)};Slider(value:$model.fontSize,in:16...34,step:1).accessibilityLabel("歌词字号")}
                VStack(alignment:.leading){HStack{Text("背景不透明度");Spacer();Text("\(Int(model.opacity*100))%").foregroundColor(.secondary)};Slider(value:$model.opacity,in:0.45...1).accessibilityLabel("背景不透明度").disabled(model.placement=="dock" && model.theme=="glass")}
                if model.placement=="dock" {
                    VStack(alignment:.leading){HStack{Text("Dock 水平边距微调");Spacer();Text(String(format:"%+.0f pt",model.dockPadding)).foregroundColor(.secondary)};Slider(value:$model.dockPadding,in:-20...20,step:1).accessibilityLabel("Dock 水平边距微调")}
                    VStack(alignment:.leading){HStack{Text("Dock 垂直位置微调");Spacer();Text(String(format:"%+.0f pt",model.dockOffset)).foregroundColor(.secondary)};Slider(value:$model.dockOffset,in:-16...16,step:1).accessibilityLabel("Dock 垂直位置微调")}
                }
                VStack(alignment:.leading){HStack{Text("同步微调");Spacer();Text(String(format:"%+.1f 秒",model.offset)).foregroundColor(.secondary)};Slider(value:$model.offset,in:-5...5,step:0.1).accessibilityLabel("同步微调");Text("正值让歌词提前，负值让歌词延后。").font(.system(size:10)).foregroundColor(.secondary)}
            }.font(.system(size:12))}
        }
    }
    private var privacyPage:some View {
        VStack(alignment:.leading,spacing:22){
            heading("读取最少的信息。","播放信息与歌词来源分开处理，数据流可以直接检查源码。")
            card{VStack(alignment:.leading,spacing:15){
                Label("不读取账号、Cookie、聊天记录或浏览器数据库",systemImage:"checkmark.shield")
                Label("不请求屏幕录制或完全磁盘访问",systemImage:"hand.raised")
                Label("辅助功能仅用于可选的 Dock 布局读取",systemImage:"rectangle.bottomthird.inset.filled")
                Label("不修改音频、不注入播放器、不发送播放控制",systemImage:"music.note")
                Label("无遥测、无自动更新服务",systemImage:"network.slash")
            }.font(.system(size:12))}
            card{VStack(alignment:.leading,spacing:12){
                Text("当前诊断").font(.system(size:15,weight:.semibold))
                diagnostic("播放器",model.playerName)
                diagnostic("应用标识",model.snapshot?.bundle ?? "—")
                diagnostic("状态",model.snapshot?.playing==true ? "正在播放" : model.snapshot == nil ? "无媒体信息" : "已暂停")
                diagnostic("歌词来源",model.document?.source ?? "尚未匹配")
                diagnostic("本地文件",model.matchedFile?.path ?? "未匹配本地文件")
                diagnostic("在线查询",model.online ? "已开启，按启用来源查询" : "关闭；应用不发起网络请求")
                diagnostic("Dock 融合",model.dockStatus)
                diagnostic("匹配目录",String(model.roots.count)+" 个 / "+String(model.fileCount)+" 个音频文件")
            }}
            footer{VStack(alignment:.leading,spacing:22){
            Text("兼容范围：能够向 macOS 发布“正在播放”信息的播放器与浏览器。系统不提供信息的应用需单独适配；部分网页只发布标题，没有准确进度。系统媒体读取依赖私有接口，未来 macOS 更新可能需要维护。").font(.system(size:12)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("重新读取歌词"){model.forceReload()}
                Spacer()
                Button("AGPL v3.0 开源协议"){
                    if let url=Bundle.main.url(forResource:"LICENSE",withExtension:nil){NSWorkspace.shared.open(url)}
                }
            }
            Text("岸词 · Copyright © 2026 dongx · AGPL-3.0-only。自由软件，不提供任何担保。").font(.system(size:11)).foregroundColor(.secondary)
            }}
        }
    }
    private func footer<Content:View>(verticalPadding:CGFloat = 18,@ViewBuilder content:()->Content)->some View{content().frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,18).padding(.vertical,verticalPadding)}
    private func card<Content:View>(verticalPadding:CGFloat = 18,@ViewBuilder content:()->Content)->some View{content().frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,18).padding(.vertical,verticalPadding).background(Color(nsColor:.windowBackgroundColor)).cornerRadius(12)}
    private func diagnostic(_ title:String,_ value:String)->some View{HStack(alignment:.top){Text(title).foregroundColor(.secondary).frame(width:84,alignment:.leading);Text(value).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)}.font(.system(size:11))}
}
func clock(_ value:Double)->String{guard value.isFinite,value>=0 else{return "0:00"};let seconds=Int(value);return String(format:"%d:%02d",seconds/60,seconds%60)}
