import SwiftUI

/// The LensControl panel. The popover is one 330 pt column; the window is 680 pt
/// with two columns (Exposure + White balance · Preview + Focus + Presets).
struct ContentView: View {
    enum Presentation {
        case popover, window
    }

    let presentation: Presentation

    @Environment(CameraModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("keepWindowOnTop") private var keepOnTop = false
    @AppStorage("livePreview") private var livePreview = true
    /// The MenuBarExtra's own window, for closing it and for keeping its frame in
    /// step with the content (it grows by itself but never shrinks back).
    @State private var popoverWindow: NSWindow?

    private var isWindow: Bool { presentation == .window }
    private var width: CGFloat { isWindow ? 680 : 330 }
    private var inset: CGFloat { isWindow ? 20 : 14 }
    private var columnWidth: CGFloat { (width - 2 * inset - 20) / 2 }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, inset)
                .padding(.vertical, 10)
            Divider()
            content
                .padding(.horizontal, inset)
                .padding(.vertical, 12)
            Divider()
            footer
                .padding(.horizontal, inset)
                .padding(.vertical, 8)
        }
        .frame(width: width)
        .background(shortcuts)
        .background(isWindow ? WindowConfigurator(keepOnTop: keepOnTop) : nil)
        .background(isWindow ? nil : HostWindowReader(window: $popoverWindow))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if !isWindow { fitPopover(to: size) }
        }
        .toolbar {
            if isWindow {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $keepOnTop) {
                        Label("Keep on Top", systemImage: keepOnTop ? "pin.fill" : "pin")
                            .labelStyle(.titleAndIcon)
                    }
                    .toggleStyle(.button)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .help("Keep this window above other apps (⌥⌘T)")
                }
            }
        }
        .onAppear {
            model.viewAppeared()
            model.setPreview(enabled: livePreview)
            if isWindow {
                // Give the window a Dock icon and menu bar while it's open.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onDisappear {
            model.viewDisappeared()
            if isWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .onChange(of: livePreview) { _, enabled in
            model.setPreview(enabled: enabled)
        }
    }

    /// Resize the popover's window to the content, keeping its top edge under the
    /// menu bar. SwiftUI grows the MenuBarExtra window when content gets taller but
    /// leaves it as is when content gets shorter, which showed up as an empty band
    /// above the panel after hiding the preview.
    private func fitPopover(to size: CGSize) {
        guard let window = popoverWindow, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let frame = window.frame
        guard abs(frame.height - target.height) > 0.5 || abs(frame.width - target.width) > 0.5 else { return }
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - target.height,
                               width: target.width, height: target.height),
                        display: true)
    }

    private func openAsWindow() {
        openWindow(id: LensControlApp.windowID)
        popoverWindow?.close()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            ProgressView()
                .controlSize(.mini)
                .opacity(model.busy || model.connection == .unknown ? 1 : 0)
                .help("Talking to camera…")
            if model.connection == .connected {
                if let percent = model.batteryPercent {
                    HStack(spacing: 4) {
                        Text("\(percent)%")
                        Image(systemName: batterySymbol(percent))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Camera battery \(percent)%")
                }
                if let mode = model.exposureMode {
                    Text(mode)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .frame(minWidth: 24, minHeight: 20)
                        .modifier(GlassCapsule())
                        .help(model.exposureModeTip)
                }
                Button {
                    model.autofocus()
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.borderless)
                .help("Autofocus now (one AF cycle)")
                .accessibilityLabel("Autofocus now")
                Button {
                    livePreview.toggle()
                } label: {
                    Image(systemName: livePreview ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(livePreview ? "Hide live preview" : "Show live preview (USB live view, 640×360)")
            }
        }
    }

    private var title: String {
        switch model.connection {
        case .connected: return model.fullModelName
        case .unknown: return "Connecting…"
        case .noCamera: return "No camera connected"
        }
    }

    private var subtitle: String {
        switch model.connection {
        case .connected: return model.lensDescription
        case .unknown: return "Looking for a camera on USB"
        case .noCamera: return "Waiting for USB"
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch model.connection {
        case .noCamera:
            noCamera
        case .unknown:
            ProgressView("Reading camera…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .connected:
            VStack(alignment: .leading, spacing: 12) {
                if isWindow {
                    GlassGroup {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                                exposure
                                whiteBalance
                            }
                            .frame(width: columnWidth)
                            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                                if livePreview { PreviewView(width: columnWidth) }
                                focusAndAudio
                                PresetsListSection()
                            }
                            .frame(width: columnWidth)
                        }
                    }
                } else {
                    GlassGroup {
                        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                            if livePreview { PreviewView(width: width - 2 * inset) }
                            exposure
                            whiteBalance
                            focusAndAudio
                            PresetsSection()
                        }
                    }
                }
                if let error = model.errorMessage {
                    WarningBanner(message: error) { model.errorMessage = nil }
                }
            }
        }
    }

    private var noCamera: some View {
        VStack(spacing: 6) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("No camera found")
                .font(.system(size: 13, weight: .semibold))
            Text("Turn the camera on and check the cable.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("LensControl also checks every 2 s.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button("Try Again") { Task { await model.refresh() } }
                .controlSize(.small)
                .padding(.top, 6)
            if let error = model.errorMessage {
                WarningBanner(message: error) { model.errorMessage = nil }
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - Sections

    private var exposure: some View {
        FormSection(title: "Exposure", symbol: "sun.max") {
            if let entry = model["movieshutterspeed"] {
                FormRow(label: "Shutter") {
                    ChoicePopup(entry: entry, readOnlyTip: model.shutterReadOnlyTip) { model.select("movieshutterspeed", choice: $0) }
                }
            }
            if let entry = model["movief-number"] {
                FormRow(label: "Aperture") {
                    ChoicePopup(entry: entry, readOnlyTip: model.apertureReadOnlyTip) { model.select("movief-number", choice: $0) }
                        .help("Range depends on the mounted lens")
                }
            }
            if let entry = model["movieiso"] {
                FormRow(label: "ISO") {
                    ChoicePopup(entry: entry) { model.select("movieiso", choice: $0) }
                }
            }
            if let entry = model["d0ad"] {
                FormRow(label: "Auto ISO") {
                    Toggle("Auto ISO", isOn: Binding(
                        get: { entry.current == "1" },
                        set: { model.select("d0ad", choice: $0 ? "1" : "0") }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(entry.readOnly)
                    .help("Auto ISO control (mode M)")
                }
            }
            if model["d0ad"]?.current == "1", let entry = model["d0ae"] {
                FormRow(label: "Max ISO") {
                    ChoicePopup(entry: entry) { model.select("d0ae", choice: $0) }
                }
            }
            if let entry = model["movieexposurecompensation"], entry.choices.count > 1 {
                FormRow(label: "EV", alignment: .top) {
                    EVSlider(count: entry.choices.count,
                             index: entry.currentIndex ?? entry.choices.count / 2) { index in
                        model.select("movieexposurecompensation", choice: entry.choices[index])
                    }
                    .disabled(entry.readOnly)
                }
            }
        }
    }

    private var whiteBalance: some View {
        FormSection(title: "White balance", symbol: "camera.filters") {
            if let entry = model["d23a"] {
                FormRow(label: "Mode") {
                    ChoicePopup(entry: entry, names: CameraModel.movieWhiteBalanceNames) { model.select("d23a", choice: $0) }
                }
            }
            if model["d23a"]?.current == CameraModel.colourTemperatureCode,
               let entry = model["d21a"], entry.kind == .range,
               let low = entry.bottom, let high = entry.top {
                FormRow(label: "Kelvin", alignment: .top) {
                    KelvinControl(value: Double(entry.current) ?? low, range: low...high, step: entry.step ?? 10) {
                        model.setValue("d21a", $0)
                    }
                    .disabled(entry.readOnly)
                }
            }
        }
    }

    private var focusAndAudio: some View {
        FormSection(title: "Focus & audio", symbol: "scope") {
            if let entry = model["liveviewaffocus"] {
                FormRow(label: "AF mode") {
                    SegmentedChoice(entry: entry, options: [
                        ("Single-servo AF", "AF-S"),
                        ("Continuous-servo AF", "AF-F"),
                        ("Manual Focus (selection)", "Manual"),
                    ]) { model.select("liveviewaffocus", choice: $0) }
                }
            }
            if let entry = model["microphone"] {
                FormRow(label: "Mic") {
                    SegmentedChoice(entry: entry, options: [
                        ("Auto sensitivity", "Auto"),
                        ("High sensitivity", "High"),
                        ("Medium sensitivity", "Medium"),
                    ]) { model.select("microphone", choice: $0) }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(updatedText(now: context.date))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isWindow {
                Button("Open as Window") { openAsWindow() }
                    .keyboardShortcut("o")
                    .help("Open as Window (⌘O)")
            }
            Button("Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")
            if !isWindow {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .help("Quit LensControl (⌘Q)")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
    }

    private func updatedText(now: Date) -> String {
        switch model.connection {
        case .unknown: return "Reading camera…"
        case .noCamera: return "Not connected"
        case .connected:
            guard let last = model.lastRefresh else { return "" }
            let seconds = max(0, Int(now.timeIntervalSince(last)))
            if seconds < 2 { return "Updated just now" }
            if seconds < 60 { return "Updated \(seconds) s ago" }
            return "Updated \(seconds / 60) min ago"
        }
    }

    /// ⌘1–⌘9 apply presets in order (invisible buttons carry the shortcuts).
    private var shortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("Preset \(number)") { model.applyPreset(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// The camera's USB live view, 16:9, with a placeholder until the first frame lands.
/// Reads the frame straight from the model so only this view re-renders per
/// frame, and hands the CGImage to a CALayer — far cheaper than diffing a
/// SwiftUI `Image` twenty times a second.
struct PreviewView: View {
    @Environment(CameraModel.self) private var model
    let width: CGFloat

    var body: some View {
        ZStack {
            if let image = model.previewImage {
                FrameLayerView(image: image)
            } else {
                VStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(model.previewError ?? "Starting live view…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(width: width, height: (width * 9 / 16).rounded())
        .background(.black, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// A layer whose contents is the current frame; aspect-fit, black letterboxing.
struct FrameLayerView: NSViewRepresentable {
    let image: CGImage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.contents = image
    }
}

/// Hands the hosting NSWindow back to SwiftUI once the view is in a window.
struct HostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let host = view.window, host !== window {
            DispatchQueue.main.async { window = host }
        }
    }
}

/// Reaches the hosting NSWindow to toggle "keep on top" (window level).
struct WindowConfigurator: NSViewRepresentable {
    let keepOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view.window)
    }

    private func configure(_ window: NSWindow?) {
        window?.level = keepOnTop ? .floating : .normal
    }
}
