// ccauth for macOS: a native front end for the ccauth command-line tool.
// Every action runs `ccauth ...`; the window reads `ccauth state` (JSON) to draw itself.

import AppKit
import SwiftUI

// MARK: - State decoded from `ccauth state`

struct AppState: Decodable {
    var version: String
    var claude: Accounts
    var gemini: Accounts
    var agy: Agy
    var checkin: Checkin
    var codex: CodexState
}

struct Accounts: Decodable {
    var current: String?
    var profiles: [Profile]
}

struct Profile: Decodable, Identifiable {
    var name: String
    var email: String?
    var savedAt: String?
    var current: Bool
    var id: String { name }
}

struct Agy: Decodable {
    var active: String
    var bridge: Bool
    var session_saved: Bool
    var providers: [Provider]
    var sites: [Site]
}

struct Provider: Decodable, Identifiable {
    var name: String
    var url: String?
    var key_tail: String
    var models: [String]
    var cheap: String?
    var writer: String?
    var hint: Bool
    var fallback: String?
    var account: String?
    var exhausted: Bool
    var id: String { name }
}

struct Site: Decodable, Identifiable {
    var name: String
    var url: String?
    var username: String?
    var id: String { name }
}

struct Checkin: Decodable {
    var records: [String: CheckinRecord]
    var scheduled: Bool
}

struct CheckinRecord: Decodable {
    var at: String?
    var date: String?
    var status: String?
    var awarded: Double?
    var balance: Double?
    var error: String?
}

struct CodexState: Decodable {
    var enabled: Bool
    var main: String?
    var subagent: String?
    var relay: String?
    var upstream: String?
    var ccswitch_model: String?
    var fallback_models: [String]?
    var router: Bool
}

struct QuotaItem: Decodable {
    var left: Double?
    var used: Double?
    var error: String?
}

// MARK: - Running the command-line tool

enum Runner {
    static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) || FileManager.default.fileExists(atPath: $0) }
    }

    static var script: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return firstExisting([home + "/.local/bin/ccauth"] + [Bundle.main.path(forResource: "ccauth", ofType: nil)].compactMap { $0 })
    }

    static var python: String? {
        firstExisting(["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"])
    }

    static func exec(_ args: [String], input: String? = nil) async -> (Int32, String) {
        guard let py = python, let sc = script else {
            return (127, "找不到 python3 或 ccauth。请先安装 ccauth：https://github.com/qzkinhit/ccauth")
        }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: py)
                p.arguments = [sc] + args
                var env = ProcessInfo.processInfo.environment
                env["CCAUTH_LANG"] = env["CCAUTH_LANG"] ?? "zh"
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                p.environment = env
                let out = Pipe()
                p.standardOutput = out
                p.standardError = out
                let inp = Pipe()
                p.standardInput = inp
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: (126, "无法运行 ccauth：\(error.localizedDescription)"))
                    return
                }
                if let input = input {
                    inp.fileHandleForWriting.write((input + "\n").data(using: .utf8)!)
                }
                try? inp.fileHandleForWriting.close()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var state: AppState?
    @Published var quota: [String: QuotaItem] = [:]
    @Published var quotaLoading = false
    @Published var busy = false
    @Published var output = ""
    @Published var outputOK = true
    @Published var showOutput = false
    @Published var loadError: String?

    func refresh() async {
        let (code, text) = await Runner.exec(["state"])
        guard code == 0, let data = text.data(using: .utf8) else {
            loadError = text.isEmpty ? "ccauth state 返回 \(code)" : text
            return
        }
        do {
            state = try JSONDecoder().decode(AppState.self, from: data)
            loadError = nil
        } catch {
            loadError = "无法解析 ccauth state 的输出：\(error)"
        }
    }

    func run(_ args: [String], input: String? = nil, confirm: String? = nil) {
        if let confirm = confirm {
            let alert = NSAlert()
            alert.messageText = confirm
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        Task {
            busy = true
            let (code, text) = await Runner.exec(args, input: input)
            output = text.trimmingCharacters(in: .whitespacesAndNewlines)
            outputOK = code == 0
            showOutput = true
            await refresh()
            busy = false
        }
    }

    func loadQuota() {
        Task {
            quotaLoading = true
            let (code, text) = await Runner.exec(["agy", "quota", "--json"])
            if code == 0, let data = text.data(using: .utf8),
               let q = try? JSONDecoder().decode([String: QuotaItem].self, from: data) {
                quota = q
            } else {
                output = text
                outputOK = false
                showOutput = true
            }
            quotaLoading = false
        }
    }
}

// MARK: - Small helpers

