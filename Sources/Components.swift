import SwiftUI
import AppKit

struct Palette {
    var dark: Bool
    var paper: Color { Color(hex: dark ? 0x000000 : 0xf8f5ed) }
    var ink: Color { Color(hex: dark ? 0xffffff : 0x202820) }
    var sub: Color { Color(hex: dark ? 0xa3a3a3 : 0x6c756b) }
    var line: Color { Color(hex: dark ? 0x292929 : 0xe3e4d9) }
    var accent: Color { Color(hex: dark ? 0xffffff : 0x0c874d) }
    var wash: Color { Color(hex: dark ? 0x1a1a1a : 0xe4eadd) }
    var side: Color { Color(hex: dark ? 0x111111 : 0xefeee5) }
    var button: Color { Color(hex: dark ? 0x121212 : 0xfdfbf5) }
    var minuteFocus: Color { Color(hex: dark ? 0x292929 : 0xdeddd5) }
    func controlFill(running: Bool) -> Color { running ? Color(hex: dark ? 0x202020 : 0xe2e7db) : accent }
    func controlInk(running: Bool) -> Color { dark ? (running ? .white : .black) : (running ? Color(hex: 0x344b39) : Color(hex: 0xfffdf5)) }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct Glyph: View {
    var name: String
    var size: CGFloat = 18
    var body: some View { Image(nsImage: Resources.icon(name)).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size).accessibilityHidden(true) }
}
struct QuietIconButton: View {
    var name: String
    var label: String
    var palette: Palette
    var size: CGFloat = 29
    var height: CGFloat? = nil
    var glyphSize: CGFloat = 18
    var glyphOpacity: Double = 1
    var glyphScale: Double = 1
    var glyphRotation: Double = 0
    var buttonOpacity: Double = 1
    var tooltip: String? = nil
    var foreground: Color? = nil
    var pressed = false
    var customTooltip = false
    var reduceMotion = false
    var focusID: String? = nil
    var action: () -> Void
    @State private var hovering = false
    @State private var keyboardFocused = false
    var body: some View {
        Button(action: action) { Glyph(name: name, size: glyphSize).foregroundStyle(foreground ?? palette.ink).opacity(glyphOpacity).scaleEffect(glyphScale).rotationEffect(.degrees(glyphRotation)).animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.45), value: glyphRotation).frame(width: size, height: height ?? size).background(hovering || pressed ? palette.wash : .clear, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle()) }
            .buttonStyle(.plain).opacity(buttonOpacity).onHover { hovering = $0 }.accessibilityLabel(label)
            .focusTarget(focusID)
            .onReceive(NotificationCenter.default.publisher(for: .focusDidChange)) { note in
                keyboardFocused = focusID != nil && note.object as? String == focusID
            }
            .modifier(NativeHelp(text: customTooltip ? nil : tooltip ?? label))
            .overlay(alignment: .topTrailing) {
                if customTooltip {
                    SoundTooltip(text: tooltip ?? label, visible: hovering || keyboardFocused, palette: palette, reduceMotion: reduceMotion)
                        .fixedSize().alignmentGuide(.top) { $0[.bottom] + 10 }.offset(x: 8).zIndex(8)
                }
            }
    }
}

