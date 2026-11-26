import AppKit
import CoreAudio

/// Which apps are in a call right now, for the "In a call" trigger. Mauna never opens the mic or hears
/// anything: it reads Core Audio's per-process flags (macOS 14.2+), the same facts behind the orange
/// mic dot in the menu bar.
///
/// An app is in a call while it uses the mic, or while it has been playing sound for a few seconds.
/// The second part matters: Zoom lets go of the mic when you mute, but keeps playing the other people.
/// See `AppSnapshot.inCall`.
///
/// Audio often runs in a helper process ("com.google.Chrome.helper", "com.microsoft.teams2.helper"):
/// it's credited to the app it belongs to. FaceTime's audio runs in a system service, credited to FaceTime.
final class MicWatcher {
    /// Called on the main thread whenever the set of apps in a call changes.
    var onChange: ((Set<String>) -> Void)?
    private(set) var appsInCall: Set<String> = []

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var watched: Set<AudioObjectID> = []
    private var pending = false
    /// When each app started playing sound, while it still is.
    private var soundSince: [String: TimeInterval] = [:]
    private var poll: Timer?

    init() {
        var list = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(system, &list, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
        // macOS doesn't reliably announce when an app starts using the mic or sound, and "sound for a
        // few seconds" needs a clock anyway: look every 2 s too. Reading these flags is cheap.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        read()
    }

    // MARK: Reading

    /// Listener callbacks come in bursts: read once per burst.
    private func scheduleRead() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pending = false
            self?.read()
        }
    }

    private func read() {
        let processes = Self.processObjects()
        // Listen to each new process's mic and sound flags.
        for process in processes where !watched.contains(process) {
            for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(process, &address, .main) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.scheduleRead() }
                }
            }
            watched.insert(process)
        }
        watched.formIntersection(processes)

        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let now = ProcessInfo.processInfo.systemUptime
        var mic: Set<String> = []
        var sounding: Set<String> = []
        for process in processes {
            let input = Self.flag(process, kAudioProcessPropertyIsRunningInput)
            let output = Self.flag(process, kAudioProcessPropertyIsRunningOutput)
            guard input || output, let id = Self.bundleID(of: process) else { continue }
            let owners = AppSnapshot.micOwners(of: id, running: running)
            if input { mic.formUnion(owners) }
            if output { sounding.formUnion(owners) }
        }
        soundSince = soundSince.filter { sounding.contains($0.key) }
        for app in sounding where soundSince[app] == nil { soundSince[app] = now }

        let apps = AppSnapshot.inCall(mic: mic, soundSince: soundSince, now: now)
        guard apps != appsInCall else { return }
        appsInCall = apps
        onChange?(apps)
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> Set<AudioObjectID> {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids)
    }

    private static func flag(_ process: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let id = value?.takeRetainedValue() as String?, !id.isEmpty else { return nil }
        return id
    }

    #if DEBUG
    /// Debug: every audio process and whether it's using the mic or playing sound.
    static func describeAll() -> [String] {
        processObjects().map { process in
            var address = address(kAudioProcessPropertyIsRunningOutput)
            var output: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(process, &address, 0, nil, &size, &output)
            return "\(bundleID(of: process) ?? "?")  mic:\(flag(process, kAudioProcessPropertyIsRunningInput) ? 1 : 0) sound:\(output)"
        }.sorted()
    }
    #endif
}
