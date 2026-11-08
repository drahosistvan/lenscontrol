import CoreGraphics
import Foundation
import Observation

/// UI-facing state for the camera. Reads everything the panel shows in one
/// pass, applies edits optimistically, and re-reads after each write so the
/// panel always converges on what the camera actually accepted.
@MainActor @Observable
final class CameraModel {
    enum Connection: Equatable {
        case unknown, connected, noCamera
    }

    /// Everything the panel displays. The Z5 II keeps separate stills and movie
    /// settings and only the movie ones affect the HDMI/webcam feed, so the movie
    /// properties are used throughout — several have no friendly libgphoto2 name
    /// and are addressed by raw PTP code:
    ///   d23a  MovieWhiteBalance      (the named `whitebalance` is the stills one)
    ///   d21a  MovieWbColorTemp, Kelvin (`d01e` is the stills one)
    ///   d0ad  MovISOAutoControl — "Auto ISO control (mode M)" in the video menu
    ///   d0ae  MovISOAutoHighLimit — its maximum sensitivity
    nonisolated static let keys = [
        "manufacturer", "cameramodel", "deviceversion", "batterylevel", "expprogram",
        "minfocallength", "maxfocallength", "apertureatminfocallength", "apertureatmaxfocallength",
        "movieshutterspeed", "movief-number", "movieiso", "d0ad", "d0ae", "movieexposurecompensation",
        "d23a", "d21a",
        "liveviewaffocus", "microphone",
    ]

    /// Keys a preset captures, in apply order: mode-like settings first so the
    /// values that depend on them (Kelvin, max ISO) land on a camera ready for them.
    nonisolated static let presetKeys = [
        "d23a", "d21a",
        "d0ad", "d0ae", "movieiso",
        "movieshutterspeed", "movief-number", "movieexposurecompensation",
        "liveviewaffocus", "microphone",
    ]

    /// Display names for the raw MovieWhiteBalance codes (PTP white-balance values).
    /// 32789 only exists in the movie list; it is taken to be the video menu's
    /// "Same as photo settings" entry.
    nonisolated static let movieWhiteBalanceNames: [String: String] = [
        "2": "Auto",
        "4": "Direct sunlight",
        "5": "Fluorescent",
        "6": "Incandescent",
        "7": "Flash",
        "32784": "Cloudy",
        "32785": "Shade",
        "32786": "Colour temperature",
        "32787": "Preset manual",
        "32789": "Same as photo settings",
        "32790": "Natural light auto",
    ]
    nonisolated static let colourTemperatureCode = "32786"

    private(set) var entries: [String: ConfigEntry] = [:]
    private(set) var connection: Connection = .unknown
    private(set) var busy = false
    private(set) var lastRefresh: Date?
    var errorMessage: String?

    private(set) var previewImage: CGImage?
    private(set) var previewError: String?
    var isPreviewing: Bool { previewTask != nil }

    let presets: PresetStore
    /// The preset last applied or saved — what Update/Rename/Delete act on.
    var selectedPresetID: UUID?

    private let gphoto = GPhoto2()
    private var pollTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var visibleViews = 0
    /// Bumped on every write so an in-flight refresh started before the write
    /// can't clobber the optimistic value with a stale read.
    private var generation = 0

    init(presets: PresetStore? = nil) {
        self.presets = presets ?? PresetStore()
    }

    subscript(key: String) -> ConfigEntry? { entries[key] }

    var modelName: String {
        guard let raw = entries["cameramodel"]?.current, !raw.isEmpty else { return "Camera" }
        // Nikon reports e.g. "Z5_2" for the Z5 II.
        return raw.replacingOccurrences(of: "_2", with: " II").replacingOccurrences(of: "_", with: " ")
    }

    /// "Nikon Z5 II".
    var fullModelName: String {
        let maker = entries["manufacturer"]?.current.split(separator: " ").first.map(String.init) ?? ""
        return maker.isEmpty ? modelName : "\(maker) \(modelName)"
    }

