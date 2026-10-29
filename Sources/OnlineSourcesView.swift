// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AppKit

struct OnlineSourcesView:View {
    @ObservedObject var model:AppModel
    @State private var editing:OnlineLyricsSource?
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{
                Text("在线歌词来源").font(.system(size:14,weight:.semibold))
                Spacer()
                Button("恢复内置默认"){model.restoreOnlineSourcesDefaults()}
                Button{editing=OnlineLyricsSource(name:"")} label:{Label("添加来源",systemImage:"plus")}
            }
            Text("拖动列表行调整优先级。自动匹配按顺序逐个查询，找到歌词后停止。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            OnlineSourceTable(model:model,sources:model.onlineSources,edit:{editing=$0})
                .frame(height:min(330,CGFloat(model.onlineSources.count)*49+4))
            Picker("本次匹配来源",selection:$model.selectedOnlineSource){
                Text("自动（按上方顺序）").tag("")
                ForEach(model.onlineSources.filter{$0.enabled}){source in Text(source.name).tag(source.id)}
                if let source=model.onlineSources.first(where:{$0.id==model.selectedOnlineSource && !$0.enabled}) {
                    Text(source.name+"（已停用）").tag(source.id)
                }
            }.disabled(!model.online)
            Text("修改配置会重新匹配当前歌曲。指定来源时仅查询该来源；停用的来源不会发起请求。来源配置和排序保存在本机。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
        }.modifier(OnlineSourcesFocus()).sheet(item:$editing){source in
            OnlineSourceEditor(source:source){model.saveOnlineSource($0)}
        }
    }
}

struct OnlineSourceEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var source:OnlineLyricsSource
    var save:(OnlineLyricsSource)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text(source.name.isEmpty ? "添加歌词来源" : "编辑歌词来源").font(.system(size:20,weight:.semibold))
            Text("填写可直接查询歌词的 HTTPS GET 接口，支持 LRC、SRT、纯文本或 JSON 响应。").font(.system(size:12)).foregroundColor(.secondary)
            field("来源名称",text:$source.name)
            field("请求地址模板",text:$source.urlTemplate)
            Text("必填占位符：{title} 歌名、{artist} 歌手；可选：{album} 专辑、{duration} 时长（秒）。参数自动编码。接口不应依赖浏览器登录或 Cookie。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            Picker("响应格式",selection:$source.format){Text("JSON").tag(OnlineLyricsSource.Format.json);Text("直接返回 LRC / 文本").tag(OnlineLyricsSource.Format.text)}
            if source.format == .json {
                field("同步歌词字段",text:$source.syncedPath)
                field("纯文本歌词字段",text:$source.plainPath)
                Text("至少填写一个。使用点号表示嵌套字段，例如 data.lrc.lyric；数组下标可写成 data.0.lyrics。优先读取同步歌词，空值时再读取纯文本。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Toggle("启用此来源",isOn:$source.enabled)
            Text("启用在线补充后，歌名、歌手及模板使用的专辑和时长会发送给该地址，对方可见来源 IP。不会发送音频或本地路径。只支持同域 HTTPS 重定向。").font(.system(size:11)).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            if let error=source.validationError {Text(error).font(.system(size:11)).foregroundColor(.red).fixedSize(horizontal:false,vertical:true)}
            HStack{Spacer();Button("取消"){dismiss()}.keyboardShortcut(.cancelAction);Button("保存"){save(source);dismiss()}.keyboardShortcut(.defaultAction).disabled(source.validationError != nil)}
        }.padding(24).frame(width:540).background(Color(nsColor:.windowBackgroundColor))
    }
    private func field(_ label:String,text:Binding<String>)->some View {
        VStack(alignment:.leading,spacing:5){Text(label).font(.system(size:12,weight:.medium));SourceTextField(text:text,label:label).frame(height:25)}
    }
}

/// Native text editing and keyboard navigation, with a soft focus background instead of a ring.
private struct SourceTextField:NSViewRepresentable {
    @Binding var text:String
    var label:String
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField()
        field.isBezeled=true;field.bezelStyle = .roundedBezel
        field.focusRingType = .none;field.drawsBackground=true
        field.font = .systemFont(ofSize:13);field.delegate=context.coordinator
        field.usesSingleLineMode=true;field.lineBreakMode = .byClipping
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        field.setAccessibilityLabel(label)
        return field
    }
    func updateNSView(_ view:NSTextField,context:Context){
        context.coordinator.parent=self
        if view.stringValue != text{view.stringValue=text}
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSTextField,context:Context)->CGSize?{CGSize(width:proposal.width ?? 300,height:25)}
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:SourceTextField
        init(_ parent:SourceTextField){self.parent=parent}
        func controlTextDidChange(_ notification:Notification){if let field=notification.object as? NSTextField{parent.text=field.stringValue}}
        func controlTextDidBeginEditing(_ notification:Notification){(notification.object as? NSTextField)?.backgroundColor=NSColor.selectedControlColor.withAlphaComponent(0.10)}
        func controlTextDidEndEditing(_ notification:Notification){(notification.object as? NSTextField)?.backgroundColor = .textBackgroundColor}
    }
}

private struct OnlineSourcesFocus:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 14.0,*){content.focusEffectDisabled()}else{content}
    }
}
