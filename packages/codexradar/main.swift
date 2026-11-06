// Codex Radar — 桌面小组件：展示 codexradar.com「雷达分 · 雷达Bench」实时分数 + 社区口碑评分
import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Config

struct WatchItem: Codable, Hashable {
    var model: String
    var effort: String
    var key: String { "\(model)|\(effort)" }
}

struct Config: Codable {
    var version: Int?
    var watch: [WatchItem]
    var refreshMinutes: Double?
    var ratingWindow: String?      // "24h" | "7d"
    var floatOnTop: Bool?
    /// 隐藏的显示项：src.deepswe / src.pompeii / src.tb4 / src.science / cost / coverage / runs / rating / spark / delta
    var hidden: [String]?
    var appearance: String?        // "system" | "light" | "dark"
    var backgroundOpacity: Double? // 旧版字段，仅用于迁移
    var background: String?        // solid | frosted | light | translucent | glass

    /// 背景预设：毛玻璃不透明度 + 叠加底色浓度
    var backgroundPreset: (blur: Double, tint: Double, key: String) {
        let k = background ?? {
            let o = backgroundOpacity ?? 0.6
            return o > 0.8 ? "solid" : (o < 0.4 ? "light" : "frosted")
        }()
        switch k {
        case "solid": return (1, 0.92, k)
        case "light": return (1, 0.25, k)
        case "translucent": return (0.5, 0.3, k)
        case "glass": return (0, 0.16, k)
        default: return (1, 0.6, "frosted")
        }
    }
    var fontScale: Double?         // 字号缩放，1 = 标准
    var language: String?          // "en"（默认）| "zh"
    var pinned: Bool?              // 固定：禁止拖动和拉伸

    func shows(_ k: String) -> Bool { !(hidden ?? []).contains(k) }

    static let currentVersion = 2
    static let `default` = Config(
        version: currentVersion,
        watch: [
            .init(model: "gpt-6.1-sol", effort: "high"),
            .init(model: "gpt-6.1-sol", effort: "xhigh"),
            .init(model: "gpt-6-astra", effort: "high"),
            .init(model: "gpt-6-astra", effort: "xhigh"),
            .init(model: "gpt-6-sol", effort: "high"),
            .init(model: "gpt-5.6-sol", effort: "xhigh"),
        ],
        refreshMinutes: 30, ratingWindow: "24h", floatOnTop: false,
        hidden: [], appearance: "system", background: "frosted")
}

enum Paths {
    static let dir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = support.appendingPathComponent("CodexRadar", isDirectory: true)
        let legacy = support.appendingPathComponent("ModelRadar", isDirectory: true)   // 改名前的目录
        if !FileManager.default.fileExists(atPath: u.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: u)
        }
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let config = dir.appendingPathComponent("config.json")
    static let cacheBench = dir.appendingPathComponent("cache_radar_bench.json")
    static let cacheBinding = dir.appendingPathComponent("cache_binding.json")
    static let cacheRatings = dir.appendingPathComponent("cache_ratings.json")
}

// MARK: - Data models（与网站 radar-bench-display.mjs 读取的接口一致）

/// /data/radar-bench-binding.json —— 网站当前收录的 model/effort 范围
struct Binding: Codable {
    let benchmark: String?
    let total_tasks: Int?
    let model_efforts: [WatchItem]
}

struct BenchSource: Codable {
    let score: Double?
    let coverage: Int?
    let required_tasks: Int?
    let graded_runs_count: Int?
}

struct BenchMetric: Codable {
    let mean: Double?
    let known_total: Double?
    let known_samples: Int?
    /// 与网站一致：有缺失样本时 mean 为空，用已知样本求平均
    var value: Double? {
        if let mean { return mean }
        if let t = known_total, let n = known_samples, n > 0 { return t / Double(n) }
        return nil
    }
}

struct BenchStats: Codable {
    let sample_count: Int?
    let metrics: [String: BenchMetric]?
}

struct BenchHistPoint: Codable {
    let at: String
    let score: Double?
    let coverage: Int?
}

struct BenchHistory: Codable {
    let points: [BenchHistPoint]?
    let updated_bucket: String?
}

/// /api/radar-bench-score?model=…&effort=…&view=summary
struct BenchSummary: Codable {
    let model: String
    let effort: String
    let score: Double?
    let coverage: Int?
    let required_tasks: Int?
    let score_status: String?
    let graded_runs_count: Int?
    let source_scores: [String: BenchSource]?
    let statistics: BenchStats?
    let statistics_state: String?
    let history: BenchHistory?
}

struct RatingModel: Codable {
    let id: String
    let label: String?
    let average: Double?
    let count: Double?
}

struct Ratings: Codable {
    let updated_at: String?
    let window_hours: Double?
    let models: [RatingModel]
}

func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

let effortOrder = ["off", "low", "medium", "high", "xhigh", "max", "ultra"]
func effortRank(_ e: String) -> Int { effortOrder.firstIndex(of: e) ?? 99 }

/// 网站四个分项（顺序与网站一致）
/// 界面语言（默认英文）
enum Lang { static var en = true }
func L(_ zh: String, _ en: String) -> String { Lang.en ? en : zh }