    var batteryPercent: Int? {
        guard let text = entries["batterylevel"]?.current else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    /// Header subtitle, e.g. "40 mm f/2 · USB" or "24–70 mm f/4 · USB".
    /// PTP doesn't carry the lens name, so it's built from the focal range and
    /// maximum aperture.
    var lensDescription: String { Self.lensDescription(entries) }

    nonisolated static func lensDescription(_ entries: [String: ConfigEntry]) -> String {
        func number(_ key: String) -> String? {
            guard let raw = entries[key]?.current else { return nil }
            let digits = raw.replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)
            guard let value = Double(digits), value > 0 else { return nil }
            return value == value.rounded() ? String(Int(value)) : String(value)
        }
        var parts: [String] = []
        if let wide = number("minfocallength") {
            let tele = number("maxfocallength") ?? wide
            var lens = wide == tele ? "\(wide) mm" : "\(wide)–\(tele) mm"
            if let fastWide = number("apertureatminfocallength") {
                let fastTele = number("apertureatmaxfocallength") ?? fastWide
                lens += fastWide == fastTele ? " f/\(fastWide)" : " f/\(fastWide)–\(fastTele)"
            }
            parts.append(lens)
        }
        parts.append("USB")
        return parts.joined(separator: " · ")
    }

    /// Mode-dial position ("M", "A", "S", "P", …).
    var exposureMode: String? {
        guard let mode = entries["expprogram"]?.current, !mode.isEmpty else { return nil }
        return mode
    }

    var exposureModeTip: String {
        let names = ["M": "Manual", "A": "Aperture priority", "S": "Shutter priority", "P": "Programmed auto", "Auto": "Auto"]
        let mode = exposureMode ?? "?"
        return "Mode dial: \(mode)\(names[mode].map { " (\($0))" } ?? ""). Change it on the camera."
    }

    var shutterReadOnlyTip: String {
        "Shutter is chosen by the camera in \(exposureMode ?? "this") mode. Turn the mode dial to M or S to set it here."
    }

    var apertureReadOnlyTip: String {
        "Aperture is chosen by the camera in \(exposureMode ?? "this") mode. Turn the mode dial to M or A to set it here."
    }

    // MARK: - Reading

    func refresh() async {
        let startedAt = generation
        busy = true
        defer { busy = false }
        do {
            let fetched = try await gphoto.getConfig(Self.keys)
            // A write happened meanwhile; its own follow-up refresh carries the truth.
            guard startedAt == generation else { return }
            entries = fetched
            connection = .connected
            errorMessage = nil
            lastRefresh = .now
        } catch {
            handle(error)
        }
    }

    /// The popover and the window both show the model. Poll while at least one
    /// is on screen; release the camera when neither is.
    func viewAppeared() {
        visibleViews += 1
        if visibleViews == 1 { startPolling() }
    }

    func viewDisappeared() {
        visibleViews = max(0, visibleViews - 1)
        if visibleViews == 0 {
            stopPolling()
            setPreview(enabled: false)
            Task { await gphoto.disconnect() }
        }
    }

