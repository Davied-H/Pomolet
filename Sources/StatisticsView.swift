import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: PomodoroStore
    @ObservedObject var timeline: MotionTimeline
    private var palette: Palette { Palette(dark: store.dark) }
    private var data: StatisticsData { store.statistics }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                QuietIconButton(name: "back", label: "返回番茄钟", palette: palette, size: 28, focusID: "statisticsBack") { store.navigate(.focus) }
                Text("数据统计").font(.system(size: 15, weight: .semibold)); Spacer()
            }.padding(.horizontal, 22).frame(height: 48).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "header"))
            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        StatisticCard(title: "今日专注", value: Double(data.today.minutes), unit: "分钟", caption: "近 7 天 · 专注时长", values: data.days.map { Double($0.minutes) }, bar: false, index: 0, palette: palette, active: store.screen == .statistics, reduced: store.reduceMotion).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "card0"))
                        StatisticCard(title: "完成番茄", value: Double(data.today.count), unit: "次", caption: "近 7 天 · 完成次数", values: data.days.map { Double($0.count) }, bar: true, index: 1, palette: palette, active: store.screen == .statistics, reduced: store.reduceMotion).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "card1"))
                        StatisticCard(title: "平均时长", value: data.today.average, unit: "分钟", caption: "近 7 天 · 单次平均", values: data.days.map { $0.average }, bar: false, index: 2, palette: palette, active: store.screen == .statistics, reduced: store.reduceMotion).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "card2"))
                        StatisticCard(title: "本周累计", value: Double(data.weekMinutes), unit: "分钟", caption: "周一至今 · 累计时长", values: data.week, bar: false, index: 3, palette: palette, active: store.screen == .statistics, reduced: store.reduceMotion).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "card3"))
                    }
                    VStack(spacing: 0) {
                    HStack { Text("今日记录").font(CSSFont.font(11, weight: 550)); Spacer(); Text("\(store.todayRecords.count) 条").font(.system(size: 9)).foregroundStyle(palette.sub) }.padding(.top, 19).padding(.bottom, 7)
                    Rectangle().fill(palette.line).frame(height: 1)
                    }.modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "historyHeading"))
                    VStack(spacing: 0) {
                    ForEach(store.todayRecords) { record in
                        HStack(spacing: 12) {
                            Text(record.endedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN"))).font(.system(size: 10)).foregroundStyle(palette.sub).monospacedDigit().fixedSize()
                            Text(record.task.isEmpty ? "专注当下" : record.task).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(record.minutes) 分钟").font(.system(size: 11)).foregroundStyle(palette.sub).fixedSize()
                        }.padding(.vertical, 13)
                        Rectangle().fill(palette.line).frame(height: 1)
                    }
                    }.modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "history"))
                    if store.todayRecords.isEmpty {
                        VStack(spacing: 0) {
                            Glyph(name: "leaf", size: 22).padding(.bottom, 6)
                            Text("今天的第一份专注，从现在开始。").font(.system(size: 11)).frame(minHeight: 22)
                            Button { store.navigate(.focus) } label: { Text("开始一次专注").font(.system(size: 11)).frame(height: 22).padding(.horizontal, 14).padding(.vertical, 8).foregroundStyle(palette.accent).background(palette.wash, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.top, 8).focusTarget("backFocus")
                        }.foregroundStyle(palette.sub).frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 8).modifier(PagePartMotion(timeline: timeline, namespace: "statistics", part: "empty"))
                    }
                }.padding(.horizontal, 26).padding(.top, 10).padding(.bottom, 22)
            }.scrollIndicators(.automatic)
        }.foregroundStyle(palette.ink)
    }
}
struct StatisticCard: View {
    var title: String
    var value: Double
    var unit: String
    var caption: String
    var values: [Double?]
    var bar: Bool
    var index: Int
    var palette: Palette
    var active: Bool
    var reduced: Bool
    @State private var chartEpoch = 0.0
    @State private var animating = false
    @State private var heldProgress = 1.0
    @State private var chartRevision = 0
    private var number: String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.sub).frame(height: 14, alignment: .leading).padding(.bottom, 6)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(number).font(CSSFont.font(28, weight: 650, rounded: true)).tracking(-1.12).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Text(unit).font(.system(size: 9)).foregroundStyle(palette.sub)
            }.frame(height: 32.2, alignment: .leading)
            TimelineView(.animation(minimumInterval: 1.0 / 120, paused: !animating)) { _ in
                MiniChart(values: values, bar: bar, progress: animating ? WebChartProgress.value(elapsed: ProcessInfo.processInfo.systemUptime - chartEpoch, index: index) : heldProgress, palette: palette)
            }.frame(height: 32).padding(.top, 8)
            Text(caption).font(.system(size: 8)).foregroundStyle(palette.sub).lineLimit(1).frame(height: 12, alignment: .leading).padding(.top, 4)
        }.padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 10).padding(1).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.side, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.line, lineWidth: 1))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(number)\(unit)。\(caption)：" + values.map { $0.map { String(format: "%.1f", $0) } ?? "尚未到来" }.joined(separator: "，"))
            .onAppear { startChart() }
            .onChange(of: active) { _, visible in if visible { startChart() } else { stopChart(complete: false) } }
            .onChange(of: values) { _, _ in startChart() }
            .onChange(of: palette.dark) { _, _ in stopChart(complete: true) }
            .onChange(of: reduced) { _, _ in stopChart(complete: true) }
            .onDisappear { stopChart(complete: false) }
    }
    private func startChart() {
        chartRevision += 1; let token = chartRevision
        guard active && !reduced else { heldProgress = 1; animating = false; return }
        chartEpoch = ProcessInfo.processInfo.systemUptime; heldProgress = 0; animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13 + Double(index) * 0.045 + 0.58) {
            if token == chartRevision { heldProgress = 1; animating = false }
        }
    }
    private func stopChart(complete: Bool) {
        if complete { heldProgress = 1 }
        else if animating { heldProgress = WebChartProgress.value(elapsed: ProcessInfo.processInfo.systemUptime - chartEpoch, index: index) }
        chartRevision += 1; animating = false
    }
}
struct MiniChart: View, Animatable {
    var values: [Double?]
    var bar: Bool
    var progress: Double
    var palette: Palette
    var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        Canvas { context, size in
            let left = 2.0, right = Double(size.width) - 2, top = 3.0, bottom = Double(size.height) - 3
            var baseline = Path(); baseline.move(to: CGPoint(x: left, y: bottom)); baseline.addLine(to: CGPoint(x: right, y: bottom))
            context.stroke(baseline, with: .color(palette.line), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            let maximum = values.compactMap { $0 }.max() ?? 0
            guard maximum > 0 else { context.draw(Text("暂无记录").font(.system(size: 9)).foregroundColor(palette.sub), at: CGPoint(x: size.width / 2, y: size.height / 2)); return }
            context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * CGFloat(min(1, max(0, progress))), height: size.height)))
            if bar {
                let step = (right - left) / Double(values.count), width = max(3, min(10, step * 0.48))
                for (index, value) in values.enumerated() {
                    guard let value, value > 0 else { continue }
                    let h = value / maximum * (bottom - top), x = left + step * (Double(index) + 0.5) - width / 2
                    context.fill(Path(roundedRect: CGRect(x: x, y: bottom - h, width: width, height: h), cornerRadius: min(2, h / 2)), with: .color(palette.accent))
                }
            } else {
                let points = values.enumerated().compactMap { index, value -> CGPoint? in guard let value else { return nil }; return CGPoint(x: left + Double(index) * (right - left) / Double(max(1, values.count - 1)), y: bottom - value / maximum * (bottom - top)) }
                guard let first = points.first, let last = points.last else { return }
                var line = Path(); line.move(to: first); points.dropFirst().forEach { line.addLine(to: $0) }
                var area = line; area.addLine(to: CGPoint(x: Double(last.x), y: bottom)); area.addLine(to: CGPoint(x: Double(first.x), y: bottom)); area.closeSubpath()
                context.fill(area, with: .color(palette.accent.opacity(0.09)))
                context.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)), with: .color(palette.accent))
            }
        }.accessibilityHidden(true)
    }
}