private struct NativeHelp: ViewModifier {
    var text: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

/// HTML sound-tooltip counterpart. Anchor above the trailing edge, with a 10pt gap.
struct SoundTooltip: View {
    var text: String
    var visible: Bool
    var palette: Palette
    var reduceMotion = false
    @StateObject private var timeline = MotionTimeline()
    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(palette.paper)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(palette.ink, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottomTrailing) {
                Rectangle().fill(palette.ink).frame(width: 6, height: 6).rotationEffect(.degrees(45)).offset(x: -15, y: 3)
            }
            .opacity(timeline.value("opacity")) .offset(y: timeline.value("offset", fallback: 4))
            .onAppear { update() }.onChange(of: visible) { _, _ in update() }.onChange(of: reduceMotion) { _, _ in update() }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func update() {
        if reduceMotion { timeline.set("opacity", visible ? 1 : 0); timeline.set("offset", visible ? 0 : 4); return }
        timeline.animate("opacity", to: visible ? 1 : 0, duration: 0.16, ease: .cubic(0.25, 0.1, 0.25, 1))
        timeline.animate("offset", to: visible ? 0 : 4, duration: 0.2, ease: .cubic(0.25, 0.1, 0.25, 1), fallback: 4)
    }
}

/// Stable focus IDs let the app route arrows/Space only to the focused control group.
enum FocusRouting {
    static private(set) var currentID: String?
    static func activate(_ id: String) {
        guard currentID != id else { return }
        currentID = id; NotificationCenter.default.post(name: .focusDidChange, object: id)
    }
    static func deactivate(_ id: String) {
        guard currentID == id else { return }
        currentID = nil; NotificationCenter.default.post(name: .focusDidChange, object: nil)
    }
    static func request(_ id: String) { NotificationCenter.default.post(name: .focusRequest, object: id) }
}
private struct FocusTarget: ViewModifier {
    var id: String?
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused)
            .onChange(of: focused) { _, active in
                guard let id else { return }
                if active { FocusRouting.activate(id) } else { FocusRouting.deactivate(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusRequest)) { note in
                guard let id, note.object as? String == id else { return }; focused = true
            }
            .onDisappear { if let id { FocusRouting.deactivate(id) } }
    }
}
extension View {
    func focusTarget(_ id: String?) -> some View { modifier(FocusTarget(id: id)) }
}
extension Notification.Name {
    static let focusDidChange = Notification.Name("FocusDidChange")
    static let focusRequest = Notification.Name("FocusRequest")
}

struct NativeField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    var placeholder = ""
    var label: String
    var fontSize: CGFloat
    var weight: NSFont.Weight = .regular
    var tracking: CGFloat = 0
    var color: NSColor
    var placeholderColor: NSColor
    var alignment: NSTextAlignment = .left
    var limit: Int = 50
    var focusRequest = false
    var numericStepper = false
    var focusID: String? = nil
    var onValue: (String) -> Void
    var onFocus: (Bool) -> Void = { _ in }
    var onEnd: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: weight); field.textColor = color; field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail; field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.isEnabled = isEnabled
        field.delegate = context.coordinator; field.setAccessibilityLabel(label)
        context.coordinator.installFocusRequest(for: field)
        applyTypography(field)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        if !isEnabled && field.currentEditor() != nil {
            DispatchQueue.main.async { if !field.isEnabled && field.currentEditor() != nil { field.window?.makeFirstResponder(nil) } }
        }
        let marked = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !marked && field.stringValue != text { field.stringValue = text }
        field.font = .systemFont(ofSize: fontSize, weight: weight); field.textColor = color; field.alignment = alignment; field.setAccessibilityLabel(label)
        applyTypography(field)
        if !focusRequest { context.coordinator.requested = false }
        if isEnabled && focusRequest && !context.coordinator.requested {
            context.coordinator.requested = true
            DispatchQueue.main.async { guard field.isEnabled else { return }; field.window?.makeFirstResponder(field); field.selectText(nil) }
        }
    }
    private func applyTypography(_ field: NSTextField) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: paragraph]
        if let editor = field.currentEditor() as? NSTextView {
            guard !editor.hasMarkedText() else { return }
            editor.typingAttributes = attributes
            editor.textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
        } else {
            field.attributedStringValue = NSAttributedString(string: field.stringValue, attributes: attributes)
        }
        var placeholderAttributes = attributes; placeholderAttributes[.foregroundColor] = placeholderColor
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeField
        var requested = false
        var focusObserver: NSObjectProtocol?
        init(_ parent: NativeField) { self.parent = parent }
        deinit { if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) } }
        func installFocusRequest(for field: NSTextField) {
            focusObserver = NotificationCenter.default.addObserver(forName: .focusRequest, object: nil, queue: .main) { [weak self, weak field] note in
                guard let self, let field, field.isEnabled, let id = self.parent.focusID, note.object as? String == id else { return }
                field.window?.makeFirstResponder(field); field.selectText(nil)
            }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField, let editor = field.currentEditor() as? NSTextView {
                let dark = (parent.color.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.8
                editor.insertionPointColor = dark ? .white : NSColor(Color(hex: 0x0c874d))
                editor.selectedTextAttributes = [.backgroundColor: dark ? NSColor.white : NSColor(Color(hex: 0xb9d8bf)), .foregroundColor: dark ? NSColor.black : NSColor(Color(hex: 0x143b25))]
            }
            FocusRouting.activate(parent.focusID ?? "field")
            parent.onFocus(true)
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            let value = String(field.stringValue.prefix(parent.limit))
            if value != field.stringValue { field.stringValue = value }
            parent.text = value; parent.onValue(value)
        }
        func controlTextDidEndEditing(_ notification: Notification) { FocusRouting.deactivate(parent.focusID ?? "field"); parent.onFocus(false); parent.onEnd() }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if parent.numericStepper && (commandSelector == #selector(NSResponder.moveUp(_:)) || commandSelector == #selector(NSResponder.moveDown(_:))) {
                let delta = commandSelector == #selector(NSResponder.moveUp(_:)) ? 1 : -1
                let value = String(min(120, max(1, (Int(textView.string).map { $0 + delta } ?? 1))))
                textView.string = value; control.stringValue = value; parent.text = value; parent.onValue(value)
                textView.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { control.window?.makeFirstResponder(nil); return true }
            return false
        }
    }
}

