import SwiftUI

// Building blocks for the panel, following the LensControl design's component notes:
// 84 pt right-aligned label column, 10 pt gutter, rows ≥ 24 pt and 6 pt apart,
// pop-ups capped at ~170 pt. Each section sits in its own rounded card: Liquid
// Glass on macOS 26 and later, a quiet tinted fill before that.

enum Metrics {
    static let labelWidth: CGFloat = 84
    static let gutter: CGFloat = 10
    static let rowSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    static let popupMaxWidth: CGFloat = 170
    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 12
}

/// "☀︎ Exposure" — a symbol in the accent colour and a 12 pt semibold title.
struct SectionHeader: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

/// A section: header plus rows, on a glass card.
struct FormSection<Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder let content: Content

    init(title: String, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            SectionHeader(title: title, symbol: symbol)
            content
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground())
    }
}

// MARK: - Liquid Glass (macOS 26+) with material fallbacks

/// Groups glass cards so neighbouring ones blend and sample the backdrop once.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: Metrics.sectionSpacing) { content }
        } else {
            content
        }
    }
}

/// A section card.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        } else {
            content.background(.quaternary.opacity(0.4),
                               in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// A small pill (mode badge, chips).
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.quaternary.opacity(0.5), in: Capsule())
        }
    }
}

/// Glass button where available, bordered before that.
struct GlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Label column + value column. Multi-line controls (Kelvin, EV) pass `.top`
/// so the label lines up with their first line.
struct FormRow<Content: View>: View {
    let label: String
    let alignment: VerticalAlignment
    let content: Content

    init(label: String, alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: Metrics.gutter) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Metrics.labelWidth, height: alignment == .top ? 22 : nil, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 24)
    }
}

/// A RADIO entry as a pop-up; when the mode dial makes it read-only it turns
/// into a flat field with "Set by camera" and an explanatory tooltip (never hidden).
struct ChoicePopup: View {
    let entry: ConfigEntry
    var names: [String: String] = [:]
    var readOnlyTip: String?
    let select: (String) -> Void

    var body: some View {
        if entry.readOnly {
            HStack(spacing: 8) {
                Text(display(entry.current))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(width: 100, height: 22, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
                Text("Set by camera")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .help(readOnlyTip ?? "\(entry.label) is set by the camera in its current mode")
        } else {
            Picker(entry.label, selection: Binding(get: { entry.current }, set: select)) {
                ForEach(entry.choices, id: \.self) { choice in
                    Text(display(choice)).tag(choice)
                }
                // Keep the picker consistent if the camera reports a value outside its own list.
                if !entry.choices.contains(entry.current) {
                    Text(display(entry.current)).tag(entry.current)
                }
            }
            .labelsHidden()
            .frame(maxWidth: Metrics.popupMaxWidth, alignment: .leading)
            .help(entry.label)
        }
    }

    private func display(_ choice: String) -> String { names[choice] ?? choice }
}

/// A RADIO entry as a segmented control, showing only the choices given (in that order).
struct SegmentedChoice: View {
    let entry: ConfigEntry
    /// (camera choice, short label)
    let options: [(choice: String, label: String)]
    let select: (String) -> Void

    var body: some View {
        let available = options.filter { entry.choices.contains($0.choice) }
        Picker(entry.label, selection: Binding(get: { entry.current }, set: select)) {
            ForEach(available, id: \.choice) { option in
                Text(option.label).tag(option.choice)
            }
            if !available.contains(where: { $0.choice == entry.current }) {
                Text("—").tag(entry.current)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .disabled(entry.readOnly)
        .help(entry.label)
    }
}

/// Exposure compensation from −3 to +3 in ⅓ steps. The centre is "home": its
/// tick is taller and full-ink, the fill grows outward from 0, the readout greys
/// out at 0.0, and double-click or the 0 key resets.
struct EVSlider: View {
    /// Number of camera choices (19 for −3…+3).
    let count: Int
    let index: Int
    let commit: (Int) -> Void

    @State private var draft: Int?
    @FocusState private var focused: Bool

    private var center: Int { count / 2 }

    var body: some View {
        let current = draft ?? index
        HStack(spacing: 8) {
            VStack(spacing: 1) {
                GeometryReader { geo in
                    track(width: geo.size.width, current: current)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { draft = step(at: $0.location.x, width: geo.size.width) }
                            .onEnded {
                                let value = step(at: $0.location.x, width: geo.size.width)
                                draft = nil
                                commit(value)
                            })
                        .simultaneousGesture(TapGesture(count: 2).onEnded { commit(center) })
                }
                .frame(height: 24)
                HStack {
                    Text("−3")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("+3")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            }
            Text(Self.format(step: current, center: center))
                .monospacedDigit()
                .foregroundStyle(current == center ? .secondary : .primary)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(maxWidth: Metrics.popupMaxWidth + 42)
        .focusable()
        .focusEffectDisabled()   // the knob's own ring shows focus; no system outline around the row
        .focused($focused)
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.downArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .onKeyPress(.upArrow) { nudge(1) }
        .onKeyPress("0") { commit(center); return .handled }
        .help("Exposure compensation · double-click for 0")
    }

    private func track(width: CGFloat, current: Int) -> some View {
        let x = { (i: Int) in 8 + (width - 16) * CGFloat(i) / CGFloat(max(1, count - 1)) }
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.quaternary)
                .frame(width: width - 16, height: 4)
                .offset(x: 8, y: 7)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: abs(x(current) - x(center)), height: 4)
                .offset(x: min(x(current), x(center)), y: 7)
            ForEach(0..<count, id: \.self) { i in
                let offset = i - center
                Rectangle()
                    .fill(offset == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 1, height: offset == 0 ? 8 : offset % 3 == 0 ? 5 : 3)
                    .offset(x: x(i) - 0.5, y: 15)
            }
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                .frame(width: 18, height: 18)
                .offset(x: x(current) - 9, y: 0)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(focused ? 0.5 : 0), lineWidth: 3)
                        .frame(width: 22, height: 22)
                        .offset(x: x(current) - 11, y: -2),
                    alignment: .topLeading)
        }
    }

