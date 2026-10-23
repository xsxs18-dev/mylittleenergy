import SwiftUI
import Charts

// MARK: - Cards

struct CardStyle: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

// SwiftUI lists render their rows in UIKit cells. When a row updates, its symbols can pick up the
// window's tint (system blue) instead of the tint set further up, so the accent color is applied
// at every navigation root and to the windows themselves.
struct AccentTint: ViewModifier {
    @ObservedObject private var settings = SettingsStore.shared

    func body(content: Content) -> some View {
        content
            .tint(settings.accent)
            .accentColor(settings.accent)
            .onAppear { applyToWindows(settings.accent) }
            .onChange(of: settings.string("accentColor")) { _ in applyToWindows(settings.accent) }
    }

    private func applyToWindows(_ color: Color) {
        let tint = UIColor(color)
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows { window.tintColor = tint }
        }
    }
}

extension View {
    func accentTint() -> some View {
        modifier(AccentTint())
    }

    func card(padding: CGFloat = 14) -> some View {
        modifier(CardStyle(padding: padding))
    }

    // Liquid Glass on iOS 26, the classic prominent button before.
    @ViewBuilder
    func prominentButton() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

}

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(color.gradient))
    }
}

struct MetricCard<Accessory: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var caption: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            accessory()
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .card()
    }
}

extension MetricCard where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color, value: String, caption: String? = nil) {
        self.init(title: title, symbol: symbol, tint: tint, value: value, caption: caption, accessory: { EmptyView() })
    }
}

// MARK: - Charts

struct ChartPoint: Identifiable {
    let id: Int
    let x: Date
    let y: Double
}

struct Sparkline: View {
    let points: [ChartPoint]
    let tint: Color
    var height: CGFloat = 34

    var body: some View {
        let range = domain
        Chart(points) { point in
            // The area starts at the bottom of the visible range; down to zero it would spill out of the card.
            AreaMark(x: .value("t", point.x), yStart: .value("low", range.lowerBound), yEnd: .value("v", min(max(point.y, range.lowerBound), range.upperBound)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", point.x), y: .value("v", point.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: range)
        .chartPlotStyle { $0.clipped() }
        .frame(height: height)
        .clipped()
    }

    private var domain: ClosedRange<Double> {
        let values = points.map(\.y).filter(\.isFinite)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.2, 0.5)
        return (low - pad)...(high + pad)
    }
}

// MARK: - Ring

struct BatteryRing: View {
    let level: Double
    let tint: Color
    var lineWidth: CGFloat = 22
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(shown, 0.005))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.45), radius: 14)
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { shown = level }
        }
        .onChange(of: level) { value in
            withAnimation(.easeInOut(duration: 0.6)) { shown = value }
        }
    }
}

// MARK: - Battery glyph

struct BatteryGlyph: View {
    let level: Double
    let fill: Color
    var charging = false

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 2)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fill)
                        .frame(width: max(4, (proxy.size.width - 6) * level))
                        .padding(3)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 52, height: 26)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.35))
                .frame(width: 3, height: 9)
        }
    }
}

// MARK: - Lists

// A binding to one element of an array, found by id instead of by index. ForEach($array) hands out
// index-based bindings; after a swipe-to-delete, the deleted row's controls still read their old
// index once and crash with "index out of range". This one falls back to the last known value.
func elementBinding<Element: Identifiable>(_ array: Binding<[Element]>, _ element: Element) -> Binding<Element> {
    Binding(
        get: { array.wrappedValue.first { $0.id == element.id } ?? element },
        set: { value in
            guard let index = array.wrappedValue.firstIndex(where: { $0.id == element.id }) else { return }
            array.wrappedValue[index] = value
        }
    )
}

// MARK: - Rows

struct ValueRow: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct ModuleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct InfoBanner: View {
    let symbol: String
    let text: String
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.body.weight(.semibold))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