/// 分项：key、短标签（组件内）、全称（菜单/提示）
var sourceLabels: [(String, String)] {
    [("deepswe", L("工程", "SWE")), ("pompeii", L("视觉", "Vis")), ("tb4", L("终端", "Term")), ("science", L("科研", "Sci"))]
}
func sourceFullName(_ key: String) -> String {
    switch key {
    case "deepswe": return L("工程 · 软件工程", "SWE · Software engineering")
    case "pompeii": return L("视觉 · 视觉空间推理", "Vis · Visual-spatial reasoning")
    case "tb4": return L("终端 · 终端与系统操作", "Term · Terminal & systems")
    case "science": return L("科研 · 科学研究", "Sci · Scientific research")
    default: return key
    }
}

func prettyModel(_ id: String) -> String {
    let upper: Set<String> = ["gpt", "glm", "k3", "hy4", "dsh"]
    var parts = id.split(separator: "-").map(String.init)
    parts = parts.map { upper.contains($0) ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
    if parts.count >= 2, upper.contains(parts[0].lowercased()), parts[1].first?.isNumber == true {
        parts[0] = parts[0] + "-" + parts[1]
        parts.remove(at: 1)
    }
    return parts.joined(separator: " ")
}

// MARK: - Row view-model

struct RowVM: Identifiable {
    let id: String
    let item: WatchItem
    let summary: BenchSummary?
    let failed: Bool
    let listed: Bool
    let rating: RatingModel?

    var series: [Double] {
        (summary?.history?.points ?? []).filter { ($0.coverage ?? 0) >= 10 }.compactMap(\.score)
    }
    /// 与上一个判分日相比的变化
    var delta: (Double, String)? {
        let pts = (summary?.history?.points ?? []).filter { $0.score != nil && ($0.coverage ?? 0) >= 10 }
        guard pts.count >= 2, let cur = summary?.score ?? pts.last?.score, let prev = pts[pts.count - 2].score,
              let d = parseDate(pts[pts.count - 2].at) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.month, .day], from: d)
        return (cur - prev, String(format: "%d/%d", c.month ?? 0, c.day ?? 0))
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var config: Config { didSet { Lang.en = config.language != "zh" } }
    @Published var binding: Binding?
    @Published var summaries: [String: BenchSummary] = [:]
    @Published var failedKeys: Set<String> = []
    @Published var ratings: Ratings?
    @Published var lastFetch: Date?
    @Published var errorText: String?
    @Published var loading = false

    private let base = "https://codexradar.com"

    init() {
        if let d = try? Data(contentsOf: Paths.config), let c = try? JSONDecoder().decode(Config.self, from: d),
           (c.version ?? 0) >= Config.currentVersion {
            config = c
        } else {
            config = .default   // 旧版配置（含网站未收录的模型）直接换成新默认值
        }
        saveConfig()
        if let d = try? Data(contentsOf: Paths.cacheBinding) { binding = try? JSONDecoder().decode(Binding.self, from: d) }
        if let d = try? Data(contentsOf: Paths.cacheBench) {
            summaries = (try? JSONDecoder().decode([String: BenchSummary].self, from: d)) ?? [:]
        }
        if let d = try? Data(contentsOf: Paths.cacheRatings) { ratings = try? JSONDecoder().decode(Ratings.self, from: d) }
        Lang.en = config.language != "zh"
    }

    var ratingWindow: String { config.ratingWindow ?? "24h" }
    var refreshMinutes: Double { max(5, config.refreshMinutes ?? 30) }

    func saveConfig() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(config) { try? d.write(to: Paths.config) }
    }

    func reloadConfig() {
        if let d = try? Data(contentsOf: Paths.config), let c = try? JSONDecoder().decode(Config.self, from: d) {
            config = c
            errorText = nil
        } else {
            errorText = L("config.json 解析失败", "Failed to parse config.json")
        }
    }

    func toggleHidden(_ k: String) {
        var h = config.hidden ?? []
        if let i = h.firstIndex(of: k) { h.remove(at: i) } else { h.append(k) }
        config.hidden = h
        saveConfig()
    }

    func isWatched(_ w: WatchItem) -> Bool { config.watch.contains(w) }

    func toggle(_ w: WatchItem) {
        if let i = config.watch.firstIndex(of: w) { config.watch.remove(at: i) } else { config.watch.append(w) }
        saveConfig()
        if summaries[w.key] == nil { Task { await refresh() } }
    }

    nonisolated private static func get(_ url: String, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CodexRadar/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (d, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw NSError(domain: "HTTP", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]) }
        return d
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var errors: [String] = []
        let base = self.base

        // 1) 收录范围
        do {
            let d = try await Self.get(base + "/data/radar-bench-binding.json")
            binding = try JSONDecoder().decode(Binding.self, from: d)
            try? JSONEncoder().encode(binding).write(to: Paths.cacheBinding)
        } catch {
            if binding == nil { errors.append(L("收录列表", "Catalog") + ": \(error.localizedDescription)") }
        }

        // 2) 每个关注的 model/effort 单独读取实时分数（网站也是这样逐个读取）
        let listed = Set((binding?.model_efforts ?? []).map(\.key))
        let targets = config.watch.filter { binding == nil || listed.contains($0.key) }
        let results: [(String, BenchSummary?)] = await withTaskGroup(of: (String, BenchSummary?).self) { g in
            for w in targets {
                g.addTask {
                    var q = URLComponents(string: base + "/api/radar-bench-score")!
                    q.queryItems = [.init(name: "model", value: w.model), .init(name: "effort", value: w.effort), .init(name: "view", value: "summary")]
                    guard let d = try? await Self.get(q.url!.absoluteString, headers: ["X-Radar-Bench-Selection": "user-selected-v1"]),
                          let s = try? JSONDecoder().decode(BenchSummary.self, from: d) else { return (w.key, nil) }
                    return (w.key, s)
                }
            }
            var out: [(String, BenchSummary?)] = []
            for await r in g { out.append(r) }
            return out
        }
        var failed = Set<String>()
        for (k, s) in results {
            if let s { summaries[k] = s } else { failed.insert(k) }
        }
        failedKeys = failed
        if !failed.isEmpty { errors.append(L("\(failed.count) 项读取失败，显示上次数据", "\(failed.count) failed to load; showing last data")) }
        try? JSONEncoder().encode(summaries).write(to: Paths.cacheBench)

        // 3) 社区口碑评分
        do {
            let d = try await Self.get(base + "/api/model-ratings?view=public&window=\(ratingWindow)")
            ratings = try JSONDecoder().decode(Ratings.self, from: d)
            try? d.write(to: Paths.cacheRatings)
        } catch {
            errors.append(L("口碑", "Ratings") + ": \(error.localizedDescription)")
        }

        lastFetch = Date()
        errorText = errors.isEmpty ? nil : errors.joined(separator: "；")
    }

    var rows: [RowVM] {
        let listed = Set((binding?.model_efforts ?? []).map(\.key))
        return config.watch.map { w in
            RowVM(id: w.key, item: w, summary: summaries[w.key], failed: failedKeys.contains(w.key),
                  listed: binding == nil || listed.contains(w.key),
                  rating: ratings?.models.first { $0.id == "\(w.model)-\(w.effort)" })
        }
    }

    /// 可选的 (模型 -> [effort])，来自网站收录范围，保持网站的模型顺序
    var catalog: [(String, [String])] {
        var order: [String] = []
        var m: [String: Set<String>] = [:]
        for w in (binding?.model_efforts ?? []) + config.watch {
            if m[w.model] == nil { order.append(w.model) }
            m[w.model, default: []].insert(w.effort)
        }
        return order.map { ($0, m[$0]!.sorted { effortRank($0) > effortRank($1) }) }
    }

    var latestBucket: Date? {
        summaries.values.compactMap { parseDate($0.history?.updated_bucket) }.max()
    }
}