func pickerOptions(_ list: [String], current: String?, off: String?) -> [(String, String)] {
    var out: [(String, String)] = []
    if let off = off { out.append(("off", off)) }
    out += list.map { ($0, $0) }
    if let c = current, c != "off", !list.contains(c) { out.append((c, c + "（已下架）")) }
    return out
}

func shortTime(_ iso: String?) -> String {
    guard let s = iso, s.count >= 16 else { return "" }
    return String(s.prefix(16)).replacingOccurrences(of: "T", with: " ")
}

struct StatusDot: View {
    var on: Bool
    var onText: String
    var offText: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(on ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
            Text(on ? onText : offText).foregroundStyle(on ? .primary : .secondary)
        }
    }
}

struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}

// MARK: - Antigravity

struct AgyView: View {
    @EnvironmentObject var store: Store
    let s: AppState
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newKey = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("当前模式") {
                    Tag(text: s.agy.active == "official" ? "官方 Google 登录" : "第三方 \(s.agy.active)")
                }
                LabeledContent("本地桥") { StatusDot(on: s.agy.bridge, onText: "运行中", offText: "未运行") }
                LabeledContent("官方登录态") { Text(s.agy.session_saved ? "已保存" : "未保存").foregroundStyle(.secondary) }
                HStack {
                    Button("保存官方登录态") { store.run(["agy", "save"]) }
                    Button("切回官方") { store.run(["agy", "use", "official"]) }
                        .disabled(s.agy.active == "official")
                    Spacer()
                    Text("切换后要完全退出 Antigravity 桌面版再打开").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Antigravity 模式") }

            Section {
                ForEach(s.agy.providers) { p in ProviderRow(p: p, s: s) }
            } header: {
                HStack {
                    Text("第三方中转站")
                    Spacer()
                    Button(store.quotaLoading ? "查询中…" : "查询余额") { store.loadQuota() }
                        .disabled(store.quotaLoading)
                }
            }

            Section {
                TextField("名字", text: $newName, prompt: Text("如 relay2"))
                TextField("地址", text: $newURL, prompt: Text("https://example.com"))
                SecureField("API key", text: $newKey)
                HStack {
                    Text("保存时自动读取该站的 Gemini 模型列表。同名会被拒绝，换 key 请先删除旧的。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存") {
                        store.run(["agy", "add", newName, "--url", newURL, "--key", newKey])
                        newKey = ""
                    }.disabled(newName.isEmpty || newURL.isEmpty || newKey.isEmpty)
                }
            } header: { Text("新增中转站") }
        }
        .formStyle(.grouped)
    }
}

struct ProviderRow: View {
    @EnvironmentObject var store: Store
    let p: Provider
    let s: AppState