    func startPolling(every interval: Duration = .seconds(2)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Releases the camera; called before the app exits so live view is left off.
    func shutdown() async {
        stopPolling()
        previewTask?.cancel()
        previewTask = nil
        await gphoto.endPreview()
        await gphoto.disconnect()
    }

    // MARK: - Live view

    func setPreview(enabled: Bool) {
        if enabled {
            guard previewTask == nil else { return }
            previewTask = Task { [weak self] in await self?.previewLoop() }
        } else {
            guard previewTask != nil else { return }
            previewTask?.cancel()
            previewTask = nil
            previewImage = nil
            previewError = nil
            Task { await gphoto.endPreview() }
        }
    }

    /// Pulls frames at up to ~20 fps; the camera delivers ~29, and each frame is
    /// a 40 KB USB transfer plus a JPEG decode, so a little restraint is cheap.
    private func previewLoop() async {
        let minimumInterval: Duration = .milliseconds(50)
        while !Task.isCancelled {
            let started = ContinuousClock.now
            do {
                let frame = try await gphoto.capturePreview()
                guard !Task.isCancelled else { break }
                previewImage = frame.image
                previewError = nil
                if connection != .connected { connection = .connected }
            } catch {
                handle(error)
                previewError = error.localizedDescription
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let elapsed = ContinuousClock.now - started
            if elapsed < minimumInterval {
                try? await Task.sleep(for: minimumInterval - elapsed)
            }
        }
    }

    // MARK: - Writing

    /// Sets a RADIO entry to one of its choices.
    func select(_ key: String, choice: String) {
        guard let entry = entries[key],
              entry.current != choice,
              let index = entry.choices.firstIndex(of: choice) else { return }
        entries[key]?.current = choice
        perform { try await $0.setChoice(key, index: index) }
    }

    /// Sets a RANGE entry, e.g. WB Kelvin.
    func setValue(_ key: String, _ value: Double) {
        guard let entry = entries[key], entry.kind == .range else { return }
        let text = value.rounded() == value ? String(Int(value)) : String(value)
        guard entry.current != text else { return }
        entries[key]?.current = text
        perform { try await $0.setValue(key, text) }
    }

    /// Drives one autofocus cycle (Nikon "AF drive").
    func autofocus() {
        perform { try await $0.setValue("autofocusdrive", "1") }
    }

    private func perform(_ operation: @escaping @Sendable (GPhoto2) async throws -> Void) {
        generation += 1
        Task {
            busy = true
            do {
                try await operation(gphoto)
                errorMessage = nil
            } catch {
                handle(error)
            }
            busy = false
            // Re-read regardless: on failure this reverts the optimistic value,
            // on success it picks up side effects (e.g. WB mode changing other fields).
            await refresh()
        }
    }

    private func handle(_ error: Error) {
        switch error {
        case GPhotoError.noCamera:
            connection = .noCamera
            entries = [:]
        default:
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Presets

    /// The current camera values for every preset key the camera exposes.
    var currentValues: [String: String] {
        Dictionary(uniqueKeysWithValues: Self.presetKeys.compactMap { key in
            entries[key].map { (key, $0.current) }
        })
    }

    /// True when every value the preset stores matches the camera right now.
    func matches(_ preset: Preset) -> Bool {
        guard connection == .connected else { return false }
        return preset.values.allSatisfy { key, value in
            entries[key].map { $0.current == value } ?? true
        }
    }

    var activePreset: Preset? {
        presets.presets.first(where: matches)
    }

    /// Saves the camera's current values; an existing preset with the same name
    /// (ignoring case) is overwritten rather than duplicated.
    func saveCurrentPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? presets.suggestedName() : trimmed
        if let existing = presets.presets.first(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            updatePreset(existing.id)
            return
        }
        let preset = presets.add(name: finalName, values: currentValues)
        selectedPresetID = preset.id
    }

    func renamePreset(_ id: UUID, to name: String) {
        presets.rename(id: id, to: name)
        selectedPresetID = id
    }

    /// ⌘1…⌘9.
    func applyPreset(number: Int) {
        let list = presets.presets
        guard number >= 1, number <= list.count else { return }
        apply(list[number - 1])
    }

    func updatePreset(_ id: UUID) {
        presets.update(id: id, values: currentValues)
        selectedPresetID = id
    }

    func deletePreset(_ id: UUID) {
        presets.delete(id: id)
        if selectedPresetID == id { selectedPresetID = nil }
    }

    /// Writes every value in the preset that differs from the camera. Values the
    /// camera can't take right now (read-only in this mode, or a choice the mounted
    /// lens doesn't offer) are reported, not fatal.
    func apply(_ preset: Preset) {
        selectedPresetID = preset.id
        let plan = Self.planWrites(for: preset, entries: entries)
        for op in plan.ops {
            if case .index(let index) = op.kind, let choice = entries[op.key]?.choices[index] {
                entries[op.key]?.current = choice
            } else if case .value(let value) = op.kind {
                entries[op.key]?.current = value
            }
        }
        guard !plan.ops.isEmpty else {
            errorMessage = plan.problems.isEmpty ? nil : plan.problems.joined(separator: "\n")
            return
        }
        perform { gphoto in
            let rejected = try await gphoto.apply(plan.ops)
            let all = plan.problems + rejected
            if !all.isEmpty { throw GPhotoError.failed(all.joined(separator: "\n")) }
        }
    }

    /// Works out which writes a preset needs against the camera's current state.
    nonisolated static func planWrites(for preset: Preset, entries: [String: ConfigEntry]) -> (ops: [WriteOp], problems: [String]) {
        var ops: [WriteOp] = []
        var problems: [String] = []
        for key in presetKeys {
            guard let target = preset.values[key], let entry = entries[key], entry.current != target else { continue }
            if entry.readOnly {
                problems.append("\(entry.label) is read-only in the camera's current mode")
                continue
            }
            switch entry.kind {
            case .radio:
                guard let index = entry.choices.firstIndex(of: target) else {
                    problems.append("\(entry.label): \(target) is not available")
                    continue
                }
                ops.append(WriteOp(key: key, kind: .index(index)))
            default:
                ops.append(WriteOp(key: key, kind: .value(target)))
            }
        }
        return (ops, problems)
    }
}
