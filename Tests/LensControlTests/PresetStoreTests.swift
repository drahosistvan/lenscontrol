import XCTest
@testable import LensControl

@MainActor
final class PresetStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LensControlTests-\(UUID().uuidString)/presets.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testRoundTripsThroughDisk() {
        let store = PresetStore(fileURL: fileURL)
        let preset = store.add(name: "Desk", values: ["movieiso": "400", "d01e": "5000"])
        store.add(name: "Evening", values: ["movieiso": "1600"])
        store.rename(id: preset.id, to: "Daylight desk")

        let reloaded = PresetStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.presets.map(\.name), ["Daylight desk", "Evening"])
        XCTAssertEqual(reloaded.presets[0].values, ["movieiso": "400", "d01e": "5000"])
        XCTAssertEqual(reloaded.presets[0].id, preset.id)
        XCTAssertNil(reloaded.lastError)
    }

    func testUpdateAndDelete() {
        let store = PresetStore(fileURL: fileURL)
        let preset = store.add(name: "A", values: ["movieiso": "400"])
        store.update(id: preset.id, values: ["movieiso": "800"])
        XCTAssertEqual(store.preset(id: preset.id)?.values["movieiso"], "800")

        store.delete(id: preset.id)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertEqual(PresetStore(fileURL: fileURL).presets.count, 0)
    }

    func testSuggestedNameSkipsTakenNames() {
        let store = PresetStore(fileURL: fileURL)
        XCTAssertEqual(store.suggestedName(), "Preset 1")
        store.add(name: "Preset 2", values: [:])
        XCTAssertEqual(store.suggestedName(), "Preset 3")
    }
}
