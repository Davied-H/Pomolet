import Foundation
import Combine
import SwiftUI

/// CSS timing functions, sampled from presentation values when a transition reverses.
enum WebEase: Equatable {
    case linear
    case cubic(Double, Double, Double, Double)
    static let arrive = WebEase.cubic(0.16, 1, 0.3, 1)
    static let depart = WebEase.cubic(0.4, 0, 1, 1)
    static let easeIn = WebEase.cubic(0.42, 0, 1, 1)
    static let settingsClose = WebEase.cubic(0.55, 0, 0.85, 0.4)
    func value(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        guard case let .cubic(x1, y1, x2, y2) = self else { return x }
        if x == 0 || x == 1 { return x }
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double { let r = 1 - t; return 3 * r * r * t * a + 3 * r * t * t * b + t * t * t }
        var low = 0.0, high = 1.0
        for _ in 0..<30 { let t = (low + high) / 2; if bezier(t, x1, x2) < x { low = t } else { high = t } }
        return bezier((low + high) / 2, y1, y2)
    }
}
struct MotionChannel {
    var from: Double
    var to: Double
    var start: TimeInterval
    var duration: TimeInterval
    var ease: WebEase
    func value(at time: TimeInterval) -> Double {
        guard time > start else { return from }
        guard duration > 0, time < start + duration else { return to }
        return from + (to - from) * ease.value((time - start) / duration)
    }
}
@MainActor final class MotionTimeline: ObservableObject {
    @Published private(set) var sampleTime: TimeInterval
    private var channels: [String: MotionChannel] = [:]
    private var ticker: Timer?
    private let clock: () -> TimeInterval
    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.clock = clock; sampleTime = clock() }
    func value(_ key: String, fallback: Double = 0) -> Double { channels[key]?.value(at: sampleTime) ?? fallback }
    func set(_ key: String, _ value: Double) { channels[key] = MotionChannel(from: value, to: value, start: clock(), duration: 0, ease: .linear); sampleTime = clock() }
    func animate(_ key: String, to: Double, from: Double? = nil, duration: Double, delay: Double = 0, ease: WebEase = .arrive, fallback: Double = 0) {
        let time = clock(), initial = from ?? channels[key]?.value(at: time) ?? fallback
        channels[key] = MotionChannel(from: initial, to: to, start: time + delay, duration: duration, ease: ease)
        sampleTime = time; startTicker()
    }
    func freeze() {
        let time = clock()
        for (key, channel) in channels { let value = channel.value(at: time); channels[key] = MotionChannel(from: value, to: value, start: time, duration: 0, ease: .linear) }
        ticker?.invalidate(); ticker = nil; sampleTime = time
    }
    func sample(at time: TimeInterval) { sampleTime = time }
    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }; let time = self.clock(); self.sampleTime = time
                if self.channels.values.allSatisfy({ time >= $0.start + $0.duration }) { self.ticker?.invalidate(); self.ticker = nil }
            }
        }
        ticker = timer; RunLoop.main.add(timer, forMode: .common)
    }
}
@MainActor final class NavigationMotion: ObservableObject {
    let timeline: MotionTimeline
    private let scheduler: (Double, @escaping () -> Void) -> Void
    @Published private(set) var statisticsMounted = false
    @Published private(set) var settingsMounted = false
    @Published private(set) var homeVisible = true
    private var route: AppScreen = .focus
    private var revision = 0
    private var forwarding: AnyCancellable?
    private var homeParts = ["header", "character", "clock", "task", "controls", "footer"]
    static let statisticsParts = ["header", "card0", "card1", "card2", "card3", "historyHeading", "history", "empty"]
    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, scheduler: @escaping (Double, @escaping () -> Void) -> Void = { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() } }) {
        timeline = MotionTimeline(clock: clock); self.scheduler = scheduler
        timeline.set("home.opacity", 1); timeline.set("statistics.opacity", 0); timeline.set("settings.reveal", 0)
        forwarding = timeline.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func update(to next: AppScreen, running: Bool, empty: Bool, reduced: Bool) {
        guard next != route || reduced || (next != .settings && settingsMounted) else { return }
        let previous = route; route = next; revision += 1; let token = revision
        homeParts = running ? ["character", "clock", "controls"] : ["header", "character", "clock", "task", "controls", "footer"]
        timeline.freeze()
        // A closing settings surface remains mounted until its reveal finishes.
        // A second route must own that cleanup, even if the logical route is already focus.
        if next == .settings || previous == .settings || settingsMounted {
            let opening = next == .settings, wasHidden = !settingsMounted, homeWasHidden = !homeVisible
            settingsMounted = true; homeVisible = true
            if next == .settings && previous == .statistics { timeline.animate("statistics.opacity", to: 0, duration: 0.16) }
            if reduced {
                timeline.set("settings.reveal", opening ? 1 : 0); timeline.set("home.opacity", opening ? 0 : 1)
                for i in 0..<3 { timeline.set("settings.part.\(i).opacity", opening ? 1 : 0); timeline.set("settings.part.\(i).y", 0) }
            } else {
                timeline.animate("settings.reveal", to: opening ? 1 : 0, from: wasHidden ? 0 : nil, duration: opening ? 0.5 : 0.28, ease: opening ? .arrive : .settingsClose)
                timeline.animate("home.opacity", to: opening ? 0 : 1, from: homeWasHidden ? 0 : nil, duration: opening ? 0.16 : 0.22, delay: opening ? 0 : 0.06, fallback: 1)
                for i in 0..<3 {
                    let delay = opening ? 0.075 + min(Double(i) * 0.022, 0.13) : max(0, 0.04 - Double(i) * 0.006)
                    timeline.animate("settings.part.\(i).opacity", to: opening ? 1 : 0, from: wasHidden ? 0 : nil, duration: opening ? 0.3 : 0.16, delay: delay, ease: opening ? .arrive : .easeIn, fallback: 1)
                    timeline.animate("settings.part.\(i).y", to: opening ? 0 : -3, from: wasHidden ? -4 : nil, duration: opening ? 0.3 : 0.16, delay: delay, ease: opening ? .arrive : .easeIn)
                }
            }
            finish(after: reduced ? 0 : opening ? 0.5 : 0.28, token: token) {
                self.settingsMounted = opening; self.homeVisible = !opening; self.statisticsMounted = false
                if !opening { self.timeline.set("settings.reveal", 0) }
                for part in self.homeParts { self.timeline.set("home.part." + part + ".x", 0); self.timeline.set("home.part." + part + ".opacity", 1) }
                if !opening && next == .statistics { self.route = .focus; self.update(to: .statistics, running: running, empty: empty, reduced: reduced) }
            }
            return
        }
        let enteringStatistics = next == .statistics
        let incoming = enteringStatistics ? "statistics" : "home", outgoing = enteringStatistics ? "home" : "statistics"
        let incomingWasVisible = enteringStatistics ? statisticsMounted : homeVisible
        statisticsMounted = true; homeVisible = true
        let statisticsParts = empty ? Self.statisticsParts : Array(Self.statisticsParts.dropLast())
        let incomingParts = enteringStatistics ? statisticsParts : homeParts, outgoingParts = enteringStatistics ? homeParts : statisticsParts
        let direction = enteringStatistics ? 1.0 : -1.0, arrival = incomingWasVisible ? 0.0 : 0.11
        if reduced {
            timeline.set(incoming + ".opacity", 1); timeline.set(outgoing + ".opacity", 0)
            for part in incomingParts { timeline.set(incoming + ".part." + part + ".opacity", 1); timeline.set(incoming + ".part." + part + ".x", 0) }
        } else {
            timeline.animate(outgoing + ".opacity", to: 0, duration: 0.16, ease: .depart, fallback: 1)
            timeline.animate(incoming + ".opacity", to: 1, from: incomingWasVisible ? nil : 0, duration: 0.19, delay: arrival)
            for part in outgoingParts { timeline.animate(outgoing + ".part." + part + ".x", to: -direction * 5, duration: 0.16, ease: .depart) }
            for (i, part) in incomingParts.enumerated() {
                let delay = incomingWasVisible ? 0 : arrival + min(Double(i) * 0.02, 0.06)
                timeline.animate(incoming + ".part." + part + ".opacity", to: 1, from: incomingWasVisible ? nil : 0, duration: 0.25, delay: delay, fallback: 1)
                timeline.animate(incoming + ".part." + part + ".x", to: 0, from: incomingWasVisible ? nil : direction * (i == 0 ? 4 : 7), duration: 0.25, delay: delay)
            }
            timeline.animate("chartGlyph.opacity", to: 1, from: 0.3, duration: 0.22)
            timeline.animate("chartGlyph.scale", to: 1, from: 0.92, duration: 0.22, fallback: 1)
        }
        let duration = reduced ? 0 : max(0.25 + arrival + (incomingWasVisible ? 0 : min(Double(max(0, incomingParts.count - 1)) * 0.02, 0.06)), 0.22)
        finish(after: duration, token: token) {
            self.statisticsMounted = enteringStatistics; self.homeVisible = !enteringStatistics
            for part in outgoingParts { self.timeline.set(outgoing + ".part." + part + ".x", 0); self.timeline.set(outgoing + ".part." + part + ".opacity", 1) }
        }
    }
    private func finish(after delay: Double, token: Int, action: @escaping () -> Void) {
        if delay == 0 { if token == revision { action() }; return }
        scheduler(delay) { if token == self.revision { action() } }
    }
}
struct PagePartMotion: ViewModifier {
    @ObservedObject var timeline: MotionTimeline
    var namespace: String
    var part: String
    var axis: String = "x"
    func body(content: Content) -> some View {
        let prefix = namespace + ".part." + part
        content.opacity(timeline.value(prefix + ".opacity", fallback: 1))
            .offset(x: axis == "x" ? timeline.value(prefix + ".x") : 0, y: axis == "y" ? timeline.value(prefix + ".y") : 0)
    }
}

