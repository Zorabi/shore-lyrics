// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AppKit
import CoreText

/// Core Text supplies both glyph positions and the text we draw, so masks stay aligned.
struct KaraokeGlyphLayout {
    let line: CTLine
    let boundaries: [CGFloat]
    let width: CGFloat

    init(text: String, font: NSFont) {
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white
        ]))
        width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var offsets = [CGFloat(0)]
        var utf16Offset = 0
        for character in text {
            utf16Offset += String(character).utf16.count
            offsets.append(CTLineGetOffsetForStringIndex(line, utf16Offset, nil))
        }
        boundaries = offsets
    }

    func frontier(progress: Double) -> (edge: CGFloat, lower: CGFloat, upper: CGFloat) {
        let count = boundaries.count-1
        guard count > 0 else { return (0,0,0) }
        let position = min(1,max(0,progress))*Double(count)
        let index = min(count-1,Int(position))
        let lower = boundaries[index], upper = boundaries[index+1]
        return (lower+(upper-lower)*CGFloat(position-Double(index)),min(lower,upper),max(lower,upper))
    }
}

struct KaraokeText: View {
    @ObservedObject var model: AppModel
    var color: Color
    var fontSize: CGFloat
    var rounded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60, paused: model.snapshot?.playing != true || !model.karaokeEnabled)) { context in
            let projected = model.snapshot?.elapsed(now:context.date.timeIntervalSince1970) ?? model.position
            // The model owns line changes; never apply the next line's progress to outgoing text.
            let position = model.document?.index(at:projected+model.offset) == model.currentIndex ? projected : model.position
            GlyphText(text:model.primaryLyricText, progress:model.lyricProgress(at:position),
                      color:NSColor(color), highlight:NSColor(model.karaokeColor),
                      fontSize:fontSize, rounded:rounded, glow:!reduceMotion, dark:colorScheme == .dark, animateLineChange:!reduceMotion && !model.lyricJumped)
        }
        .frame(height:ceil(fontSize*1.3))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("当前歌词：\(model.primaryLyricText)")
        .transaction { $0.animation=nil }
    }
}

private struct GlyphText: NSViewRepresentable {
    var text: String
    var progress: Double?
    var color: NSColor
    var highlight: NSColor
    var fontSize: CGFloat
    var rounded: Bool
    var glow: Bool
    var dark: Bool
    var animateLineChange: Bool

    func makeNSView(context: Context) -> GlyphTextView {
        let view=GlyphTextView()
        view.wantsLayer=true
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        return view
    }
    func updateNSView(_ view: GlyphTextView, context: Context) {
        view.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        let base=NSFont.systemFont(ofSize:fontSize,weight:rounded ? .semibold : .medium)
        let font=rounded ? NSFont(descriptor:base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,size:fontSize) ?? base : base
        if view.text != text {
            view.prepareForLineChange(animated:animateLineChange)
        } else if !animateLineChange {
            view.cancelLineTransition()
        }
        if view.text != text || view.font != font {
            view.text=text; view.font=font
            view.layout=KaraokeGlyphLayout(text:text,font:font)
        }
        view.progress=progress; view.color=color; view.highlight=highlight; view.glow=glow
        view.needsDisplay=true
    }
}

struct KaraokeFrame {
    var layout:KaraokeGlyphLayout
    var font:NSFont
    var progress:Double?
    var color:NSColor
    var highlight:NSColor
    var glow:Bool
}

final class GlyphTextView: NSView {
    var text=""
    var font=NSFont.systemFont(ofSize:22)
    var layout:KaraokeGlyphLayout?
    var progress:Double?
    var color=NSColor.labelColor
    var highlight=NSColor.systemTeal
    var glow=true

    private(set) var outgoingFrame:KaraokeFrame?
    private var transitionStart:TimeInterval=0
    private var transitionTimer:Timer?
    private let transitionDuration:TimeInterval=0.24

