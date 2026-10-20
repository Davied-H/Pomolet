import AppKit
import SwiftUI
import AVFoundation
import CoreImage

@MainActor enum Resources {
    static func url(_ name: String, folder: String? = nil, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: ["Resources", folder].compactMap { $0 }.joined(separator: "/"))
        #else
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder)
        #endif
    }
    static let poster: NSImage = { NSImage(contentsOf: url("poster", ext: "png")!)! }()
    static let darkPoster: NSImage = { NSImage(contentsOf: url("poster-dark", ext: "png")!)! }()
    private static var iconCache: [String: NSImage] = [:]
    static func icon(_ name: String) -> NSImage {
        if let image = iconCache[name] { return image }
        let image = url(name, folder: "Icons", ext: "pdf").flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 24, height: 24)); iconCache[name] = image; return image
    }
}

@MainActor final class CharacterPlayer: ObservableObject {
    @Published private(set) var clip = "idle"
    @Published private(set) var ready = false
    @Published private(set) var seeking = false
    @Published private(set) var displayReady: Set<String> = []
    private(set) var players: [String: AVPlayer] = [:]
    private var observers: [NSObjectProtocol] = []
    private var readiness: [NSKeyValueObservation] = []
    private var kind: ModeKind = .focus
    private var permitted = false
    private var dark = false
    private var idleLeft = 3
    private var lastActions: [ModeKind: String] = [:]
    private var playbackGeneration = 0
    init() {
        for key in ["idle", "focus-adjust", "short", "short-eyes", "long", "long-yawn"] {
            guard let url = Resources.url(key, folder: "Videos", ext: "mov") else { continue }
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true; player.actionAtItemEnd = .pause; player.automaticallyWaitsToMinimizeStalling = true
            players[key] = player
            readiness.append(item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in guard let self, self.clip == key else { return }; self.ready = item.status == .readyToPlay }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.advance(ended: key) }
            })
        }
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        players.values.forEach { $0.pause() }
    }
    func synchronize(kind: ModeKind, playing: Bool, dark: Bool, reset: Bool = false) {
        if self.dark != dark { self.dark = dark; applyAppearance() }
        if self.kind != kind || reset {
            self.kind = kind; playbackGeneration += 1
            players.values.forEach { $0.pause() }
            clip = "idle"; idleLeft = kind == .focus ? Int.random(in: 2...4) : Int.random(in: 1...2)
            lastActions = [:]
            seekAndPlay(playing)
        }
        permitted = playing
        players.forEach { key, player in if key != clip || !playing { player.pause() } }
        guard let active = players[clip] else { ready = false; return }
        ready = active.currentItem?.status == .readyToPlay
        if playing {
            if active.currentItem?.duration.isNumeric == true, active.currentTime() >= active.currentItem!.duration { advance(ended: clip) }
            else { active.playImmediately(atRate: 1) }
        }
    }
    func setDisplayReady(_ key: String, ready: Bool) {
        if ready && !displayReady.contains(key) { displayReady.insert(key) }
        else if !ready && displayReady.contains(key) { displayReady.remove(key) }
    }
    private func applyAppearance() {
        for player in players.values {
            guard let item = player.currentItem else { continue }
            if !dark { item.videoComposition = nil; continue }
            item.videoComposition = CSSVideoAppearance.composition(for: item.asset)
        }
    }
    private func seekAndPlay(_ play: Bool) {
        let generation = playbackGeneration
        seeking = true
        guard let player = players[clip] else { ready = false; seeking = false; return }
        ready = player.currentItem?.status == .readyToPlay
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] done in
            Task { @MainActor in guard let self, generation == self.playbackGeneration else { return }; self.seeking = false; guard done else { return }; if play && self.permitted { player?.playImmediately(atRate: 1) } }
        }
    }
    private func advance(ended: String) {
        guard ended == clip, permitted else { return }
        playbackGeneration += 1
        players[clip]?.pause()
        if clip == "idle" {
            idleLeft -= 1
            if idleLeft <= 0 {
                let available = kind.actions.filter { players[$0]?.currentItem?.status == .readyToPlay }
                let fresh = available.filter { $0 != lastActions[kind] }
                if let next = (fresh.isEmpty ? available : fresh).randomElement() { clip = next; lastActions[kind] = next }
                else { clip = "idle"; idleLeft = 1 }
            }
        } else { clip = "idle"; idleLeft = kind == .focus ? Int.random(in: 2...4) : Int.random(in: 1...2) }
        seekAndPlay(true)
    }
}

