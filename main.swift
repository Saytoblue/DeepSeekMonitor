import Cocoa
import SwiftUI
import Charts
import Combine

// --- 1. 数据模型 ---

// 余额/总览接口 (get_user_summary)
struct SummaryResponse: Decodable {
    let data: SummaryData
}
struct SummaryData: Decodable {
    let biz_data: SummaryBizData
}
struct SummaryBizData: Decodable {
    let normal_wallets: [Wallet]
    let monthly_costs: [SummaryCost]
}
struct Wallet: Decodable {
    let currency: String
    let balance: String
}
struct SummaryCost: Decodable {
    let currency: String
    let amount: String
}

// 金额明细接口 (usage/cost) - biz_data 是数组
struct CostResponse: Decodable {
    let data: CostData
}
struct CostData: Decodable {
    let biz_data: [BizDataContent]
}
struct BizDataContent: Decodable {
    let total: [ModelUsage]
    let days: [DailyCost]
}

// Token 明细接口 (usage/amount) - biz_data 是对象
struct AmountResponse: Decodable {
    let data: AmountData
}
struct AmountData: Decodable {
    let biz_data: AmountBizData
}
struct AmountBizData: Decodable {
    let total: [ModelUsage]
    let days: [DailyToken]
}

// 通用模型与用量结构
struct ModelUsage: Decodable {
    let model: String
    let usage: [UsageDetail]
}
struct UsageDetail: Decodable {
    let type: String
    let amount: String
}
struct DailyCost: Identifiable, Decodable {
    var id: String { date }
    let date: String
    let data: [ModelUsage]
    func totalValue() -> Double {
        data.flatMap { $0.usage }.reduce(0) { $0 + (Double($1.amount) ?? 0) }
    }
}
struct DailyToken: Decodable {
    let date: String
    let data: [ModelUsage]
}

// UI 显示模型
struct ModelDisplayData: Identifiable {
    let id = UUID()
    let name: String
    let cost: String
    let tokens: String
    let progress: Double
}

// 组合后的每日图表数据模型
struct DailyChartData: Identifiable {
    var id: String { date }
    let date: String
    let costAmount: Double
    let tokenAmount: Double
    
    var tokenString: String {
        if tokenAmount >= 1_000_000 { return String(format: "%.1fM", tokenAmount / 1_000_000) }
        if tokenAmount >= 1_000 { return String(format: "%.1fK", tokenAmount / 1_000) }
        if tokenAmount == 0 { return "" }
        return String(format: "%.0f", tokenAmount)
    }
}

// --- 2. 逻辑管理器 ---

class MonitorViewModel: ObservableObject {
    @Published var balance: String = "0.00"
    @Published var monthlyCost: String = "0.00"
    @Published var lastUpdate: String = "--:--"
    @Published var modelBreakdown: [ModelDisplayData] = []
    @Published var chartData: [DailyChartData] = [] // 更新为组合数据模型

    // ⚠️ 替换为你的鉴权信息（从 DeepSeek Platform 控制台获取）
    //   1. 打开 https://platform.deepseek.com 并登录
    //   2. 打开浏览器开发者工具 -> Application -> Cookies，复制完整的 Cookie 字符串
    //   3. 在 Network 面板中找到任意 API 请求，复制 Authorization 头的 Bearer Token
    private let cookie = "YOUR_COOKIE_HERE"
    private let auth = "Bearer YOUR_TOKEN_HERE"
    
    private let summaryURL = "https://platform.deepseek.com/api/v0/users/get_user_summary"
    private var costURL: String {
        let now = Date()
        let month = Calendar.current.component(.month, from: now)
        let year = Calendar.current.component(.year, from: now)
        return "https://platform.deepseek.com/api/v0/usage/cost?month=\(month)&year=\(year)"
    }
    private var amountURL: String {
        let now = Date()
        let month = Calendar.current.component(.month, from: now)
        let year = Calendar.current.component(.year, from: now)
        return "https://platform.deepseek.com/api/v0/usage/amount?month=\(month)&year=\(year)"
    }

    func fetchData() {
        print("🔄 开始拉取最新数据...")
        fetchSummary()
        fetchCombinedDetails()
    }

    private func fetchSummary() {
        var request = URLRequest(url: URL(string: summaryURL)!)
        request.addValue(cookie, forHTTPHeaderField: "Cookie")
        request.addValue(auth, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            do {
                let decoded = try JSONDecoder().decode(SummaryResponse.self, from: data)
                let biz = decoded.data.biz_data
                DispatchQueue.main.async {
                    if let cnyW = biz.normal_wallets.first(where: { $0.currency == "CNY" }) {
                        self.balance = String(format: "%.2f", Double(cnyW.balance) ?? 0)
                    }
                    if let cnyC = biz.monthly_costs.first(where: { $0.currency == "CNY" }) {
                        self.monthlyCost = String(format: "%.2f", Double(cnyC.amount) ?? 0)
                    }
                }
            } catch { print("⚠️ Summary 解析失败: \(error)") }
        }.resume()
    }

