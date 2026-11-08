import XCTest
@testable import LensBar

/// Pure logic — no camera needed.
final class CameraModelTests: XCTestCase {

    private let entries: [String: ConfigEntry] = [
        "d23a": ConfigEntry(label: "MovieWhiteBalance", kind: .radio, current: "2",
                            choices: ["2", "4", "5", "6", "32784", "32785", "32786", "32787", "32789", "32790"]),
        "d21a": ConfigEntry(label: "MovieWbColorTemp", kind: .range, current: "4000", bottom: 2500, top: 10000, step: 10),
        "movieiso": ConfigEntry(label: "Movie ISO Speed", kind: .radio, current: "500", choices: ["100", "200", "400", "500", "800"]),
        "movief-number": ConfigEntry(label: "Movie F-Number", kind: .radio, current: "f/2", choices: ["f/2", "f/2.8", "f/4"]),
        "movieshutterspeed": ConfigEntry(label: "Movie Shutter Speed 2", readOnly: true, kind: .radio, current: "1/125", choices: ["1/60", "1/125"]),
    ]

    func testPlanWritesOnlyWhatDiffersInPresetKeyOrder() {
        let preset = Preset(name: "Desk", values: [
            "d23a": "32786", "d21a": "5600", "movieiso": "500", "movief-number": "f/2.8",
        ])
        let plan = CameraModel.planWrites(for: preset, entries: entries)
        XCTAssertEqual(plan.ops, [
            WriteOp(key: "d23a", kind: .index(6)),
            WriteOp(key: "d21a", kind: .value("5600")),
            WriteOp(key: "movief-number", kind: .index(1)),
        ])
        XCTAssertEqual(plan.problems, [])
    }

    func testPlanReportsReadOnlyAndMissingChoices() {
        let preset = Preset(name: "Odd", values: [
            "movieshutterspeed": "1/60",   // read-only right now
            "movief-number": "f/1.8",      // lens doesn't offer it
            "microphone": "High",          // camera doesn't expose the key at all → silently skipped
        ])
        let plan = CameraModel.planWrites(for: preset, entries: entries)
        XCTAssertEqual(plan.ops, [])
        XCTAssertEqual(plan.problems, [
            "Movie Shutter Speed 2 is read-only in the camera's current mode",
            "Movie F-Number: f/1.8 is not available",
        ])
    }

    func testMovieWhiteBalanceNamesCoverTheZ5IIList() {
        for code in entries["d23a"]!.choices {
            XCTAssertNotNil(CameraModel.movieWhiteBalanceNames[code], code)
        }
        XCTAssertEqual(CameraModel.movieWhiteBalanceNames[CameraModel.colourTemperatureCode], "Colour temperature")
    }

    @MainActor
    func testModelNameAndBattery() {
        let model = CameraModel(presets: PresetStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraModelTests-\(UUID().uuidString).json")))
        XCTAssertEqual(model.modelName, "Camera")
        XCTAssertNil(model.batteryPercent)
    }
}
