// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AppKit

/// Native table drag-and-drop avoids nested SwiftUI scroll/drop gesture conflicts.
struct OnlineSourceTable:NSViewRepresentable {
    var model:AppModel
    var sources:[OnlineLyricsSource]
    var edit:(OnlineLyricsSource)->Void
    private static let pasteboardType=NSPasteboard.PasteboardType("dongx.shorelyrics.source")

    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let table=NSTableView()
        table.headerView=nil;table.rowHeight=48;table.intercellSpacing=NSSize(width:0,height:1)
        table.backgroundColor = .clear;table.focusRingType = .none
        table.usesAlternatingRowBackgroundColors=false
        table.selectionHighlightStyle = .regular
        table.verticalMotionCanBeginDrag=true
        table.setAccessibilityLabel("在线来源优先级，可拖动行排序")
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id,width) in [("drag",26.0),("enabled",28.0),("name",300.0),("actions",112.0)] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id))
            column.width=width;column.minWidth=id=="name" ? 120 : width
            column.resizingMask=id=="name" ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.dataSource=context.coordinator;table.delegate=context.coordinator
        table.registerForDraggedTypes([Self.pasteboardType])
        table.setDraggingSourceOperationMask(.move,forLocal:true)
        table.setDraggingSourceOperationMask([],forLocal:false)
        let scroll=NSScrollView()
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.borderType = .noBorder
        scroll.documentView=table
        context.coordinator.table=table
        context.coordinator.refresh(self)
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context){context.coordinator.refresh(self)}

    final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
        var parent:OnlineSourceTable
        weak var table:NSTableView?
        private var displayed:[OnlineLyricsSource]=[]
        init(_ parent:OnlineSourceTable){self.parent=parent}
        func refresh(_ value:OnlineSourceTable){
            parent=value
            // Playback updates at 10 Hz. Reloading during a drag would cancel the session.
            guard displayed != value.sources else{return}
            let selected=table.flatMap{displayed.indices.contains($0.selectedRow) ? displayed[$0.selectedRow].id : nil}
            displayed=value.sources
            table?.reloadData()
            if let selected,let index=displayed.firstIndex(where:{$0.id==selected}){table?.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
        }
        func numberOfRows(in tableView:NSTableView)->Int{displayed.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            guard displayed.indices.contains(row),let column=tableColumn?.identifier.rawValue else{return nil}
            let source=displayed[row],cell=NSTableCellView()
            switch column {
            case "drag":
                let image=NSImageView(image:NSImage(systemSymbolName:"line.3.horizontal",accessibilityDescription:"拖动调整 \(source.name) 的优先级")!)
                image.contentTintColor = .secondaryLabelColor;image.translatesAutoresizingMaskIntoConstraints=false
                cell.addSubview(image)
                NSLayoutConstraint.activate([image.centerXAnchor.constraint(equalTo:cell.centerXAnchor),image.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            case "enabled":
                let button=NSButton(checkboxWithTitle:"",target:self,action:#selector(toggleSource(_:)))
                button.state=source.enabled ? .on : .off
                button.identifier=NSUserInterfaceItemIdentifier(source.id);button.focusRingType = .none
                button.setAccessibilityLabel("启用 \(source.name)")
                button.translatesAutoresizingMaskIntoConstraints=false
                cell.addSubview(button)
                NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo:cell.centerXAnchor),button.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            case "name":
                let title=NSTextField(labelWithString:source.name)
                title.font = .systemFont(ofSize:12,weight:.medium)
                let detail=NSTextField(labelWithString:Self.detail(source))
                detail.font = .systemFont(ofSize:10);detail.textColor = .secondaryLabelColor
                for label in [title,detail]{label.lineBreakMode = .byTruncatingTail;label.translatesAutoresizingMaskIntoConstraints=false;cell.addSubview(label)}
                NSLayoutConstraint.activate([
                    title.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:4),title.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-4),title.bottomAnchor.constraint(equalTo:cell.centerYAnchor,constant:-1),
                    detail.leadingAnchor.constraint(equalTo:title.leadingAnchor),detail.trailingAnchor.constraint(lessThanOrEqualTo:cell.trailingAnchor,constant:-4),detail.topAnchor.constraint(equalTo:cell.centerYAnchor,constant:2)
                ])
            case "actions":
                let stack=NSStackView();stack.orientation = .horizontal;stack.spacing=4
                func button(_ symbol:String,_ label:String,_ action:Selector,enabled:Bool=true){
                    let button=NSButton(image:NSImage(systemSymbolName:symbol,accessibilityDescription:label)!,target:self,action:action)
                    button.isBordered=false;button.focusRingType = .none;button.isEnabled=enabled
                    button.identifier=NSUserInterfaceItemIdentifier(source.id);button.toolTip=label;button.setAccessibilityLabel(label)
                    button.widthAnchor.constraint(equalToConstant:22).isActive=true
                    button.heightAnchor.constraint(equalToConstant:26).isActive=true
                    stack.addArrangedSubview(button)
                }
                button("chevron.up","提高 \(source.name) 的优先级",#selector(moveUp(_:)),enabled:row>0)
                button("chevron.down","降低 \(source.name) 的优先级",#selector(moveDown(_:)),enabled:row<displayed.count-1)
                if !source.builtIn {
                    button("pencil","编辑 \(source.name)",#selector(editSource(_:)))
                    button("trash","移除 \(source.name)",#selector(removeSource(_:)))
                }
                stack.translatesAutoresizingMaskIntoConstraints=false;cell.addSubview(stack)
                NSLayoutConstraint.activate([stack.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-4),stack.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            default:return nil
            }
            return cell
        }
        private static func detail(_ source:OnlineLyricsSource)->String {
            switch source.kind {
            case .lrclib:return "同步歌词 / 纯文本 · lrclib.net"
            case .netease:return "歌曲匹配 / LRC · music.163.com"
            case .qq:return "歌曲匹配 / LRC · c.y.qq.com"
            case .kugou:return "歌词候选 / LRC · lyrics.kugou.com"
            case .amll:return "网易云歌曲 ID / ESLRC · 社区歌词库"
            case .custom:return source.builtIn ? "纯文本 · api.lyrics.ovh" : "自定义 HTTPS · \(source.format == .json ? "JSON" : "LRC / 文本")"
            }
        }
        private func index(_ button:NSButton)->Int?{parent.model.onlineSources.firstIndex{$0.id==button.identifier?.rawValue}}
        @objc private func toggleSource(_ sender:NSButton){if let index=index(sender){parent.model.onlineSources[index].enabled=sender.state == .on}}
        @objc private func moveUp(_ sender:NSButton){if let index=index(sender),index>0{parent.model.moveOnlineSources(from:IndexSet(integer:index),to:index-1)}}
        @objc private func moveDown(_ sender:NSButton){if let index=index(sender),index<parent.model.onlineSources.count-1{parent.model.moveOnlineSources(from:IndexSet(integer:index),to:index+2)}}
        @objc private func editSource(_ sender:NSButton){if let index=index(sender){parent.edit(parent.model.onlineSources[index])}}
        @objc private func removeSource(_ sender:NSButton){if let index=index(sender){parent.model.removeOnlineSource(parent.model.onlineSources[index])}}

        func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {
            guard displayed.indices.contains(row) else{return nil}
            let item=NSPasteboardItem();item.setString(displayed[row].id,forType:OnlineSourceTable.pasteboardType)
            return item
        }
        func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
            guard let id=info.draggingPasteboard.string(forType:OnlineSourceTable.pasteboardType),let from=displayed.firstIndex(where:{$0.id==id}) else{return []}
            var destination=row
            if operation == .on {destination=row+(from<row ? 1 : 0)}
            tableView.setDropRow(max(0,min(displayed.count,destination)),dropOperation:.above)
            return .move
        }
        func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation:NSTableView.DropOperation)->Bool {
            guard let id=info.draggingPasteboard.string(forType:OnlineSourceTable.pasteboardType),let from=parent.model.onlineSources.firstIndex(where:{$0.id==id}) else{return false}
            parent.model.moveOnlineSources(from:IndexSet(integer:from),to:max(0,min(parent.model.onlineSources.count,row)))
            return true
        }
    }
}