/// CSS grayscale(1) invert(1) contrast(1.18), evaluated in nonlinear sRGB.
enum CSSVideoAppearance {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    static func image(_ source: CIImage) -> CIImage {
        let weights = CIVector(x: -0.250868, y: -0.843936, z: -0.085196, w: 0)
        return source.applyingFilter("CIColorMatrix", parameters: ["inputRVector": weights, "inputGVector": weights, "inputBVector": weights, "inputAVector": CIVector(x: 0,y: 0,z: 0,w: 1), "inputBiasVector": CIVector(x: 1.09,y: 1.09,z: 1.09,w: 0)])
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0,y: 0,z: 0,w: 0), "inputMaxComponents": CIVector(x: 1,y: 1,z: 1,w: 1)])
    }
    static func composition(for asset: AVAsset) -> AVVideoComposition {
        AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in request.finish(with: image(request.sourceImage), context: context) })
    }
}

final class TransparentVideoView: NSView {
    let playerLayer = AVPlayerLayer()
    var readyCallback: ((Bool) -> Void)?
    private var displayObservation: NSKeyValueObservation?
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect; playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false; layer?.addSublayer(playerLayer)
        displayObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            DispatchQueue.main.async { self?.readyCallback?(layer.isReadyForDisplay) }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); playerLayer.frame = bounds; CATransaction.commit() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
struct PlayerSurface: NSViewRepresentable {
    var player: AVPlayer
    var onDisplay: (Bool) -> Void
    func makeNSView(context: Context) -> TransparentVideoView { let view = TransparentVideoView(); view.readyCallback = onDisplay; view.playerLayer.player = player; return view }
    func updateNSView(_ view: TransparentVideoView, context: Context) { view.readyCallback = onDisplay; if view.playerLayer.player !== player { view.playerLayer.player = player } }
}
struct CharacterView: View {
    @ObservedObject var media: CharacterPlayer
    var dark: Bool
    var reduced: Bool
    var body: some View {
        ZStack {
            Image(nsImage: dark ? Resources.darkPoster : Resources.poster).resizable().aspectRatio(contentMode: .fit)
                .opacity(media.ready && media.displayReady.contains(media.clip) && !media.seeking && !reduced ? 0 : 1)
            ForEach(Array(media.players.keys).sorted(), id: \.self) { key in
                if let player = media.players[key] { PlayerSurface(player: player, onDisplay: { ready in media.setDisplayReady(key, ready: ready) }).opacity(key == media.clip && media.ready && !media.seeking && !reduced ? 1 : 0) }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
extension View {
    @ViewBuilder func colorInvertIf(_ flag: Bool) -> some View { if flag { self.colorInvert() } else { self } }
}

@MainActor final class CompletionChime {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    func play() {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        let rate = 44100.0, duration = 1.56
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * duration)), let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        for sample in 0..<Int(buffer.frameLength) {
            let time = Double(sample) / rate
            var value = 0.0
            for (index, frequency) in [523.25, 659.25, 783.99].enumerated() {
                let t = time - Double(index) * 0.18
                if t >= 0 && t <= 1.2 { value += sin(2 * .pi * frequency * t) * CompletionEnvelope.gain(at: t) }
            }
            channel[sample] = Float(value)
        }
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start(); player.scheduleBuffer(buffer); player.play(); self.engine = engine; self.node = player
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak engine] in if self?.engine === engine { self?.engine?.stop(); self?.engine = nil; self?.node = nil } }
        } catch { NSSound(named: "Glass")?.play() }
    }
}