// MARK: - Views

private struct ScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    /// 字号缩放（与窗口大小无关）
    var uiScale: CGFloat {
        get { self[ScaleKey.self] }
        set { self[ScaleKey.self] = newValue }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 浅色/深色模式各一套、饱和度克制的颜色
func dynamicColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { ap in
        let hex = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                       blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    })
}

/// 每个分项固定一种颜色，所有行统一
let sourceColors: [String: Color] = [
    "deepswe": dynamicColor(0x3D6AA8, 0x8FB0DD),  // 工程
    "pompeii": dynamicColor(0x7357A0, 0xB5A0D8),  // 视觉
    "tb4":     dynamicColor(0x2C7770, 0x7FC2B9),  // 终端
    "science": dynamicColor(0x9A6327, 0xD8AC78),  // 科研
]
let sourceNSColors: [String: NSColor] = [
    "deepswe": NSColor(srgbRed: 0.36, green: 0.53, blue: 0.76, alpha: 1),
    "pompeii": NSColor(srgbRed: 0.56, green: 0.46, blue: 0.75, alpha: 1),
    "tb4":     NSColor(srgbRed: 0.30, green: 0.60, blue: 0.56, alpha: 1),
    "science": NSColor(srgbRed: 0.72, green: 0.52, blue: 0.30, alpha: 1),
]
/// effort 档位颜色：每档一种，和分项颜色错开
func effortColor(_ e: String) -> Color {
    switch e {
    case "low":    return dynamicColor(0x6B7280, 0xA3AAB6)  // 灰
    case "medium": return dynamicColor(0x667529, 0xB9C47C)  // 橄榄绿
    case "high":   return dynamicColor(0xA3446A, 0xE8A1BE)  // 玫红
    case "xhigh":  return dynamicColor(0x4A53AE, 0xA6ADEC)  // 靛蓝
    case "max":    return dynamicColor(0xB0512A, 0xEFA582)  // 朱橙
    case "ultra":  return dynamicColor(0x876610, 0xE0C25F)  // 金
    default:       return textSecondary
    }
}
/// 文字颜色一律用不透明实色（系统的 .primary/.secondary 带透明度，半透明背景下会透出壁纸）
let textPrimary = dynamicColor(0x1C1D21, 0xF3F4F7)
let textSecondary = dynamicColor(0x5B616B, 0xB3B9C3)
let textTertiary = dynamicColor(0x8B9099, 0x80868F)
func solidNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
    NSColor(name: nil) { ap in
        let hex = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                       blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
let upColor = dynamicColor(0x2E7D4F, 0x7CC79A)
let downColor = dynamicColor(0xB3453F, 0xE89590)

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { g in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = g.size.height * (1 - CGFloat((v - lo) / span))
                        i == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
                    }
                }
                .stroke(textSecondary, style: .init(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct EffortChip: View {
    let effort: String
    @Environment(\.uiScale) var k
    var body: some View {
        Text(effort)
            .font(.system(size: 9.5 * k, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5 * k).padding(.vertical, 1.5 * k)
            .foregroundStyle(effortColor(effort))
            .background(effortColor(effort).opacity(0.15), in: Capsule())
    }
}

struct RowView: View {
    let row: RowVM
    let cfg: Config
    @Environment(\.uiScale) var k

    var meta: String {
        guard let s = row.summary else { return row.listed ? (row.failed ? L("读取失败", "Failed to load") : L("读取中…", "Loading…")) : L("网站未收录该配置", "Not tracked by the site") }
        var parts: [String] = []
        if cfg.shows("cost") {
            if let usd = s.statistics?.metrics?["api_equivalent_usd"]?.value { parts.append(String(format: "$%.2f", usd)) }
            if let ms = s.statistics?.metrics?["elapsed_ms"]?.value { parts.append(String(format: L("%.1f分钟", "%.1f min"), ms / 60000)) }
        }
        if cfg.shows("coverage"), let c = s.coverage { parts.append(L("覆盖\(c)/\(s.required_tasks ?? 64)", "\(c)/\(s.required_tasks ?? 64) tasks")) }
        if cfg.shows("rating"), let r = row.rating, let avg = r.average { parts.append(String(format: L("口碑 %.1f", "Rating %.1f"), avg)) }
        return parts.joined(separator: " · ")
    }

    var insufficient: Bool {
        guard let c = row.summary?.coverage else { return false }
        return c > 0 && c < 40   // 与网站一致：总分覆盖 < 40 题标「数据不足」
    }

    var visibleSources: [(String, String)] { sourceLabels.filter { cfg.shows("src.\($0.0)") } }

    var body: some View {
        HStack(alignment: .center, spacing: 8 * k) {
            VStack(alignment: .leading, spacing: 2.5 * k) {
                HStack(spacing: 5 * k) {
                    Text(prettyModel(row.item.model))
                        .font(.system(size: 12.5 * k, weight: .semibold))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                    EffortChip(effort: row.item.effort)
                    if cfg.shows("runs"), let n = row.summary?.graded_runs_count {
                        Text(L("\(n)次", "\(n) runs"))
                            .font(.system(size: 9 * k).monospacedDigit())
                            .foregroundStyle(textSecondary)
                            .help(L("已正式判分题次", "Officially graded runs"))
                    }
                    if insufficient {
                        Text(L("数据不足", "Low data")).font(.system(size: 9 * k, weight: .medium)).foregroundStyle(textSecondary)
                            .padding(.horizontal, 4 * k).padding(.vertical, 1 * k)
                            .overlay(Capsule().strokeBorder(textTertiary, lineWidth: 0.7))
                    }
                }
                let m = meta
                if !m.isEmpty {
                    Text(m)
                        .font(.system(size: 10 * k).monospacedDigit())
                        .foregroundStyle(textSecondary)
                        .lineLimit(1)
                }
                if let src = row.summary?.source_scores, !visibleSources.isEmpty {
                    HStack(spacing: 8 * k) {
                        ForEach(visibleSources, id: \.0) { key, label in
                            let v = src[key]?.score
                            Text(v.map { "\(label) \(Int($0.rounded()))" } ?? "\(label) —")
                                .foregroundStyle(v == nil ? textTertiary : (sourceColors[key] ?? textSecondary))
                                .lineLimit(1)
                                .fixedSize()
                                .help(v.map { "\(sourceFullName(key)): \(String(format: "%.1f", $0)) · \(src[key]?.coverage ?? 0)/\(src[key]?.required_tasks ?? 0)" } ?? sourceFullName(key))
                        }
                    }
                    .font(.system(size: 10 * k, weight: .semibold).monospacedDigit())
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4 * k)
            if cfg.shows("spark") {
                Sparkline(values: row.series)
                    .frame(width: 42 * k, height: 18 * k)
                    .help(L("每日雷达分走势（\(row.series.count) 个判分日）", "Daily score trend (\(row.series.count) graded days)"))
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.summary?.score.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 19 * k, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(textPrimary)
                if cfg.shows("delta") {
                    if let (d, since) = row.delta, abs(d) >= 0.05 {
                        Text(String(format: "%@%.1f vs %@", d > 0 ? "▲" : "▼", abs(d), since))
                            .font(.system(size: 9 * k, weight: .medium).monospacedDigit())
                            .foregroundStyle(d > 0 ? upColor : downColor)
                    } else {
                        Text(L("持平", "flat")).font(.system(size: 9 * k)).foregroundStyle(textSecondary)
                    }
                }
            }
            .frame(minWidth: 70 * k, alignment: .trailing)
        }
    }
}

struct WidgetView: View {
    @ObservedObject var store: Store
    var onContentHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .environment(\.uiScale, CGFloat(store.config.fontScale ?? 1))
                    .frame(width: geo.size.width, alignment: .topLeading)
                    .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
            }
        }
        .background(
            ZStack {
                VisualEffect().opacity(store.config.backgroundPreset.blur)
                Color(nsColor: .windowBackgroundColor).opacity(store.config.backgroundPreset.tint)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .onPreferenceChange(HeightKey.self) { h in onContentHeight(h) }
    }

    var content: some View { WidgetContent(store: store) }
}

struct WidgetContent: View {
    @ObservedObject var store: Store
    /// 测量理想宽度时不含页脚：页脚只跟随宽度折行，不撑宽窗口
    var measuring = false
    @Environment(\.uiScale) var k

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * k) {
            HStack(spacing: 6 * k) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11.5 * k))
                    .foregroundStyle(textSecondary)
                Text("Codex Radar").font(.system(size: 12 * k, weight: .semibold))
                    .lineLimit(1).fixedSize()
                Text(L("雷达分", "RadarBench")).font(.system(size: 10 * k, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1).fixedSize()
                Spacer()
                if store.loading { ProgressView().controlSize(.mini) }
                Text(L("满分 150", "of 150")).font(.system(size: 9.5 * k, weight: .medium)).foregroundStyle(textSecondary)
                    .lineLimit(1).fixedSize()
                    .help(L("雷达Bench v1：64 题，每题最近 3 次有效判分等权，百分制 × 1.5", "RadarBench v1: 64 tasks, latest 3 valid grades per task weighted equally, percent × 1.5"))
                Color.clear.frame(width: 16 * k, height: 1)   // 图钉按钮位置（AppKit 按钮叠在这里）
            }
            Divider()
            let rows = store.rows
            if rows.isEmpty {
                Text(L("右键 → 关注模型，挑选要展示的模型/effort", "Right-click → Watchlist to pick models / efforts"))
                    .font(.system(size: 11 * k)).foregroundStyle(textSecondary)
            }
            ForEach(rows) { RowView(row: $0, cfg: store.config) }
            if !measuring {
                Divider()
                footer
            }
        }
        .padding(.horizontal, 14 * k).padding(.top, 12 * k).padding(.bottom, 14 * k)
        .foregroundStyle(textPrimary)
    }

    @ViewBuilder var footer: some View {
        VStack(alignment: .leading, spacing: 2 * k) {
            HStack(spacing: 4 * k) {
                if let f = store.lastFetch {
                    Text(L("读取于 ", "Updated ") + f.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().locale(Locale(identifier: Lang.en ? "en_US" : "zh_CN"))))
                } else {
                    Text(L("正在读取…", "Loading…"))
                }
                Text(L("· 口碑 ", "· Ratings ") + store.ratingWindow)
            }
            .foregroundStyle(textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let e = store.errorText {
                Text(e).foregroundStyle(downColor).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 9.5 * k).monospacedDigit())
    }
}

