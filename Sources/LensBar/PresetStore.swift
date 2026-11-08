import Foundation
import Observation

/// A named snapshot of the camera's writable settings.
struct Preset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// gphoto2 key → value as the panel shows it (a RADIO choice or a RANGE number).
    var values: [String: String]
}

/// Presets persisted as JSON in ~/Library/Application Support/LensBar/presets.json.
@MainActor @Observable
final class PresetStore {
    private(set) var presets: [Preset] = []
    private(set) var lastError: String?
    let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("LensBar/presets.json")
        // Presets saved while the app was still called "Camera Settings" come along.
        let legacy = support.appendingPathComponent("CameraSettings/presets.json")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: url)
        }
        return url
    }

    init(fileURL: URL = PresetStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func preset(id: UUID?) -> Preset? {
        presets.first { $0.id == id }
    }

    @discardableResult
    func add(name: String, values: [String: String]) -> Preset {
        let preset = Preset(name: name, values: values)
        presets.append(preset)
        save()
        return preset
    }

    func update(id: UUID, values: [String: String]) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].values = values
        save()
    }

    func rename(id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
        save()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    /// A name that doesn't collide with an existing preset ("Preset 3").
    func suggestedName() -> String {
        var number = presets.count + 1
        while presets.contains(where: { $0.name == "Preset \(number)" }) { number += 1 }
        return "Preset \(number)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            presets = try JSONDecoder().decode([Preset].self, from: data)
        } catch {
            lastError = "Could not read presets: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(presets).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Could not save presets: \(error.localizedDescription)"
        }
    }
}