    private func fetchCombinedDetails() {
        let group = DispatchGroup()
        var costResult: CostResponse?
        var amountResult: AmountResponse?

        group.enter()
        var costReq = URLRequest(url: URL(string: costURL)!)
        costReq.addValue(cookie, forHTTPHeaderField: "Cookie")
        costReq.addValue(auth, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: costReq) { data, _, _ in
            if let data = data { costResult = try? JSONDecoder().decode(CostResponse.self, from: data) }
            group.leave()
        }.resume()

        group.enter()
        var amountReq = URLRequest(url: URL(string: amountURL)!)
        amountReq.addValue(cookie, forHTTPHeaderField: "Cookie")
        amountReq.addValue(auth, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: amountReq) { data, _, _ in
            if let data = data { amountResult = try? JSONDecoder().decode(AmountResponse.self, from: data) }
            group.leave()
        }.resume()

        group.notify(queue: .main) {
            guard let costs = costResult?.data.biz_data.first, 
                  let amounts = amountResult?.data.biz_data else { return }
            
            // 1. 生成模型列表数据
            let tokenCap = 100_000_000.0 // 满进度 = 1亿 Token
            var breakdown: [ModelDisplayData] = []
            for costItem in costs.total {
                let rawModelName = costItem.model
                let costVal = costItem.usage.reduce(0) { $0 + (Double($1.amount) ?? 0) }
                if costVal <= 0 { continue }

                let tokenSum = amounts.total.first(where: { $0.model == rawModelName })?
                    .usage.filter { $0.type.contains("TOKEN") }
                    .reduce(0) { $0 + (Double($1.amount) ?? 0) } ?? 0

                var displayName = rawModelName
                if displayName == "deepseek-v4-pro" { displayName = "DeepSeek-V4-pro" }
                else if displayName == "deepseek-v4-flash" { displayName = "DeepSeek-V4-flash" }
                else { displayName = displayName.replacingOccurrences(of: "deepseek-", with: "") }

                breakdown.append(ModelDisplayData(
                    name: displayName,
                    cost: "¥" + String(format: "%.2f", costVal),
                    tokens: self.formatTokens(tokenSum) + "/100M",
                    progress: min(tokenSum / tokenCap, 1.0)
                ))
            }
            self.modelBreakdown = breakdown
            
            // 2. 生成图表合并数据 (合并成本与Token)
            var newChartData: [DailyChartData] = []
            let validDays = costs.days.filter { $0.totalValue() > 0 }.suffix(7)
            
            for dayCost in validDays {
                let dCost = dayCost.totalValue()
                // 在 amount 数据中寻找同一天的 Token 总数
                let dailyTokenSum = amounts.days.first(where: { $0.date == dayCost.date })?
                    .data.flatMap { $0.usage }
                    .filter { $0.type.contains("TOKEN") }
                    .reduce(0) { $0 + (Double($1.amount) ?? 0) } ?? 0
                
                newChartData.append(DailyChartData(
                    date: dayCost.date,
                    costAmount: dCost,
                    tokenAmount: dailyTokenSum
                ))
            }
            self.chartData = newChartData
            self.lastUpdate = Date().formatted(date: .omitted, time: .shortened)
            print("✅ 数据合并更新完成！")
        }
    }

    private func formatTokens(_ val: Double) -> String {
        if val >= 1_000_000 { return String(format: "%.1fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
        return String(format: "%.0f", val)
    }
}

// --- 3. UI 界面 ---

struct ContentView: View {
    @ObservedObject var viewModel: MonitorViewModel
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(nsImage: NSImage(contentsOfFile: Bundle.main.path(forResource: "deepseek_avatar", ofType: "png") ?? "") ?? NSImage()).resizable().frame(width: 18, height: 18)
                Text("DeepSeek Monitor").font(.headline)
                Spacer()
                Button(action: { viewModel.fetchData() }) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
                Button(action: { NSApplication.shared.terminate(nil) }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain).padding(.leading, 6)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("当前余额").font(.caption).foregroundColor(.gray)
                        Text("¥ \(viewModel.balance)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.blue)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("本月消费").font(.caption).foregroundColor(.gray)
                        Text("¥ \(viewModel.monthlyCost)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.orange)
                    }
                }
                HStack {
                    Label("服务正常", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundColor(.green)
                    Spacer()
                    Text("更新于 \(viewModel.lastUpdate)").font(.system(size: 10)).foregroundColor(.gray)
                }
            }
            .padding(12).background(Color(NSColor.windowBackgroundColor).opacity(0.5)).cornerRadius(12)

            VStack(spacing: 12) {
                ForEach(viewModel.modelBreakdown) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.name).font(.subheadline).bold()
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(model.cost).font(.subheadline).foregroundColor(.primary)
                                Text(model.tokens).font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                        ProgressView(value: model.progress).progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    }
                }
            }

            // 消耗趋势图表区域
            VStack(alignment: .leading, spacing: 8) {
                Text("消耗趋势").font(.caption).foregroundColor(.gray)
                Chart(viewModel.chartData) { item in
                    BarMark(
                        x: .value("Day", String(Int(item.date.suffix(2)) ?? 0)),
                        y: .value("Tokens", item.tokenAmount)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        Text(item.tokenString)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
            }
        }
        .padding().frame(width: 300)
    }
}

// --- 4. 生命周期管理 (AppDelegate) ---
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var viewModel = MonitorViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover = NSPopover()
        // 稍微拉长整体面板，以适应变高的图表
        popover.contentSize = NSSize(width: 300, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let path = Bundle.main.path(forResource: "deepseek_avatar", ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "heart.bubble", accessibilityDescription: "DS")
            }
            button.action = #selector(togglePopover(_:))
        }
        viewModel.fetchData()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in self.viewModel.fetchData() }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown { popover.performClose(sender) }
            else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()