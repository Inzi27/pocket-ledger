import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

enum LedgerTheme {
    static let background = Color("LedgerBackground", bundle: .main)
    static func color(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "indigo": return .indigo
        case "gray": return .gray
        default: return .teal
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, orange, pink, green, red, gray, yellow
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    private var rgb: (Double, Double, Double) {
        switch self {
        case .teal: return (0.08, 0.38, 0.33)
        case .blue: return (0.12, 0.36, 0.72)
        case .indigo: return (0.30, 0.28, 0.65)
        case .purple: return (0.51, 0.24, 0.65)
        case .orange: return (0.70, 0.30, 0.06)
        case .pink: return (0.69, 0.19, 0.39)
        case .green: return (0.18, 0.43, 0.22)
        case .red: return (0.72, 0.16, 0.18)
        case .gray: return (0.36, 0.39, 0.43)
        case .yellow: return (0.57, 0.43, 0.02)
        }
    }
    var heroStart: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
    var gradientEnd: Color { Color(red: rgb.0 * 0.7, green: rgb.1 * 0.7, blue: rgb.2 * 0.7) }
    /// Native menus tint template symbols. Render the swatch in its original color instead.
    var menuSwatch: Image {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18))
        let swatch = renderer.image { _ in
            // Use a recognizable yellow swatch; the darker yellow accent keeps text readable.
            UIColor(self == .yellow ? Color.yellow : heroStart).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16)).fill()
        }
        return Image(uiImage: swatch.withRenderingMode(.alwaysOriginal)).renderingMode(.original)
        #else
        return Image(systemName: "circle.fill").renderingMode(.original)
        #endif
    }
    var accent: Color {
        #if os(iOS)
        let components = rgb
        return Color(uiColor: UIColor { traits in
            let lift = traits.userInterfaceStyle == .dark ? 0.32 : 0.0
            return UIColor(red: CGFloat(components.0 + (1 - components.0) * lift),
                           green: CGFloat(components.1 + (1 - components.1) * lift),
                           blue: CGFloat(components.2 + (1 - components.2) * lift), alpha: 1)
        })
        #else
        return heroStart
        #endif
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { self == .system ? "Follow system" : rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct LedgerPaletteKey: EnvironmentKey {
    static let defaultValue = AppTheme.teal
}

extension EnvironmentValues {
    var ledgerPalette: AppTheme {
        get { self[LedgerPaletteKey.self] }
        set { self[LedgerPaletteKey.self] = newValue }
    }
}

struct CategoryIcon: View {
    var symbol: String
    var tint: String
    var compact = false
    @ScaledMetric(relativeTo: .subheadline) private var compactSize: CGFloat = 34
    var body: some View {
        Image(systemName: symbol).font(compact ? .subheadline.weight(.semibold) : .system(size: 17, weight: .semibold))
            .foregroundStyle(LedgerTheme.color(tint))
            .frame(width: compact ? compactSize : 42, height: compact ? compactSize : 42)
            .background(LedgerTheme.color(tint).opacity(0.12), in: RoundedRectangle(cornerRadius: compact ? 11 : 14))
            .accessibilityHidden(true)
    }
}

struct TransactionRow: View {
    @Environment(\.ledgerPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: LedgerEntry
    let category: LedgerCategory?
    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(symbol: category?.symbol ?? "tag.fill", tint: category?.tint ?? "gray", compact: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.merchant).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                HStack(spacing: 4) {
                    Text(entry.payment.label)
                    Text("·")
                    Text(entry.date, format: .dateTime.day().month(.abbreviated))
                    if entry.needsReview { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("Needs review") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text((entry.kind == .refund || entry.kind == .income ? "+" : "") + Money.formatted(entry.amountPaise))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(entry.kind == .refund || entry.kind == .income ? palette.accent : .primary)
                Text(entry.kind == .expense ? category?.name ?? "Uncategorized" : entry.kind.label)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension View {
    func ledgerBackground() -> some View { self.scrollContentBackground(.hidden).background(LedgerTheme.background) }
    @ViewBuilder func amountKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
    @ViewBuilder func plainTextInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

struct ErrorNotice: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Couldn’t save that change", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "Please try again.") }
    }
}