// MARK: - Window plumbing

final class DragHostingView<V: View>: NSHostingView<V> {
    var contextMenu: (() -> NSMenu)?
    var canDrag: () -> Bool = { true }
    override func mouseDown(with event: NSEvent) {
        if canDrag() { window?.performDrag(with: event) } else { super.mouseDown(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let m = contextMenu?() { NSMenu.popUpContextMenu(m, with: event, for: self) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 右下角拉伸手柄：拖动调整窗口大小；按住 ⌥ 拖动缩放字号；双击恢复自适应
final class ResizeGrip: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((_ dx: CGFloat, _ dy: CGFloat, _ option: Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var startMouse = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        solidNS(0x8B9099, 0x80868F).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 1.2
        p.lineCapStyle = .round
        let w = bounds.width
        for i in [3.0, 7.0, 11.0] {
            p.move(to: NSPoint(x: w - 6 - i, y: 6))
            p.line(to: NSPoint(x: w - 6, y: 6 + i))
        }
        p.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(); return }
        startMouse = NSEvent.mouseLocation
        onBegin?()
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        onDrag?(p.x - startMouse.x, p.y - startMouse.y, event.modifierFlags.contains(.option))
    }
}

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = Store()
    var panel: WidgetPanel!
    var host: DragHostingView<WidgetView>!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var contentHeight: CGFloat = 0
    let defaults = UserDefaults.standard
    let baseWidth: CGFloat = 360
    /// 离屏测量：内容在当前字号下的理想（最紧凑）宽度
    let measureHost = NSHostingView(rootView: AnyView(EmptyView()))
    var dragStartFrame = NSRect.zero
    var dragStartScale: Double = 1
    var bag = Set<AnyCancellable>()
    var grip: ResizeGrip!
    let pinButton = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    var pinned: Bool { store.config.pinned == true }

    var autoFitHeight: Bool {
        get { defaults.object(forKey: "autoFitHeight") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoFitHeight") }
    }
    var autoFitWidth: Bool {
        get { defaults.object(forKey: "autoFitWidth") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoFitWidth") }
    }
    var fontScale: Double { store.config.fontScale ?? 1 }

    func applicationDidFinishLaunching(_ n: Notification) {
        if defaults.object(forKey: "topLeft") == nil, let old = UserDefaults(suiteName: "local.modelradar.widget") {
            // 改名前（bundle id local.modelradar.widget）的窗口位置/大小
            for k in ["topLeft", "width", "height", "autoFitWidth", "autoFitHeight", "sizingVersion"] {
                if let v = old.object(forKey: k) { defaults.set(v, forKey: k) }
            }
        }
        if defaults.integer(forKey: "sizingVersion") < 2 {
            // 旧版本里宽度会缩放字号；升级后恢复为自适应内容
            autoFitWidth = true; autoFitHeight = true
            defaults.set(2, forKey: "sizingVersion")
        }
        let width = CGFloat(defaults.object(forKey: "width") as? Double ?? Double(baseWidth))
        let height = CGFloat(defaults.object(forKey: "height") as? Double ?? 420)

        host = DragHostingView(rootView: WidgetView(store: store, onContentHeight: { [weak self] h in
            DispatchQueue.main.async { self?.contentHeightChanged(h) }
        }))
        host.contextMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        host.canDrag = { [weak self] in !(self?.pinned ?? false) }
        host.sizingOptions = []

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        grip = ResizeGrip(frame: NSRect(x: width - 22, y: 0, width: 22, height: 22))
        grip.autoresizingMask = [.minXMargin, .maxYMargin]
        grip.onBegin = { [weak self] in
            guard let self else { return }
            self.dragStartFrame = self.panel.frame
            self.dragStartScale = self.fontScale
        }
        grip.onDrag = { [weak self] dx, dy, option in self?.userDragged(dx: dx, dy: dy, option: option) }
        grip.onDoubleClick = { [weak self] in self?.setAutoFit(true) }
        container.addSubview(grip)
        pinButton.isBordered = false
        pinButton.bezelStyle = .regularSquare
        pinButton.imagePosition = .imageOnly
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(pinButton)
        applyPin()

        panel = WidgetPanel(contentRect: container.frame,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = container
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        applyLevel()
        applyAppearance()
        if let s = defaults.string(forKey: "topLeft") {
            panel.setFrameTopLeftPoint(NSPointFromString(s))
        } else if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: vf.maxX - panel.frame.width - 24, y: vf.maxY - 24))
        }
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Codex Radar")
        let m = NSMenu(); m.delegate = self
        statusItem.menu = m

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        store.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refit() } }
            .store(in: &bag)
        refit()
        scheduleTimer()
        Task { await store.refresh() }
    }

    // MARK: Sizing

    func idealWidth() -> CGFloat {
        measureHost.rootView = AnyView(WidgetContent(store: store, measuring: true).environment(\.uiScale, CGFloat(fontScale)))
        return ceil(measureHost.fittingSize.width)
    }

    /// 自适应宽度：取消显示项/换字号后窗口随之收窄或放宽；高度由 contentHeightChanged 跟进
    func refit() {
        layoutPinButton()
        guard let panel, autoFitWidth else { return }
        let maxW = (panel.screen ?? NSScreen.main)?.visibleFrame.width ?? 1600
        let w = min(max(idealWidth(), 200), maxW)
        guard abs(panel.frame.width - w) > 0.5 else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.minY, width: w, height: panel.frame.height), display: true)
        saveSize()
    }

    /// 图钉放在标题栏右侧预留的位置
    func layoutPinButton() {
        guard let container = panel?.contentView else { return }
        let k = CGFloat(fontScale)
        let b = container.bounds
        let size = max(18, 18 * k)
        pinButton.frame = NSRect(x: b.width - 14 * k - 8 * k - size / 2, y: b.height - 19 * k - size / 2, width: size, height: size)
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")?
            .withSymbolConfiguration(.init(pointSize: 11 * k, weight: .medium))
    }

    func applyPin() {
        grip.isHidden = pinned
        pinButton.contentTintColor = pinned ? .controlAccentColor : solidNS(0x8B9099, 0x80868F)
        pinButton.toolTip = pinned ? L("已固定：点击取消固定", "Pinned — click to unpin") : L("点击固定位置和大小", "Click to pin position & size")
        layoutPinButton()
    }

    func setAutoFit(_ on: Bool) {
        autoFitWidth = on; autoFitHeight = on
        if on { refit(); applyHeight(contentHeight) }
    }

    func userDragged(dx: CGFloat, dy: CGFloat, option: Bool) {
        if option {
            // ⌥ 拖动：等比缩放字号，窗口随内容自适应
            let s = dragStartScale * Double((dragStartFrame.width + dx) / max(dragStartFrame.width, 1))
            store.config.fontScale = (min(2.5, max(0.7, s)) * 100).rounded() / 100
            store.saveConfig()
            setAutoFit(true)
            return
        }
        if abs(dx) > 6 { autoFitWidth = false }
        if abs(dy) > 14 { autoFitHeight = false }
        let start = dragStartFrame
        let w = autoFitWidth ? panel.frame.width : min(1400, max(200, start.width + dx))
        let h = autoFitHeight ? panel.frame.height : min(1600, max(90, start.height - dy))
        panel.setFrame(NSRect(x: start.minX, y: start.maxY - h, width: w, height: h), display: true)
        saveSize()
    }

    func contentHeightChanged(_ h: CGFloat) {
        guard h > 0 else { return }
        contentHeight = h
        if autoFitHeight { applyHeight(h) }
    }

    func applyHeight(_ h: CGFloat) {
        guard let panel, h > 0 else { return }
        let maxH = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 1600
        let target = min(ceil(h), maxH)
        guard abs(panel.frame.height - target) > 0.5 else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - target, width: panel.frame.width, height: target), display: true)
        saveSize()
    }

    func saveSize() {
        defaults.set(Double(panel.frame.width), forKey: "width")
        defaults.set(Double(panel.frame.height), forKey: "height")
        windowDidMove(Notification(name: NSWindow.didMoveNotification))
    }

    func resetSize() {
        store.config.fontScale = 1
        store.saveConfig()
        setAutoFit(true)
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: store.refreshMinutes * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
    }

    func applyLevel() {
        if store.config.floatOnTop == true {
            panel.level = .floating
        } else {
            // 位于桌面图标之上、普通窗口之下 —— 像桌面小组件一样
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    func applyAppearance() {
        switch store.config.appearance {
        case "light": panel.appearance = NSAppearance(named: .aqua)
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        default: panel.appearance = nil
        }
    }

    func windowDidMove(_ n: Notification) {
        defaults.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)), forKey: "topLeft")
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for i in buildMenu().items { i.menu?.removeItem(i); menu.addItem(i) }
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(item(L("立即刷新", "Refresh now"), #selector(refreshNow), key: "r"))
        let lang = NSMenuItem(title: "Language / 语言", action: nil, keyEquivalent: "")
        let langm = NSMenu()
        for (v, label) in [("en", "English"), ("zh", "中文")] {
            let i = item(label, #selector(setLanguage(_:)))
            i.representedObject = v
            i.state = (store.config.language ?? "en") == v ? .on : .off
            langm.addItem(i)
        }
        lang.submenu = langm
        m.addItem(lang)
        m.addItem(.separator())

        let watch = NSMenuItem(title: L("关注模型", "Watchlist"), action: nil, keyEquivalent: "")
        let wm = NSMenu()
        for (model, efforts) in store.catalog {
            let mi = NSMenuItem(title: prettyModel(model), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            var any = false
            for e in efforts {
                let w = WatchItem(model: model, effort: e)
                var title = e
                if let s = store.summaries[w.key]?.score { title += String(format: "   %.1f", s) }
                let ei = item(title, #selector(toggleWatch(_:)))
                ei.representedObject = w.key
                ei.state = store.isWatched(w) ? .on : .off
                any = any || store.isWatched(w)
                sub.addItem(ei)
            }
            mi.submenu = sub
            mi.state = any ? .mixed : .off
            wm.addItem(mi)
        }
        if store.catalog.isEmpty { wm.addItem(NSMenuItem(title: L("（尚未读取到网站收录列表）", "(Catalog not loaded yet)"), action: nil, keyEquivalent: "")) }
        watch.submenu = wm
        m.addItem(watch)

        // 显示内容
        let show = NSMenuItem(title: L("显示内容", "Show"), action: nil, keyEquivalent: "")
        let sm = NSMenu()
        let header = NSMenuItem(title: L("分项", "Category scores"), action: nil, keyEquivalent: ""); header.isEnabled = false
        sm.addItem(header)
        for (key, label) in sourceLabels {
            let i = item(label, #selector(toggleShow(_:)))
            i.representedObject = "src.\(key)"
            i.state = store.config.shows("src.\(key)") ? .on : .off
            let t = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: sourceNSColors[key] ?? .labelColor])
            t.append(NSAttributedString(string: sourceFullName(key)))
            i.attributedTitle = t
            sm.addItem(i)
        }
        sm.addItem(.separator())
        for (k, label) in [("cost", L("费用 · 耗时", "Cost · Duration")), ("coverage", L("覆盖题数", "Task coverage")),
                           ("runs", L("判分次数", "Graded runs")), ("rating", L("口碑评分", "Community rating")),
                           ("spark", L("走势线", "Trend line")), ("delta", L("涨跌", "Change"))] {
            let i = item(label, #selector(toggleShow(_:)))
            i.representedObject = k
            i.state = store.config.shows(k) ? .on : .off
            sm.addItem(i)
        }
        show.submenu = sm
        m.addItem(show)

        let win = NSMenuItem(title: L("口碑评分窗口", "Rating window"), action: nil, keyEquivalent: "")
        let winm = NSMenu()
        for w in ["24h", "7d"] {
            let i = item(w, #selector(setRatingWindow(_:)))
            i.representedObject = w
            i.state = store.ratingWindow == w ? .on : .off
            winm.addItem(i)
        }
        win.submenu = winm
        m.addItem(win)

        // 外观
        let look = NSMenuItem(title: L("外观", "Appearance"), action: nil, keyEquivalent: "")
        let lm = NSMenu()
        for (v, label) in [("system", L("跟随系统", "System")), ("light", L("浅色", "Light")), ("dark", L("深色", "Dark"))] {
            let i = item(label, #selector(setAppearance(_:)))
            i.representedObject = v
            i.state = (store.config.appearance ?? "system") == v ? .on : .off
            lm.addItem(i)
        }
        lm.addItem(.separator())
        let bgHeader = NSMenuItem(title: L("背景", "Background"), action: nil, keyEquivalent: ""); bgHeader.isEnabled = false
        lm.addItem(bgHeader)
        let curBg = store.config.backgroundPreset.key
        for (v, label) in [("solid", L("实色", "Solid")), ("frosted", L("毛玻璃", "Frosted")), ("light", L("浅毛玻璃", "Light frosted")),
                           ("translucent", L("半透明", "Translucent")), ("glass", L("高透明", "Clear glass"))] {
            let i = item(label, #selector(setBackground(_:)))
            i.representedObject = v
            i.state = curBg == v ? .on : .off
            lm.addItem(i)
        }
        look.submenu = lm
        m.addItem(look)

        let font = NSMenuItem(title: L("字号", "Text size"), action: nil, keyEquivalent: "")
        let fm = NSMenu()
        for (v, label) in [(0.85, L("小", "Small")), (1.0, L("标准", "Default")), (1.2, L("大", "Large")), (1.45, L("更大", "Larger")), (1.75, L("特大", "Largest"))] {
            let i = item(label, #selector(setFontScale(_:)))
            i.representedObject = v
            i.state = abs(fontScale - v) < 0.01 ? .on : .off
            fm.addItem(i)
        }
        fm.addItem(.separator())
        let hint = NSMenuItem(title: L("提示：按住 ⌥ 拖动右下角可微调", "Tip: ⌥-drag the corner to fine-tune"), action: nil, keyEquivalent: ""); hint.isEnabled = false
        fm.addItem(hint)
        font.submenu = fm
        m.addItem(font)
        let fit = item(L("大小自适应内容", "Fit size to content"), #selector(toggleAutoFit))
        fit.state = autoFitWidth && autoFitHeight ? .on : (autoFitWidth || autoFitHeight ? .mixed : .off)
        m.addItem(fit)
        m.addItem(item(L("恢复默认大小和字号", "Reset size & text"), #selector(resetSizeAction)))
        let pin = item(L("固定位置和大小", "Pin position & size"), #selector(togglePin), key: "p")
        pin.state = pinned ? .on : .off
        m.addItem(pin)
        let top = item(L("浮于所有窗口之上", "Keep above all windows"), #selector(toggleFloat))
        top.state = store.config.floatOnTop == true ? .on : .off
        m.addItem(top)
        m.addItem(item(panel.isVisible ? L("隐藏桌面组件", "Hide widget") : L("显示桌面组件", "Show widget"), #selector(toggleVisible)))
        let login = item(L("登录时启动", "Launch at login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(item(L("编辑配置文件…", "Edit config file…"), #selector(editConfig)))
        m.addItem(item(L("重新载入配置", "Reload config"), #selector(reloadConfig)))
        m.addItem(item(L("打开 codexradar.com", "Open codexradar.com"), #selector(openSite)))
        m.addItem(.separator())
        m.addItem(item(L("退出", "Quit"), #selector(quit), key: "q"))
        return m
    }

    func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc func refreshNow() { Task { await store.refresh() } }
    @objc func toggleWatch(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
        store.toggle(WatchItem(model: parts[0], effort: parts[1]))
    }
    @objc func toggleShow(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        store.toggleHidden(k)
    }
    @objc func setRatingWindow(_ s: NSMenuItem) {
        guard let w = s.representedObject as? String else { return }
        store.config.ratingWindow = w; store.saveConfig()
        Task { await store.refresh() }
    }
    @objc func setAppearance(_ s: NSMenuItem) {
        guard let v = s.representedObject as? String else { return }
        store.config.appearance = v; store.saveConfig()
        applyAppearance()
    }
    @objc func setBackground(_ s: NSMenuItem) {
        guard let v = s.representedObject as? String else { return }
        store.config.background = v; store.saveConfig()
    }
    @objc func togglePin() {
        store.config.pinned = !pinned; store.saveConfig()
        applyPin()
    }
    @objc func setLanguage(_ s: NSMenuItem) {
        guard let v = s.representedObject as? String else { return }
        store.config.language = v; store.saveConfig()
        applyPin()
    }
    @objc func toggleAutoFit() { setAutoFit(!(autoFitWidth && autoFitHeight)) }
    @objc func setFontScale(_ s: NSMenuItem) {
        guard let v = s.representedObject as? Double else { return }
        store.config.fontScale = v; store.saveConfig()
        setAutoFit(true)
    }
    @objc func resetSizeAction() { resetSize() }
    @objc func toggleFloat() {
        store.config.floatOnTop = !(store.config.floatOnTop ?? false); store.saveConfig()
        applyLevel()
    }
    @objc func toggleVisible() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = L("无法设置登录时启动", "Couldn’t change Launch at Login")
            a.informativeText = error.localizedDescription + L("\n可在「系统设置 → 通用 → 登录项」中手动添加 CodexRadar.app。", "\nYou can add CodexRadar.app manually in System Settings → General → Login Items.")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }
    @objc func editConfig() { NSWorkspace.shared.open(Paths.config) }
    @objc func reloadConfig() {
        store.reloadConfig(); applyLevel(); applyAppearance(); scheduleTimer()
        Task { await store.refresh() }
    }
    @objc func openSite() { NSWorkspace.shared.open(URL(string: "https://codexradar.com/?station=codex#intelligence-efficiency")!) }
    @objc func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