    var balance: String {
        guard let q = store.quota[p.name] else { return "余额未查询" }
        if q.error != nil { return "余额查询失败" }
        return String(format: "余额 $%.2f", q.left ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(p.name).font(.headline)
                Text(p.url ?? "").foregroundStyle(.secondary)
                Tag(text: "key …\(p.key_tail)")
                Text(balance).foregroundStyle(store.quota[p.name] == nil ? .secondary : .primary)
                if p.exhausted { Text("今日已用完").foregroundStyle(.orange) }
                Spacer()
                if s.agy.active == p.name {
                    Tag(text: "使用中")
                } else {
                    Button("切换到这里") { store.run(["agy", "use", p.name]) }.buttonStyle(.borderedProminent)
                }
                Button("删除", role: .destructive) { store.run(["agy", "rm", p.name], confirm: "删除中转站 \(p.name)？") }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Picker("工具步骤", selection: Binding(get: { p.cheap ?? "off" },
                                                     set: { store.run(["agy", "cheap", p.name, $0]) })) {
                        ForEach(pickerOptions(p.models, current: p.cheap, off: "关闭（全程主模型）"), id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("写作步骤", selection: Binding(get: { p.writer ?? "off" },
                                                     set: { store.run(["agy", "writer", p.name, $0]) })) {
                        ForEach(pickerOptions(p.models, current: p.writer, off: "关闭"), id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                GridRow {
                    Picker("备用 key", selection: Binding(get: { p.fallback ?? "off" },
                                                        set: { store.run(["agy", "fallback", p.name, $0]) })) {
                        ForEach(pickerOptions(s.agy.providers.map(\.name).filter { $0 != p.name },
                                              current: p.fallback, off: "无"), id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle("省调用提示词", isOn: Binding(get: { p.hint },
                                                     set: { store.run(["agy", "hint", p.name, $0 ? "on" : "off"]) }))
                }
            }
            Text("可用模型：" + p.models.joined(separator: "，")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Codex routing

struct CodexView: View {
    @EnvironmentObject var store: Store
    let s: AppState
    @State private var sub = ""

    var relayModels: [String] {
        let m = s.agy.providers.first { $0.name == s.codex.relay }?.models.filter { $0.hasPrefix("gemini") } ?? []
        return m
    }

    var body: some View {
        Form {
            Section {
                Toggle("开启分流", isOn: Binding(get: { s.codex.enabled },
                                              set: { store.run(["codex", $0 ? "on" : "off"]) }))
                LabeledContent("本地分流") { StatusDot(on: s.codex.router, onText: "运行中", offText: "未运行") }
                Picker("主代理模型", selection: Binding(get: { s.codex.main ?? "" },
                                                   set: { store.run(["codex", "main", $0]) })) {
                    ForEach(pickerOptions(relayModels, current: s.codex.main, off: nil), id: \.0) { Text($0.1).tag($0.0) }
                }
                LabeledContent("主代理中转站") { Text(s.codex.relay ?? "?") }
                LabeledContent("冷却时改用") { Text((s.codex.fallback_models ?? []).joined(separator: "、")).foregroundStyle(.secondary) }
            } header: { Text("主代理（Gemini）") } footer: {
                Text("设置对新开的 Codex 会话生效。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("当前子代理模型") {
                    Text(s.codex.subagent == "follow" ? "跟随 CC Switch（\(s.codex.ccswitch_model ?? "?")）" : (s.codex.subagent ?? "?"))
                }
                HStack {
                    TextField("子代理模型", text: $sub, prompt: Text("如 gpt-6.1-sol"))
                    Button("应用") {
                        let v = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.run(["codex", "subagent", v.isEmpty ? "gpt-6.1-sol" : v])
                    }
                    Button("跟随 CC Switch") { store.run(["codex", "subagent", "follow"]) }
                }
                LabeledContent("CC Switch 当前模型") { Text(s.codex.ccswitch_model ?? "?") }
                LabeledContent("CC Switch 当前服务商") { Text(s.codex.upstream ?? "?").foregroundStyle(.secondary).textSelection(.enabled) }
            } header: { Text("子代理（CC Switch 选中的公益站）") }
        }
        .formStyle(.grouped)
        .onAppear { if s.codex.subagent != "follow" { sub = s.codex.subagent ?? "" } }
    }
}

// MARK: - Daily check-in

struct CheckinView: View {
    @EnvironmentObject var store: Store
    let s: AppState
    @State private var lgProvider = ""
    @State private var lgUser = ""
    @State private var lgPassword = ""
    @State private var stName = ""
    @State private var stURL = ""
    @State private var stUser = ""
    @State private var stUID = ""
    @State private var stToken = ""
    @State private var stPassword = ""

    var names: [String] {
        Set(s.checkin.records.keys).union(s.agy.sites.map(\.name)).union(s.agy.providers.filter { $0.account != nil }.map(\.name)).sorted()
    }

    var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
        Form {
            Section {
                Toggle("自动签到（每天 00:10、12:10 与开机登录时）", isOn: Binding(
                    get: { s.checkin.scheduled },
                    set: { store.run(["agy", "checkin", $0 ? "--install" : "--uninstall"]) }))
                HStack {
                    Text("当天已签的账户不再访问网站，同一站点的账户之间间隔 30 到 60 秒。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("立即签到") { store.run(["agy", "checkin"]) }.buttonStyle(.borderedProminent)
                }
            } header: { Text("每日签到") }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        ForEach(["账户", "今天", "签到奖励", "签到后余额", "时间"], id: \.self) {
                            Text($0).foregroundStyle(.secondary)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(names, id: \.self) { n in
                        let r = s.checkin.records[n]
                        GridRow {
                            Text(n).bold()
                            if r?.status == "error" {
                                Text("失败 " + (r?.error ?? "")).foregroundStyle(.red).lineLimit(2)
                            } else if r?.date == today {
                                Text("已签").foregroundStyle(.green)
                            } else {
                                Text("未签").foregroundStyle(.secondary)
                            }
                            Text(r?.awarded.map { String(format: "+$%.2f", $0) } ?? "—")
                            Text(r?.balance.map { String(format: "$%.2f", $0) } ?? "—")
                            Text(shortTime(r?.at)).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("签到记录") }

            Section {
                Picker("中转站", selection: $lgProvider) {
                    ForEach(s.agy.providers.map(\.name), id: \.self) { Text($0).tag($0) }
                }
                TextField("用户名", text: $lgUser)
                SecureField("密码", text: $lgPassword)
                HStack {
                    Spacer()
                    Button("登录并保存") {
                        store.run(["agy", "login", lgProvider, lgUser], input: lgPassword)
                        lgPassword = ""
                    }.disabled(lgProvider.isEmpty || lgUser.isEmpty || lgPassword.isEmpty)
                }
            } header: { Text("登录 NewAPI 账户（站内有签到按钮的中转站）") }

            Section {
                TextField("名字", text: $stName)
                TextField("地址", text: $stURL, prompt: Text("https://example.com"))
                TextField("用户名或邮箱", text: $stUser)
                TextField("用户 ID（可空）", text: $stUID)
                TextField("系统访问令牌（可空）", text: $stToken)
                SecureField("密码", text: $stPassword)
                HStack {
                    Text("已保存：" + (s.agy.sites.isEmpty ? "无" : s.agy.sites.map { "\($0.name)（\($0.username ?? "")）" }.joined(separator: "，")))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存") {
                        store.run(["agy", "site", stName, stURL, stUser, stUID, stToken], input: stPassword)
                        stPassword = ""
                    }.disabled(stName.isEmpty || stURL.isEmpty || stUser.isEmpty || stPassword.isEmpty)
                }
            } header: { Text("添加登录即签到的站点（如 Agent Router）") }
        }
        .formStyle(.grouped)
        .onAppear { if lgProvider.isEmpty { lgProvider = s.agy.providers.first?.name ?? "" } }
    }
}

// MARK: - Claude / Gemini CLI accounts

struct AccountsView: View {
    @EnvironmentObject var store: Store
    let title: String
    let note: String
    let prefix: [String]
    let accounts: Accounts
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("当前账号") { Text(accounts.current ?? "未登录").textSelection(.enabled) }
                Text(note).font(.caption).foregroundStyle(.secondary)
            } header: { Text(title) }

            Section {
                if accounts.profiles.isEmpty {
                    Text("还没有保存的账号").foregroundStyle(.secondary)
                }
                ForEach(accounts.profiles) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text(p.email ?? "").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(shortTime(p.savedAt)).font(.caption).foregroundStyle(.secondary)
                        if p.current {
                            Tag(text: "当前")
                        } else {
                            Button("切换") { store.run(prefix + ["use", p.name], confirm: "切换到 \(p.name)（\(p.email ?? "")）？") }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("覆盖保存") { store.run(prefix + ["save", p.name, "--force"], confirm: "用当前登录的账号覆盖 \(p.name)？") }
                        Button("删除", role: .destructive) { store.run(prefix + ["rm", p.name], confirm: "删除 \(p.name)？") }
                    }
                }
            } header: { Text("已保存的账号") }

            Section {
                HStack {
                    TextField("名字", text: $newName, prompt: Text("如 work"))
                    Button("保存") { store.run(prefix + ["save", newName]) }.disabled(newName.isEmpty)
                }
            } header: { Text("把当前登录的账号保存为") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Codex request log

struct Attempt: Decodable {
    var model: String
    var code: Int
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        model = (try? c.decode(String.self)) ?? "-"
        code = (try? c.decode(Int.self)) ?? 0
    }
}

struct LogRec: Decodable, Identifiable {
    var ts: String?
    var asked: String?
    var model: String?
    var route: String?
    var ok: Bool?
    var status: Int?
    var ms: Int?
    var ttfb_ms: Int?
    var in_tokens: Int?
    var out_tokens: Int?
    var user: String?
    var reply: String?
    var error: String?
    var tries: [Attempt]?
    var path: String?
    var id: String { (ts ?? "") + (asked ?? "") + String(ms ?? 0) + (user ?? "").prefix(20) }
    var time: String { ts.map { String($0.dropFirst(11).prefix(8)) } ?? "" }
    var modelText: String { (asked == model || model == nil) ? (asked ?? "-") : "\(asked ?? "-") → \(model ?? "-")" }
    var seconds: String { String(format: "%.1fs", Double(ms ?? 0) / 1000) }
    var tokens: String { in_tokens.map { "\($0) / \(out_tokens ?? 0)" } ?? "" }
}

struct CodexLogView: View {
    @State private var rows: [LogRec] = []
    @State private var live = true
    @State private var selection: LogRec.ID?
    @State private var note = ""

    func load() async {
        let (code, text) = await Runner.exec(["codex", "log", "--json", "-n", "300"])
        guard code == 0, let data = text.data(using: .utf8),
              let r = try? JSONDecoder().decode([LogRec].self, from: data) else {
            note = text.isEmpty ? "" : String(text.prefix(300))
            return
        }
        rows = r.reversed()
        note = ""
    }

    var picked: LogRec? { rows.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("实时刷新", isOn: $live).toggleStyle(.switch)
                Text("每 2 秒读取一次，最新的在最上面。只记录经过 ccauth 分流的请求。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(rows.count) 条").foregroundStyle(.secondary)
                Button("立即刷新") { Task { await load() } }
            }
            .padding(10)
            Table(rows, selection: $selection) {
                TableColumn("时间") { Text($0.time).monospacedDigit() }.width(70)
                TableColumn("结果") { r in
                    Text(r.ok == true ? "成功" : "失败 \(r.status ?? 0)").foregroundStyle(r.ok == true ? .green : .red)
                }.width(70)
                TableColumn("去向") { Text($0.route ?? "-") }.width(90)
                TableColumn("模型（请求 → 实际）") { Text($0.modelText) }.width(min: 180, ideal: 260)
                TableColumn("耗时") { Text($0.seconds).monospacedDigit() }.width(55)
                TableColumn("Token 入/出") { Text($0.tokens).monospacedDigit() }.width(90)
                TableColumn("提问") { Text(($0.user ?? "").replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }
            }
            if let r = picked {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("尝试过程：" + (r.tries ?? []).map { "\($0.model)（\($0.code)）" }.joined(separator: " → "))
                        if let t = r.ttfb_ms { Text("首字耗时：\(String(format: "%.1f", Double(t) / 1000)) 秒，总耗时：\(r.seconds)") }
                        if let u = r.user, !u.isEmpty { Text("提问：" + u) }
                        if let p = r.reply, !p.isEmpty { Text("回复：" + p) }
                        if let e = r.error, !e.isEmpty, r.ok != true { Text("错误：" + e).foregroundStyle(.red) }
                    }
                    .font(.system(.callout))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(height: 150)
                .background(.bar)
            }
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).padding(6) }
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if live { await load() }
            }
        }
    }
}

// MARK: - Window

enum Page: String, CaseIterable, Identifiable {
    case agy, codex, codexlog, checkin, claude, gemini
    var id: String { rawValue }
    var title: String {
        switch self {
        case .agy: return "Antigravity"
        case .codex: return "Codex 分流"
        case .codexlog: return "Codex 日志"
        case .checkin: return "每日签到"
        case .claude: return "Claude 账号"
        case .gemini: return "Gemini CLI 账号"
        }
    }
    var icon: String {
        switch self {
        case .agy: return "arrow.triangle.branch"
        case .codex: return "point.3.connected.trianglepath.dotted"
        case .codexlog: return "list.bullet.rectangle"
        case .checkin: return "calendar.badge.checkmark"
        case .claude: return "person.crop.circle"
        case .gemini: return "person.2.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var page: Page? = .agy

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                if let s = store.state {
                    switch page ?? .agy {
                    case .agy: AgyView(s: s)
                    case .codex: CodexView(s: s)
                    case .codexlog: CodexLogView()
                    case .checkin: CheckinView(s: s)
                    case .claude:
                        AccountsView(title: "Claude Code 账号", note: "切换后重启 claude，正在运行的会话仍用旧账号。",
                                     prefix: [], accounts: s.claude)
                    case .gemini:
                        AccountsView(title: "Gemini CLI 账号", note: "切换后重启 gemini。",
                                     prefix: ["gemini"], accounts: s.gemini)
                    }
                } else if let err = store.loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(err).textSelection(.enabled).frame(maxWidth: 520)
                        Button("重试") { Task { await store.refresh() } }
                    }.padding()
                } else {
                    ProgressView("读取中…")
                }
            }
            .navigationTitle((page ?? .agy).title)
            .toolbar {
                ToolbarItem {
                    if store.busy { ProgressView().controlSize(.small) }
                }
                ToolbarItem {
                    Button { Task { await store.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.showOutput {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: store.outputOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(store.outputOK ? .green : .red)
                            Text(store.outputOK ? "完成" : "失败").bold()
                            Spacer()
                            Button("关闭") { store.showOutput = false }.buttonStyle(.borderless)
                        }
                        ScrollView {
                            Text(store.output.isEmpty ? "（没有输出）" : store.output)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 130)
                    }
                    .padding(12)
                    .background(.bar)
                }
            }
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if !store.busy { await store.refresh() }
            }
        }
    }
}

@main
struct CcauthApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("ccauth") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("刷新") { Task { await store.refresh() } }.keyboardShortcut("r")
            }
        }
    }
}
