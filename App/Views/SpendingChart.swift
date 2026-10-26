import SwiftUI
import Charts
#if canImport(BudgetStore)
import BudgetStore
#endif

struct SpendingChart: View {
    let entries: [LedgerEntry]
    let categories: [LedgerCategory]
    var selectedCategoryID: String?
    var onCategorySelected: (String) -> Void

    private var categorySpending: [(id: String, name: String, amount: Int64, color: Color)] {
        let filteredExpenses = entries.filter { $0.kind == .expense }
        let totals = Dictionary(grouping: filteredExpenses, by: \.categoryID)
            .mapValues { $0.reduce(0) { $0 + $1.amountPaise } }

        return totals.map { id, amount in
            let cat = categories.first { $0.id == id }
            return (id: id, name: cat?.name ?? "Uncategorized", amount: amount, color: LedgerTheme.color(cat?.tint ?? "gray"))
        }.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if entries.filter({ $0.kind == .expense }).isEmpty {
                ContentUnavailableView("No spending data", systemImage: "chart.pie.fill")
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(categorySpending, id: \.id) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(selectedCategoryID == nil || selectedCategoryID == item.id ? item.color : item.color.opacity(0.3))
                        .cornerRadius(4)
                    }
                }
                .frame(height: 200)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let anchor = proxy.plotFrame {
                            let plotFrame = geometry[anchor]
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { tap in
                                    let center = CGPoint(x: plotFrame.midX, y: plotFrame.midY)
                                    let dx = tap.location.x - center.x
                                    let dy = tap.location.y - center.y
                                    let radius = hypot(dx, dy)
                                    let outerRadius = min(plotFrame.width, plotFrame.height) / 2
                                    // Ignore taps in the donut hole and outside the pie.
                                    guard radius >= outerRadius * 0.6, radius <= outerRadius else { return }
                                    let plotLocation = CGPoint(x: dx + plotFrame.width / 2, y: dy + plotFrame.height / 2)
                                    let angle = proxy.angle(at: plotLocation)
                                    guard let value = proxy.value(atAngle: angle, as: Int64.self) else { return }
                                    selectCategory(at: Double(value))
                                })
                        }
                    }
                }
                .chartLegend {
                    ForEach(categorySpending, id: \.id) { item in
                        Label(item.name, systemImage: "circle.fill")
                            .foregroundStyle(item.color)
                            .font(.caption)
                            .opacity(selectedCategoryID == nil || selectedCategoryID == item.id ? 1.0 : 0.5)
                            .onTapGesture { toggleCategory(item.id) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let totalAmount = categorySpending.reduce(0) { $0 + $1.amount }
                    ForEach(categorySpending, id: \.id) { item in
                        HStack {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.name).font(.caption).foregroundStyle(.primary)
                            Spacer()
                            let percentage = totalAmount > 0 ? (Double(item.amount) / Double(totalAmount) * 100) : 0
                            Text("\(String(format: "%.1f", percentage))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .opacity(selectedCategoryID == nil || selectedCategoryID == item.id ? 1.0 : 0.5)
                        .onTapGesture { toggleCategory(item.id) }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func selectCategory(at value: Double) {
        guard value >= 0 else { return }
        var cumulativeAmount = 0.0
        for item in categorySpending {
            cumulativeAmount += Double(item.amount)
            if value < cumulativeAmount {
                toggleCategory(item.id)
                return
            }
        }
    }

    private func toggleCategory(_ categoryID: String) {
        onCategorySelected(selectedCategoryID == categoryID ? "all" : categoryID)
    }
}