    private func step(at x: CGFloat, width: CGFloat) -> Int {
        let fraction = min(max((x - 8) / (width - 16), 0), 1)
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    private func nudge(_ delta: Int) -> KeyPress.Result {
        commit(min(max(index + delta, 0), count - 1))
        return .handled
    }

    /// "0.0", "+1.3", "−0.7" — thirds of a stop from the centre step.
    static func format(step: Int, center: Int) -> String {
        let thirds = step - center
        guard thirds != 0 else { return "0.0" }
        let value = String(format: "%.1f", abs(Double(thirds) / 3))
        return (thirds > 0 ? "+" : "−") + value
    }
}

/// Colour temperature: slider that commits on release, then −100 · [5600] K · +100.
struct KelvinControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let commit: (Double) -> Void

    @State private var draft: Double = 0
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $draft, in: range, step: step) { isDragging in
                if !isDragging { commit(draft) }
            }
            .controlSize(.small)
            .help("Colour temperature · commits on release")
            HStack(spacing: 6) {
                Button("−100") { set(draft - 100) }
                    .help("−100 K (warmer)")
                HStack(spacing: 3) {
                    TextField("K", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 56)
                        .focused($editing)
                        .onSubmit { set(Double(text) ?? draft); editing = false }
                        .onExitCommand { text = String(Int(draft)); editing = false }
                        .onChange(of: text) { _, new in
                            let digits = new.filter(\.isNumber)
                            if digits != new { text = digits }
                        }
                    Text("K").foregroundStyle(.secondary)
                }
                Button("+100") { set(draft + 100) }
                    .help("+100 K (cooler)")
            }
            .controlSize(.small)
        }
        .onAppear { sync(value) }
        .onChange(of: value) { _, new in sync(new) }
        .onChange(of: draft) { _, new in if !editing { text = String(Int(new)) } }
    }

    private func sync(_ new: Double) {
        draft = new
        if !editing { text = String(Int(new)) }
    }

    private func set(_ raw: Double) {
        let snapped = (raw / step).rounded() * step
        draft = min(max(snapped, range.lowerBound), range.upperBound)
        text = String(Int(draft))
        commit(draft)
    }
}

/// Dismissible one-line warning under the controls.
struct WarningBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 16, height: 16)
                .background(Color.yellow, in: Circle())
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}