struct LiquidBackground: View, Animatable {
    var progress: Double
    var fill: Color
    var stroke: Color? = nil
    var reduced = false
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                if let image=LiquidRaster.image(width:geometry.size.width,progress:progress,fill:fill,stroke:stroke,filtered:!reduced) {
                    context.draw(Image(decorative:image,scale:2),in:CGRect(x:0,y:0,width:geometry.size.width+40,height:64))
                }
            }.frame(width:geometry.size.width+40,height:64).offset(x:-20,y:-10)
        }.frame(height:44).allowsHitTesting(false)
    }
}
struct TimerControls: View, Animatable {
    @ObservedObject var store: PomodoroStore
    var palette: Palette
    var separation: Double
    @StateObject private var colors = ControlColorMotion()
    var animatableData: Double { get { separation } set { separation = newValue } }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, p = min(1, max(0, separation)), mainWidth = width - 54 * CGFloat(p)
            ZStack(alignment: .topLeading) {
                LiquidBackground(progress: p, fill: colors.color("fill", fallback: palette.controlFill(running: store.running)), stroke: colors.color("stroke", fallback: store.dark && store.running ? Color(hex:0x3a3a3a) : .clear), reduced:store.reduceMotion).frame(width: width, height: 44, alignment: .top)
                Button { store.toggle() } label: {
                    HStack(spacing: 8) { Glyph(name: store.running ? "pause" : "play", size: 14); Text(store.controlTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) }
                        .foregroundStyle(colors.color("ink", fallback: palette.controlInk(running: store.running))).frame(width: mainWidth, height: 44).contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).focusTarget("start").accessibilityLabel(store.controlTitle)
                Button { store.reset() } label: {
                    Glyph(name: "reset", size: 17).offset(x: -22 * (1 - p)).foregroundStyle(colors.color("ink", fallback: palette.controlInk(running: store.running))).frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.plain).focusTarget("reset").offset(x: width - 44).opacity(max(0, min(1, (p - 0.65) / 0.35))).allowsHitTesting(store.roundStarted && p > 0.82).disabled(!store.roundStarted || p <= 0.82).accessibilityHidden(!store.roundStarted || p <= 0.82).accessibilityLabel(store.text("重置当前计时"))
            }
        }.frame(height: 44)
            .onAppear { updateColors(instant: true) }
            .onChange(of: store.running) { _, _ in updateColors() }
            .onChange(of: store.dark) { _, _ in updateColors() }
            .onChange(of: store.reduceMotion) { _, _ in updateColors(instant: true) }
            .onChange(of: store.windowVisible) { _, visible in if !visible { updateColors(instant: true) } }
    }
    private func updateColors(instant: Bool = false) {
        colors.update(palette: palette, running: store.running, instant: instant || store.reduceMotion || !store.windowVisible)
    }
}
struct CircleReveal: Shape {
    var progress: Double
    var origin: CGPoint
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        let distance = [CGPoint.zero, CGPoint(x: rect.width, y: 0), CGPoint(x: 0, y: rect.height), CGPoint(x: rect.width, y: rect.height)].map { hypot($0.x - origin.x, $0.y - origin.y) }.max()!
        let radius = ceil(distance) + 20
        let r = radius * CGFloat(min(1, max(0, progress)))
        return Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
    }
}
struct MenuReveal: Shape {
    var progress: Double
    var above: Bool
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        let height = rect.height * CGFloat(0.3 + 0.7 * progress)
        return Path(roundedRect: CGRect(x: 0, y: above ? rect.height - height : 0, width: rect.width, height: height), cornerRadius: 14)
    }
}
extension Notification.Name { static let focusKeyboard = Notification.Name("FocusKeyboard") }
