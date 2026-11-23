import Foundation

/// Runs AppleScript off the main thread, one script at a time, so Apple Events keep their order.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "in.throttlelabs.mauna.applescript", qos: .userInitiated)
    /// Compiled scripts, keyed by source. Only touched on `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    /// Runs `source` and returns the result coerced to text, if any.
    func run(_ source: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let script: NSAppleScript
                if let cached = self.compiled[source] {
                    script = cached
                } else if let fresh = NSAppleScript(source: source) {
                    self.compiled[source] = fresh
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
    }
}

nonisolated enum ScriptError: Error, Equatable, Sendable {
    /// The user hasn't allowed Mauna to control this app (System Settings › Privacy & Security › Automation).
    case notAuthorized
    /// The app quit or isn't running.
    case notRunning
    /// The app didn't answer in time.
    case timedOut
    case failed(code: Int, message: String)

    init(_ info: NSDictionary) {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        switch code {
        case -1743, -1744: self = .notAuthorized
        case -600, -609:   self = .notRunning
        case -1712:        self = .timedOut
        default:           self = .failed(code: code, message: info[NSAppleScript.errorMessage] as? String ?? "")
        }
    }
}
