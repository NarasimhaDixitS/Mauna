import Foundation

/// Runs AppleScript off the main thread, one script at a time, so Apple Events keep their order.
///
/// Two rules keep one slow app from holding everything up:
/// - Every call gives up after `timeout` (Apple's default is 2 minutes). A hidden Safari tab can stall
///   for seconds; without a cap, every Lower and Pause behind it would wait, then play out late.
/// - A call whose task was cancelled before its turn is dropped, never run late.
///   A newer action cancels the old fade, so its leftover steps vanish instead of undoing the new one.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    /// Long enough for a busy app, short enough that a stall never blocks the queue for long.
    static let timeout = 2

    private let queue = DispatchQueue(label: "in.throttlelabs.mauna.applescript", qos: .userInitiated)
    /// Compiled scripts, keyed by source. Only touched on `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    /// Runs `source` and returns the result coerced to text, if any.
    func run(_ source: String) async throws -> String? {
        try Task.checkCancellation()
        let cancelled = CancelFlag()
        let wrapped = "with timeout of \(Self.timeout) seconds\n\(source)\nend timeout"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !cancelled.isSet else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let script: NSAppleScript
                    if let cached = self.compiled[wrapped] {
                        script = cached
                    } else if let fresh = NSAppleScript(source: wrapped) {
                        self.compiled[wrapped] = fresh
                        script = fresh
                    } else {
                        continuation.resume(throwing: ScriptError.failed(code: 0, message: "Couldn't build the script"))
                        return
                    }

                    var errorInfo: NSDictionary?
                    let result = script.executeAndReturnError(&errorInfo)
                    if let errorInfo {
                        continuation.resume(throwing: ScriptError(errorInfo))
                    } else {
                        continuation.resume(returning: result.stringValue)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }
}

/// Set from any thread when a waiting call's task is cancelled.
nonisolated private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

nonisolated enum ScriptError: Error, Equatable, Sendable {
    /// The user hasn't allowed Mauna to control this app (System Settings › Privacy & Security › Automation).
    case notAuthorized
    /// The app quit or isn't running.
    case notRunning
    /// The app didn't answer in time.
    case timedOut
    /// The browser blocks JavaScript from Apple Events (a one-time setting).
    case javaScriptOff
    case failed(code: Int, message: String)

    init(_ info: NSDictionary) {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        switch code {
        case -1743, -1744: self = .notAuthorized
        case -600, -609:   self = .notRunning
        case -1712:        self = .timedOut
        default:
            let message = info[NSAppleScript.errorMessage] as? String ?? ""
            // Chrome: "Executing JavaScript through AppleScript is turned off…"
            // Safari: "You must enable the 'Allow JavaScript from Apple Events' option…"
            if message.localizedCaseInsensitiveContains("JavaScript") && (message.localizedCaseInsensitiveContains("turned off") || message.localizedCaseInsensitiveContains("Allow JavaScript")) {
                self = .javaScriptOff
            } else {
                self = .failed(code: code, message: message)
            }
        }
    }
}