enum WebChartProgress {
    static func value(elapsed: TimeInterval, index: Int) -> Double {
        let raw = min(1, max(0, (elapsed - 0.13 - Double(index) * 0.045) / 0.58))
        return 1 - pow(1 - raw, 3)
    }
}

@MainActor final class LiquidSpring: ObservableObject {
    @Published private(set) var position = 0.0
    private(set) var velocity = 0.0
    private(set) var target = 0.0
    private var last = 0.0
    private var timer: Timer?
    private let automatic: Bool
    private let clock: () -> Double
    init(initial: Double = 0, automatic: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.automatic = automatic; self.clock = clock
        position = initial; target = initial
    }
    func setTarget(_ value: Double, instant: Bool = false) {
        if instant { target=value;position=value;velocity=0;timer?.invalidate();timer=nil;return }
        guard value != target else { return };target=value
        if timer == nil {
            last=clock()
            guard automatic else { return }
            let timer=Timer(timeInterval:1.0/120,repeats:true) { [weak self] _ in Task { @MainActor in self?.step(at:ProcessInfo.processInfo.systemUptime) } }
            self.timer=timer;RunLoop.main.add(timer,forMode:.common)
        }
    }
    func step(at time:Double) {
        let dt=min(0.032,max(0.001,time-last));last=time
        let steps=Int(ceil(dt/0.008)),h=dt/Double(steps),omega=target>0 ? 14.5 : 19.0
        for _ in 0..<steps { velocity += (omega*omega*(target-position)-2*omega*velocity)*h;position += velocity*h }
        if abs(target-position)<0.0008 && abs(velocity)<0.015 { position=target;velocity=0;timer?.invalidate();timer=nil }
    }
}
