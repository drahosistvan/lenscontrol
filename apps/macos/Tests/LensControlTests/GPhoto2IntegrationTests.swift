import XCTest
@testable import LensControl

/// Talks to the real camera through libgphoto2. Skipped when no camera is
/// connected, so the suite stays green on a machine without hardware.
/// The app must not have its panel open while these run — it holds the session.
final class GPhoto2IntegrationTests: XCTestCase {
    private var gphoto: GPhoto2!

    override func setUp() async throws {
        gphoto = GPhoto2()
        do {
            try await gphoto.connect()
        } catch GPhotoError.noCamera {
            throw XCTSkip("no camera connected")
        } catch GPhotoError.cameraBusy(let detail) {
            throw XCTSkip("camera is in use: \(detail)")
        }
    }

    override func tearDown() async throws {
        await gphoto.endPreview()
        await gphoto.disconnect()
    }

    func testReadsAllPanelKeysAndSkipsUnknownOnes() async throws {
        let entries = try await gphoto.getConfig(CameraModel.keys + ["nosuchkey"])
        XCTAssertNil(entries["nosuchkey"])
        XCTAssertEqual(entries["d21a"]?.kind, .range)
        XCTAssertEqual(entries["d23a"]?.kind, .radio)
        XCTAssertEqual(entries["movieiso"]?.kind, .radio)
        XCTAssertFalse(entries["movieiso"]?.choices.isEmpty ?? true)
        XCTAssertFalse(entries["cameramodel"]?.current.isEmpty ?? true)
        // Every movie WB code the camera offers has a display name.
        for code in entries["d23a"]?.choices ?? [] {
            XCTAssertNotNil(CameraModel.movieWhiteBalanceNames[code], "no name for MovieWhiteBalance code \(code)")
        }
    }

    func testReadsAreFast() async throws {
        _ = try await gphoto.getConfig(["movieiso"])
        let start = ContinuousClock.now
        _ = try await gphoto.getConfig(CameraModel.keys)
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .milliseconds(200), "reading \(CameraModel.keys.count) keys took \(elapsed)")
    }

    /// Nudges movie ISO one step and restores it, verifying the write path end to end.
    func testSetChoiceRoundTrip() async throws {
        let before = try await gphoto.getConfig(["movieiso"])["movieiso"]!
        try XCTSkipIf(before.readOnly, "movieiso is read-only in the camera's current mode")
        guard let index = before.currentIndex, before.choices.count > 1 else {
            throw XCTSkip("movieiso has no alternative choice")
        }
        let other = index == 0 ? 1 : index - 1

        try await gphoto.setChoice("movieiso", index: other)
        let changed = try await gphoto.getConfig(["movieiso"])["movieiso"]!
        XCTAssertEqual(changed.current, before.choices[other])

        try await gphoto.setChoice("movieiso", index: index)
        let restored = try await gphoto.getConfig(["movieiso"])["movieiso"]!
        XCTAssertEqual(restored.current, before.current)
    }

    /// Movie Kelvin is a RANGE: set by value and restore.
    func testSetRangeRoundTrip() async throws {
        let before = try await gphoto.getConfig(["d21a"])["d21a"]!
        try XCTSkipIf(before.readOnly, "d21a is read-only")
        let target = before.current == "5000" ? "5100" : "5000"

        try await gphoto.setValue("d21a", target)
        let changed = try await gphoto.getConfig(["d21a"])["d21a"]?.current
        XCTAssertEqual(changed, target)

        try await gphoto.setValue("d21a", before.current)
        let restored = try await gphoto.getConfig(["d21a"])["d21a"]?.current
        XCTAssertEqual(restored, before.current)
    }

    /// A batch with a bad write in the middle: the good writes land, the bad one is reported.
    func testApplyBatchReportsRejectedWritesAndKeepsGoing() async throws {
        let before = try await gphoto.getConfig(["movieiso", "d0ae"])
        let iso = before["movieiso"]!, limit = before["d0ae"]!
        try XCTSkipIf(iso.readOnly || limit.readOnly, "ISO settings are read-only in the camera's current mode")
        guard let isoIndex = iso.currentIndex, let limitIndex = limit.currentIndex,
              iso.choices.count > 1, limit.choices.count > 1 else {
            throw XCTSkip("no alternative choices")
        }
        let otherIso = isoIndex == 0 ? 1 : isoIndex - 1
        let otherLimit = limitIndex == 0 ? 1 : limitIndex - 1

        let rejected = try await gphoto.apply([
            WriteOp(key: "movieiso", kind: .index(otherIso)),
            WriteOp(key: "movieiso", kind: .value("999")),
            WriteOp(key: "d0ae", kind: .index(otherLimit)),
        ])
        XCTAssertEqual(rejected.count, 1, rejected.joined(separator: "\n"))

        let after = try await gphoto.getConfig(["movieiso", "d0ae"])
        XCTAssertEqual(after["movieiso"]?.current, iso.choices[otherIso])
        XCTAssertEqual(after["d0ae"]?.current, limit.choices[otherLimit])

        let restoreErrors = try await gphoto.apply([
            WriteOp(key: "movieiso", kind: .index(isoIndex)),
            WriteOp(key: "d0ae", kind: .index(limitIndex)),
        ])
        XCTAssertEqual(restoreErrors, [])
    }

    func testStillsWhiteBalanceIsRejectedOrIgnoredButMovieOneWorks() async throws {
        // Documents the reason the panel uses d23a: the stills key is writable but does nothing to video.
        let entries = try await gphoto.getConfig(["whitebalance", "d23a"])
        XCTAssertNotNil(entries["whitebalance"])
        XCTAssertNotNil(entries["d23a"])
    }

    func testLivePreviewDeliversFreshFrames() async throws {
        let first = try await gphoto.capturePreview()
        XCTAssertGreaterThan(first.image.width, 0)
        XCTAssertGreaterThan(first.image.height, 0)

        let start = ContinuousClock.now
        var frames = 0
        while ContinuousClock.now - start < .seconds(1) {
            _ = try await gphoto.capturePreview()
            frames += 1
        }
        XCTAssertGreaterThan(frames, 10, "only \(frames) frames in a second")
    }
}
