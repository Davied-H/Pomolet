import SwiftUI
import AppKit

/// Mirrors CSS box-shadow: 0 18px 48px -22px #1d3d2a45, 0 2px 6px #19392408.
struct CardSurface: View {
    var palette: Palette
    var body: some View {
        ZStack {
            if !palette.dark {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x1d3d2a).opacity(69.0 / 255)).padding(22).blur(radius: 24).offset(y: 18)
                RoundedRectangle(cornerRadius: 24).fill(Color(hex: 0x193924).opacity(8.0 / 255)).blur(radius: 3).offset(y: 2)
            }
            RoundedRectangle(cornerRadius: 24).fill(palette.paper)
        }
    }
}
struct NativeToast: View {
    @ObservedObject var store: PomodoroStore
    @StateObject private var timeline = MotionTimeline()
    @State private var message: String?
    @State private var revision = 0
    private var palette: Palette { Palette(dark: store.dark) }
    private func bounds(_ text: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 10)
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        let width = min(315.2, ceil(natural))
        let measured = (text as NSString).boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lines = max(1, ceil(measured.height / font.boundingRectForFont.height))
        return CGSize(width: width + 34, height: lines * 15 + 26)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let message {
                let size = bounds(message)
                Text(message).font(SwiftUI.Font.system(size: 10)).foregroundStyle(palette.ink).multilineTextAlignment(.center).lineSpacing(3)
                    .frame(width: size.width - 34, height: size.height - 26).padding(.horizontal, 17).padding(.vertical, 13)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line, lineWidth: 1))
                    .shadow(color: Color(hex: 0x1d3d2a).opacity(23.0 / 255), radius: 10, y: 5)
                    .opacity(timeline.value("opacity"))
                    .position(x: 195, y: 13 + size.height / 2 + timeline.value("offset"))
                    .accessibilityLabel(message)
            }
        }.frame(width: 390, height: 420).allowsHitTesting(false)
            .onAppear { update(store.toast) }
            .onChange(of: store.toast) { _, value in update(value) }
    }
    private func update(_ value: String?) {
        revision += 1; let token = revision
        if let value {
            let hidden = message == nil; message = value
            timeline.animate("opacity", to: 1, from: hidden ? 0 : nil, duration: store.reduceMotion ? 0.1 : 0.36)
            timeline.animate("offset", to: 0, from: hidden ? (store.reduceMotion ? 0 : -bounds(value).height - 16) : nil, duration: store.reduceMotion ? 0.1 : 0.36)
        } else if let old = message {
            timeline.animate("opacity", to: 0, duration: store.reduceMotion ? 0.1 : 0.2, ease: .depart)
            timeline.animate("offset", to: store.reduceMotion ? 0 : -bounds(old).height - 16, duration: store.reduceMotion ? 0.1 : 0.2, ease: .depart)
            DispatchQueue.main.asyncAfter(deadline: .now() + (store.reduceMotion ? 0.1 : 0.2)) { if token == revision { message = nil } }
        }
    }
}

enum CSSFont {
    static func font(_ size: CGFloat, weight: Double, rounded: Bool = false) -> Font {
        let stops: [(Double, CGFloat)] = [(100,-0.8),(200,-0.6),(300,-0.4),(400,0),(500,0.23),(600,0.3),(700,0.4),(800,0.56),(900,0.62)]
        let bounded = min(900,max(100,weight)); let pair = zip(stops,stops.dropFirst()).first { bounded >= $0.0.0 && bounded <= $0.1.0 }!
        let t = (bounded-pair.0.0)/(pair.1.0-pair.0.0), raw = pair.0.1 + CGFloat(t)*(pair.1.1-pair.0.1)
        let base = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: raw))
        let descriptor = rounded ? base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor : base.fontDescriptor
        return Font(NSFont(descriptor: descriptor, size: size) ?? base)
    }
}

struct FocusClock: View, Animatable {
    var text: String
    var progress: Double
    var color: Color
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        Text(text).font(.system(size:53+11*progress,weight:.bold,design:.rounded)).monospacedDigit().tracking(-1.5)
            .foregroundStyle(color).frame(width:240,height:80).position(x:264-70*progress,y:161+105.4*progress).contentTransition(.identity)
    }
}