    func prepareForLineChange(animated:Bool) {
        cancelLineTransition()
        guard animated,let layout,!text.isEmpty else{return}
        // Capture values: the outgoing line must never read the next line's text or clock.
        outgoingFrame=KaraokeFrame(layout:layout,font:font,progress:progress,color:color,highlight:highlight,glow:false)
        transitionStart=ProcessInfo.processInfo.systemUptime
        let timer=Timer(timeInterval:1.0/60,repeats:true){[weak self] timer in
            guard let self else{timer.invalidate();return}
            if ProcessInfo.processInfo.systemUptime-self.transitionStart>=self.transitionDuration {
                self.cancelLineTransition()
            }
            self.needsDisplay=true
        }
        transitionTimer=timer
        RunLoop.main.add(timer,forMode:.common)
    }
    func cancelLineTransition() {
        transitionTimer?.invalidate();transitionTimer=nil;outgoingFrame=nil
        needsDisplay=true
    }
    deinit {transitionTimer?.invalidate()}

    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        guard let context=NSGraphicsContext.current?.cgContext else{return}
        context.clear(bounds)
        let elapsed=ProcessInfo.processInfo.systemUptime-transitionStart
        let fraction=min(1,max(0,elapsed/transitionDuration))
        let blend=fraction*fraction*(3-2*fraction)
        if let outgoingFrame {
            drawFrame(outgoingFrame,in:context,alpha:1-blend,offset:CGFloat(blend)*5)
        }
        if let layout {
            let frame=KaraokeFrame(layout:layout,font:font,progress:progress,color:color,highlight:highlight,glow:glow)
            drawFrame(frame,in:context,alpha:outgoingFrame == nil ? 1 : blend,offset:outgoingFrame == nil ? 0 : -CGFloat(1-blend)*5)
        }
    }
    private func drawFrame(_ frame:KaraokeFrame,in context:CGContext,alpha:Double,offset:CGFloat) {
        let layout=frame.layout,font=frame.font,progress=frame.progress
        let color=frame.color,highlight=frame.highlight,glow=frame.glow
        guard layout.width>0,alpha>0 else{return}
        // Composite each complete lyric once, including its base and highlight.
        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x:0,y:offset)
        context.beginTransparencyLayer(auxiliaryInfo:nil)
        // Scale the same glyph layout rather than separately measuring an overlay.
        let scale=min(1,bounds.width/layout.width)
        guard scale>0 else{return}
        let x=(bounds.width-layout.width*scale)/2
        let baseline=(bounds.height-(font.ascender-font.descender)*scale)/2-font.descender*scale
        context.saveGState()
        context.translateBy(x:x,y:baseline)
        context.scaleBy(x:scale,y:scale)
        context.textMatrix = .identity
        let textBounds=CGRect(x:0,y:font.descender-3,width:layout.width,height:font.ascender-font.descender+6)
        func draw(_ tint:NSColor,in rect:CGRect) {
            context.saveGState()
            context.clip(to:rect)
            // Draw the glyph alpha as a mask, then tint with a native dynamic color.
            context.beginTransparencyLayer(auxiliaryInfo:nil)
            context.textPosition = .zero
            CTLineDraw(layout.line,context)
            context.setBlendMode(.sourceIn)
            context.setFillColor(tint.cgColor)
            context.fill(textBounds)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        draw(color,in:textBounds)
        if let progress {
            let frontier=layout.frontier(progress:progress)
            draw(highlight,in:CGRect(x:0,y:textBounds.minY,width:frontier.edge,height:textBounds.height))
            if glow,progress>0,progress<1 {
                // Keep the leading light behind the sung edge. Lighting the unsung half first
                // makes one character appear to be colored twice before the next character.
                let radius=max(3,font.pointSize*0.55)
                let start=max(0,frontier.edge-radius)
                context.saveGState()
                context.clip(to:CGRect(x:start,y:textBounds.minY,width:frontier.edge-start,height:textBounds.height))
                context.beginTransparencyLayer(auxiliaryInfo:nil)
                context.textPosition = .zero
                CTLineDraw(layout.line,context)
                context.setBlendMode(.sourceIn)
                let bright=highlight.blended(withFraction:0.38,of:.white) ?? highlight
                let colors=[bright.withAlphaComponent(0).cgColor,bright.cgColor] as CFArray
                if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) {
                    context.drawLinearGradient(gradient,start:CGPoint(x:frontier.edge-radius,y:0),end:CGPoint(x:frontier.edge,y:0),options:[])
                }
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        context.restoreGState()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
