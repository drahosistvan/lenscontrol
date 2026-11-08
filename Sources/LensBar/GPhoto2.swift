import CGPhoto2
import CoreGraphics
import Foundation
import ImageIO

/// One camera setting as libgphoto2 describes it.
struct ConfigEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case radio, range, text, toggle, date
        case other(String)
    }

    var label = ""
    var readOnly = false
    var kind: Kind = .other("")
    var current = ""
    /// RADIO/MENU choices in index order.
    var choices: [String] = []
    /// RANGE bounds.
    var bottom: Double?
    var top: Double?
    var step: Double?

    var currentIndex: Int? { choices.firstIndex(of: current) }
}

/// One write in a batch.
struct WriteOp: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case index(Int)
        case value(String)
    }

    var key: String
    var kind: Kind
}

/// A decoded live-view frame. CGImage is immutable, so handing it across actors is safe.
struct PreviewFrame: @unchecked Sendable {
    let image: CGImage
}

enum GPhotoError: LocalizedError, Equatable {
    case noCamera
    case cameraBusy(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noCamera: return "No camera detected on USB"
        case .cameraBusy: return "Another app holds the camera — quit Lightroom, Photos or Image Capture and retry"
        case .failed(let message): return message
        }
    }
}

/// Talks to the camera through libgphoto2 in-process.
///
/// One PTP session is opened on first use and kept open (a read or write takes
/// ~2 ms, a live-view frame ~35 ms) until `disconnect()`; the model calls that
/// whenever nothing is on screen so the `gphoto2` CLI can still be used alongside.
/// libgphoto2 is not thread-safe, so every call runs on this actor's own serial
/// queue — never on the shared cooperative pool, which blocking USB I/O would stall.
actor GPhoto2 {
    private let queue = DispatchSerialQueue(label: "hu.isti.lensbar.gphoto2", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var context: OpaquePointer?
    private var camera: UnsafeMutablePointer<Camera>?
    private var previewFile: OpaquePointer?

    /// libgphoto2 reports the PTP-level reason ("PTP Access Denied") through the
    /// context error callback, not the return code; the callback stashes it here.
    nonisolated(unsafe) private static var lastContextError = ""

    var isConnected: Bool { camera != nil }

    // MARK: - Session

    func connect() throws {
        if camera != nil { return }
        let context = self.context ?? makeContext()
        var fresh: UnsafeMutablePointer<Camera>? = nil
        gp_camera_new(&fresh)
        var ret = gp_camera_init(fresh, context)
        if ret == GP_ERROR_MODEL_NOT_FOUND {
            // Right after a session closes the camera can be missing from the
            // bus for a moment while it re-enumerates; look once more.
            Thread.sleep(forTimeInterval: 0.4)
            Self.lastContextError = ""
            ret = gp_camera_init(fresh, context)
        }
        if ret == GP_ERROR_IO_USB_CLAIM, Self.evictPTPCameraDaemon() {
            // macOS's Image Capture daemon grabs any idle PTP camera; it runs as
            // the user and stays away once killed, so take the camera back.
            Self.lastContextError = ""
            ret = gp_camera_init(fresh, context)
        }
        guard ret >= 0 else {
            gp_camera_free(fresh)
            throw error(ret, "connect")
        }
        camera = fresh
    }

    /// Stops macOS's Image Capture PTP daemon if it holds the camera. Both it and
    /// its ImageCaptureCore client (`mscamerad-xpc`) run as the user and ignore
    /// SIGTERM, and SIP forbids `launchctl bootout`, so they get SIGKILL; with the
    /// client gone launchd leaves `ptpcamerad` down until the next camera plug-in.
    /// Returns true when there was a daemon to remove.
    private static func evictPTPCameraDaemon() -> Bool {
        guard run("/usr/bin/pgrep", ["-x", "ptpcamerad"]) == 0 else { return false }
        _ = run("/usr/bin/pkill", ["-9", "-x", "mscamerad-xpc"])
        _ = run("/usr/bin/pkill", ["-9", "-x", "ptpcamerad"])
        Thread.sleep(forTimeInterval: 1.0)
        return true
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    func disconnect() {
        if let previewFile {
            gp_file_unref(previewFile)
            self.previewFile = nil
        }
        if let camera {
            gp_camera_exit(camera, context)
            gp_camera_free(camera)
            self.camera = nil
        }
    }

    private func makeContext() -> OpaquePointer {
        let context = gp_context_new()!
        gp_context_set_error_func(context, { _, text, _ in
            if let text { GPhoto2.lastContextError = String(cString: text) }
        }, nil)
        self.context = context
        return context
    }

    // MARK: - Config

    /// Reads several settings. Keys the camera doesn't expose in its current
    /// mode are simply left out of the result.
    func getConfig(_ keys: [String]) throws -> [String: ConfigEntry] {
        try connect()
        var result: [String: ConfigEntry] = [:]
        for key in keys {
            var widget: OpaquePointer? = nil
            let ret = gp_camera_get_single_config(camera, key, &widget, context)
            if ret == GP_ERROR_BAD_PARAMETERS { continue }
            guard ret >= 0, let widget else { throw error(ret, key) }
            defer { gp_widget_free(widget) }
            result[key] = Self.entry(from: widget)
        }
        return result
    }

    /// Selects a RADIO/MENU choice by index.
    func setChoice(_ key: String, index: Int) throws {
        try connect()
        try update(key) { widget in
            var choice: UnsafePointer<CChar>? = nil
            guard gp_widget_get_choice(widget, Int32(index), &choice) >= 0, let choice else {
                throw GPhotoError.failed("\(key): no choice \(index)")
            }
            try check(gp_widget_set_value(widget, choice), key)
        }
    }

    /// Sets a RANGE, TOGGLE, TEXT or RADIO entry from its textual value.
    func setValue(_ key: String, _ value: String) throws {
        try connect()
        try update(key) { widget in
            var type = GP_WIDGET_WINDOW
            gp_widget_get_type(widget, &type)
            switch type {
            case GP_WIDGET_RANGE:
                var number = Float(value) ?? 0
                try check(gp_widget_set_value(widget, &number), key)
            case GP_WIDGET_TOGGLE, GP_WIDGET_DATE:
                var number = Int32(value) ?? 0
                try check(gp_widget_set_value(widget, &number), key)
            default:
                try check(gp_widget_set_value(widget, value), key)
            }
        }
    }

    /// Applies several writes in order. A write the camera rejects is reported
    /// in the result and the rest still go through; only losing the camera throws.
    func apply(_ ops: [WriteOp]) throws -> [String] {
        var rejected: [String] = []
        for op in ops {
            do {
                switch op.kind {
                case .index(let index): try setChoice(op.key, index: index)
                case .value(let value): try setValue(op.key, value)
                }
            } catch GPhotoError.failed(let message) {
                rejected.append(message)
            }
        }
        return rejected
    }

    private func update(_ key: String, _ body: (OpaquePointer) throws -> Void) throws {
        var widget: OpaquePointer? = nil
        let ret = gp_camera_get_single_config(camera, key, &widget, context)
        guard ret >= 0, let widget else { throw error(ret, key) }
        defer { gp_widget_free(widget) }
        try body(widget)
        try check(gp_camera_set_single_config(camera, key, widget, context), key)
    }

    // MARK: - Live view

    /// Grabs one live-view frame (640×360 JPEG on the Z5 II) and decodes it.
    /// libgphoto2 switches the camera's USB live view on for the first call.
    func capturePreview() throws -> PreviewFrame {
        try connect()
        if previewFile == nil { gp_file_new(&previewFile) }
        try check(gp_camera_capture_preview(camera, previewFile, context), "preview")

        var bytes: UnsafePointer<CChar>? = nil
        var size: UInt = 0
        gp_file_get_data_and_size(previewFile, &bytes, &size)
        guard let bytes, size > 0 else { throw GPhotoError.failed("Empty live-view frame") }
        let data = Data(bytes: bytes, count: Int(size))

        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw GPhotoError.failed("Could not decode live-view frame")
        }
        return PreviewFrame(image: image)
    }

    /// Turns the camera's USB live view off again.
    func endPreview() {
        guard camera != nil else { return }
        try? setValue("viewfinder", "0")
    }

    // MARK: - Errors

    private func check(_ ret: Int32, _ what: String) throws {
        if ret < 0 { throw error(ret, what) }
    }

    private func error(_ ret: Int32, _ what: String) -> GPhotoError {
        let contextMessage = Self.lastContextError
        Self.lastContextError = ""
        let detail = contextMessage.isEmpty ? String(cString: gp_result_as_string(ret)) : contextMessage

        switch ret {
        case GP_ERROR_MODEL_NOT_FOUND:
            return .noCamera
        case GP_ERROR_IO_USB_CLAIM:
            return .cameraBusy(detail)
        case GP_ERROR_IO, GP_ERROR_IO_READ, GP_ERROR_IO_WRITE, GP_ERROR_IO_USB_FIND, GP_ERROR_TIMEOUT:
            // The camera went away mid-session; start over on the next call.
            disconnect()
            return .noCamera
        default:
            return .failed("\(what): \(detail)")
        }
    }

    // MARK: - Widget → entry

    private static func entry(from widget: OpaquePointer) -> ConfigEntry {
        var entry = ConfigEntry()

        var label: UnsafePointer<CChar>? = nil
        gp_widget_get_label(widget, &label)
        entry.label = label.map { String(cString: $0) } ?? ""

        var readOnly: Int32 = 0
        gp_widget_get_readonly(widget, &readOnly)
        entry.readOnly = readOnly != 0

        var type = GP_WIDGET_WINDOW
        gp_widget_get_type(widget, &type)

        switch type {
        case GP_WIDGET_RADIO, GP_WIDGET_MENU:
            entry.kind = .radio
            entry.current = stringValue(of: widget)
            let count = gp_widget_count_choices(widget)
            for index in 0..<max(0, count) {
                var choice: UnsafePointer<CChar>? = nil
                gp_widget_get_choice(widget, index, &choice)
                entry.choices.append(choice.map { String(cString: $0) } ?? "")
            }
        case GP_WIDGET_RANGE:
            entry.kind = .range
            var value: Float = 0
            gp_widget_get_value(widget, &value)
            entry.current = text(for: value)
            var low: Float = 0, high: Float = 0, step: Float = 0
            gp_widget_get_range(widget, &low, &high, &step)
            entry.bottom = Double(low)
            entry.top = Double(high)
            entry.step = Double(step)
        case GP_WIDGET_TOGGLE, GP_WIDGET_DATE:
            entry.kind = type == GP_WIDGET_TOGGLE ? .toggle : .date
            var value: Int32 = 0
            gp_widget_get_value(widget, &value)
            entry.current = String(value)
        case GP_WIDGET_TEXT:
            entry.kind = .text
            entry.current = stringValue(of: widget)
        default:
            entry.kind = .other(String(type.rawValue))
        }
        return entry
    }

    private static func stringValue(of widget: OpaquePointer) -> String {
        var value: UnsafePointer<CChar>? = nil
        gp_widget_get_value(widget, &value)
        return value.map { String(cString: $0) } ?? ""
    }

    private static func text(for value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
