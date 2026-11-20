import Foundation
import Combine

enum RemoteKey: String, CaseIterable {
    case up = "19", down = "20", left = "21", right = "22", select = "23"
    case back = "4", home = "3", menu = "82"
}

struct ADBResult {
    let code: Int32
    let output: String
    var ok: Bool { code == 0 }
}

struct ADB {
    enum PowerState: Equatable { case awake, asleep, unknown }
    enum WakeResult: Equatable { case awake, asleep, sent, failed }

    static func powerState(_ report: String) -> PowerState {
        if report.contains("mWakefulness=Asleep") || report.contains("mWakefulness=Dozing") ||
            report.contains("mWakefulness=Dreaming") || report.contains("Display Power: state=OFF") {
            return .asleep
        }
        if report.contains("mWakefulness=Awake") || report.contains("Display Power: state=ON") {
            return .awake
        }
        return .unknown
    }

    private static func readPower(_ binary: String, target: String,
                                  runCommand: (String, [String], TimeInterval) -> ADBResult) -> PowerState {
        let report = runCommand(binary, ["-s", target, "shell", "dumpsys power | grep -E 'mWakefulness=|Display Power: state='"], 2)
        return report.ok ? powerState(report.output) : .unknown
    }

    /// Use explicit wake and sleep events rather than a blind power toggle.
    static func wake(_ binary: String, target: String,
                     runCommand: (String, [String], TimeInterval) -> ADBResult = ADB.run,
                     pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)) -> WakeResult {
        setPower(binary, target: target, desired: .awake, runCommand: runCommand, pause: pause)
    }

    static func togglePower(_ binary: String, target: String,
                            runCommand: (String, [String], TimeInterval) -> ADBResult = ADB.run,
                            pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)) -> WakeResult {
        let current = readPower(binary, target: target, runCommand: runCommand)
        // If the device cannot report its state, prefer waking over sleeping
        // an active TV without knowing whether it is in use.
        return setPower(binary, target: target, desired: current == .awake ? .asleep : .awake,
                        runCommand: runCommand, pause: pause)
    }

    private static func setPower(_ binary: String, target: String, desired: PowerState,
                                 runCommand: (String, [String], TimeInterval) -> ADBResult,
                                 pause: (TimeInterval) -> Void) -> WakeResult {
        let key = desired == .asleep ? "KEYCODE_SLEEP" : "KEYCODE_WAKEUP"
        for attempt in 0..<2 {
            let result = runCommand(binary, ["-s", target, "shell", "input keyevent \(key)"], 5)
            if result.ok && !result.output.hasPrefix("Error:") {
                for poll in 0..<3 {
                    if poll > 0 { pause(0.3) }
                    let observed = readPower(binary, target: target, runCommand: runCommand)
                    if observed == desired { return desired == .asleep ? .asleep : .awake }
                    if observed == .unknown { return .sent }
                }
            }
            if attempt == 0 { pause(0.2) }
        }
        return .failed
    }

    static var installedLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FireTV Controller/platform-tools", isDirectory: true)
    }

    static func find() -> String? {
        let candidates = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/opt/homebrew/share/android-platform-tools/adb", "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb", installedLocation.appendingPathComponent("adb").path]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    // Called only after the user has explicitly accepted the Android SDK
    // terms; downloads the official macOS package, without sudo.
    static func install() -> String? {
        if find() != nil { return nil }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("firetv-tools-" + UUID().uuidString, isDirectory: true)
        let archive = temp.appendingPathComponent("platform-tools.zip")
        let destination = installedLocation
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: temp) }
            guard run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--tlsv1.2", "--retry", "2", "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip", "--output", archive.path], timeout: 180).ok else {
                return "No se pudo descargar ADB. Comprueba tu conexión a internet."
            }
            guard run("/usr/bin/ditto", ["-x", "-k", archive.path, temp.path], timeout: 30).ok else { return "No se pudo descomprimir ADB." }
            let extracted = temp.appendingPathComponent("platform-tools", isDirectory: true)
            guard fm.isExecutableFile(atPath: extracted.appendingPathComponent("adb").path) else { return "La descarga no contiene un ADB válido." }
            if fm.fileExists(atPath: destination.path) {
                return find() == nil ? "Ya existe una instalación incompleta de ADB. Revisa la carpeta de herramientas." : nil
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: extracted, to: destination)
            return find() == nil ? "No se pudo preparar ADB." : nil
        } catch {
            return "No se pudo instalar ADB. Comprueba el espacio y los permisos de tu Mac."
        }
    }

    static func run(_ binary: String, _ args: [String], timeout: TimeInterval = 6) -> ADBResult {
        let process = Process()
        let pipe = Pipe()
        let complete = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in complete.signal() }
        do { try process.run() } catch { return ADBResult(code: -1, output: error.localizedDescription) }
        if complete.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            return ADBResult(code: -1, output: "Tiempo de espera agotado")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ADBResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func endpoint(_ rawHost: String, _ rawPort: String) -> String? {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(part) else { return false }
            return (0...255).contains(number)
        }), let port = Int(rawPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else { return nil }
        return parts.map { String(Int($0)!) }.joined(separator: ".") + ":\(port)"
    }

    // Android's built-in input command accepts basic Latin characters. Spaces must
    // be escaped as %s; split literal %s so they are not interpreted as spaces.
    static func plainText(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        let singleLine = folded.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
        return String(singleLine.unicodeScalars.filter { (32...126).contains($0.value) })
    }

    static func textCommands(_ input: String) -> (commands: [String], changed: Bool) {
        let plain = plainText(input)
        var chunks = [String]()
        var chunk = ""
        for character in plain {
            if character == "s" && chunk.last == "%" {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        let commands = chunks.map { value in
            let encoded = value.replacingOccurrences(of: " ", with: "%s")
            let quoted = "'" + encoded.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return "input text \(quoted)"
        }
        return (commands, plain != input)
    }

    struct TextDelta: Equatable {
        let erase: Int
        let append: String
        var isEmpty: Bool { erase == 0 && append.isEmpty }
    }

    // The local field owns only the text entered during this writing session.
    // Reuse the common prefix and modify the suffix, never resend that prefix.
    static func textDelta(from acknowledged: String, to desired: String) -> TextDelta {
        let old = Array(acknowledged)
        let new = Array(desired)
        let prefix = zip(old, new).prefix(while: { $0.0 == $0.1 }).count
        return TextDelta(erase: old.count - prefix, append: String(new.dropFirst(prefix)))
    }
}

enum LinkState: Equatable {
    case connecting, connected, disconnected, unauthorized, missingADB
    var label: String {
        switch self {
        case .connecting: return "Conectando…"
        case .connected: return "Conectado"
        case .disconnected: return "Sin conexión"
        case .unauthorized: return "Autoriza en TV"
        case .missingADB: return "ADB no disponible"
        }
    }
}

final class RemoteController: ObservableObject {
    @Published private(set) var state: LinkState = .connecting
    @Published private(set) var endpoint: String
    @Published private(set) var notice = ""
    @Published private(set) var sendingText = false
    @Published private(set) var liveText = ""
    @Published private(set) var textNeedsReset = false
    @Published private(set) var waking = false
    @Published private(set) var fastMode = false
    @Published private(set) var latencyMS: Int?
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect") }
    }
    private let queue = DispatchQueue(label: "mx.firetvremote.commands", qos: .userInitiated)
    private var adb = ADB.find()
    private var timer: Timer?
    private var generation = UUID()
    private var checking = false
    private var pendingNavigation = 0
    private var liveAcknowledged = ""
    private var liveSyncing = false
    private var liveDebounce: DispatchWorkItem?
    private var liveConfirm: ((Bool) -> Void)?
    private var liveEnding = false
    private var liveActions: [() -> Void] = []
    // Only the first successful connection of a launch should wake the TV.
    // Periodic checks must not undo an intentional sleep.
    private var autoWakePending = true
    private var openedWindow = false
    // Only the serial command queue accesses the channel or attempt timestamp.
    private var channel: FastChannel?
    private var lastFastAttempt: Date = .distantPast

    init() {
        let defaults = UserDefaults.standard
        endpoint = defaults.string(forKey: "endpoint") ?? ""
        autoReconnect = defaults.object(forKey: "autoReconnect") as? Bool ?? true
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .connected || self.autoReconnect { self.refresh() }
        }
    }

    deinit { timer?.invalidate(); channel?.close() }

    func installDependency(_ completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = ADB.install()
            DispatchQueue.main.async {
                guard let self else { return }
                self.adb = ADB.find()
                if error == nil { self.connect() }
                completion(error)
            }
        }
    }

    func configure(host: String, port: String) -> Bool {
        guard let target = ADB.endpoint(host, port) else { return false }
        generation = UUID()
        resetLiveText()
        checking = false
        sendingText = false
        waking = false
        pendingNavigation = 0
        fastMode = false
        latencyMS = nil
        endpoint = target
        UserDefaults.standard.set(target, forKey: "endpoint")
        connect()
        return true
    }

    func connect() { checkConnection(reconnect: true, showConnecting: true) }
    private func refresh() { checkConnection(reconnect: autoReconnect, showConnecting: false) }

    func windowOpened() {
        if !openedWindow { openedWindow = true; return }
        // Closing and reopening the window without quitting the process also
        // counts as opening the remote.
        if state == .connected {
            changePower(wakeOnly: true)
        } else {
            autoWakePending = true
            connect()
        }
    }

    private func checkConnection(reconnect: Bool, showConnecting: Bool) {
        guard let adb else { state = .missingADB; return }
        guard !endpoint.isEmpty else { state = .disconnected; latencyMS = nil; return }
        guard !checking else { return }
        checking = true
        if showConnecting { state = .connecting; notice = "" }
        let target = endpoint, token = generation, wakeAtLaunch = autoWakePending
        queue.async { [weak self] in
            guard let self else { return }
            if let channel = self.channel, channel.target == target, case .ok(let milliseconds) = channel.request("P", timeout: 1) {
                let wakeResult = wakeAtLaunch ? ADB.wake(adb, target: target) : nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.checking = false
                    self.state = .connected
                    self.fastMode = true
                    self.latencyMS = Int(milliseconds.rounded())
                    if let wakeResult {
                        self.autoWakePending = false
                        if wakeResult == .failed { self.notice = "No se pudo despertar la TV. Intenta con ⏻." }
                    }
                }
                return
            }
            self.channel?.close()
            self.channel = nil
            var result = ADB.run(adb, ["-s", target, "get-state"], timeout: 3)
            var connectionMessage = ""
            if result.output != "device", reconnect {
                connectionMessage = ADB.run(adb, ["connect", target], timeout: 4).output
                result = ADB.run(adb, ["-s", target, "get-state"], timeout: 3)
            }
            let status: LinkState = result.output == "device" && result.ok ? .connected : ((result.output + connectionMessage).localizedCaseInsensitiveContains("unauthorized") || connectionMessage.localizedCaseInsensitiveContains("authenticate") ? .unauthorized : .disconnected)
            // Wake immediately after authorization, before starting the fast
            // channel or enabling the other remote controls.
            let wakeResult = status == .connected && wakeAtLaunch ? ADB.wake(adb, target: target) : nil
            var measured: Int?
            if status == .connected && (showConnecting || Date().timeIntervalSince(self.lastFastAttempt) > 25) {
                self.lastFastAttempt = Date()
                self.channel = FastChannel.start(adb: adb, target: target)
                if let channel = self.channel {
                    if case .ok(let milliseconds) = channel.request("P") {
                        measured = Int(milliseconds.rounded())
                    } else { channel.close(); self.channel = nil }
                }
            }
            let fast = self.channel != nil
            if status == .connected && !fast {
                let start = ProcessInfo.processInfo.systemUptime
                if ADB.run(adb, ["-s", target, "shell", "true"], timeout: 2).ok {
                    measured = Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
                }
            }
            let latency = measured
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.checking = false
                self.state = status
                self.fastMode = fast
                self.latencyMS = latency
                if status == .connected && (self.notice == "No se pudo enviar el comando." || self.notice == "Se perdió la conexión.") { self.notice = "" }
                if let wakeResult {
                    self.autoWakePending = false
                    if wakeResult == .failed { self.notice = "No se pudo despertar la TV. Intenta con ⏻." }
                }
            }
        }
    }

    func press(_ key: RemoteKey) {
        finishLiveTextBefore { [weak self] in self?.sendNavigation(key) }
    }

    private func sendNavigation(_ key: RemoteKey) {
        // Limit queued directional input, never accumulate seconds of stale keys.
        guard state == .connected, pendingNavigation < (fastMode ? 8 : 2) else { return }
        pendingNavigation += 1
        command(["input keyevent \(key.rawValue)"], fastCommands: ["K \(key.rawValue)"], navigation: true) { [weak self] _ in
            guard let self else { return }
            self.pendingNavigation = max(0, self.pendingNavigation - 1)
        }
    }

    func togglePower() {
        finishLiveTextBefore { [weak self] in self?.changePower(wakeOnly: false) }
    }

    private func changePower(wakeOnly: Bool) {
        guard let adb, state == .connected, !waking else { return }
        waking = true
        notice = ""
        let target = endpoint, token = generation
        queue.async { [weak self] in
            let result = wakeOnly ? ADB.wake(adb, target: target) : ADB.togglePower(adb, target: target)
            let stillConnected = result != .failed || ADB.run(adb, ["-s", target, "get-state"], timeout: 3).output == "device"
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.waking = false
                if result == .failed {
                    self.notice = stillConnected ? "No se pudo cambiar el estado de la TV. Intenta nuevamente." : "Se perdió la conexión."
                    if !stillConnected {
                        self.state = .disconnected
                        self.latencyMS = nil
                    }
                }
            }
        }
    }

    /// Coalesce very fast keystrokes, but flush word boundaries, pastes and
    /// deletions immediately. At most one delta is in flight.
    func updateLiveText(_ value: String) {
        guard !liveEnding, liveConfirm == nil, !textNeedsReset else { return }
        let previous = liveText
        liveText = String(value.prefix(500))
        guard liveText != previous else { return }
        liveDebounce?.cancel()
        guard state == .connected else {
            failLiveText()
            return
        }
        let boundary = liveText.last?.isWhitespace == true
        let editing = liveText.count != previous.count + 1 || !liveText.hasPrefix(previous)
        if boundary || editing {
            flushLiveText()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.flushLiveText() }
            liveDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045, execute: work)
        }
    }

    func confirmLiveText(completion: @escaping (Bool) -> Void) {
        guard !liveText.isEmpty, !textNeedsReset, !sendingText, !liveEnding, state == .connected else {
            completion(false); return
        }
        sendingText = true
        liveConfirm = completion
        liveDebounce?.cancel()
        flushLiveText()
    }

    /// A navigation or power action must follow the last pending text update,
    /// not race it into a different field. End the local session without
    /// deleting anything from the TV.
    private func finishLiveTextBefore(_ action: @escaping () -> Void) {
        guard liveText.isEmpty && liveAcknowledged.isEmpty && !liveSyncing &&
              liveConfirm == nil && !textNeedsReset && !liveEnding else {
            guard liveActions.count < 8 else { return }
            liveActions.append(action)
            liveEnding = true
            liveDebounce?.cancel()
            flushLiveText()
            return
        }
        action()
    }

    private func resetLiveText() {
        liveDebounce?.cancel()
        liveDebounce = nil
        liveAcknowledged = ""
        liveText = ""
        liveSyncing = false
        liveEnding = false
        liveConfirm = nil
        liveActions.removeAll()
        sendingText = false
        textNeedsReset = false
        if notice == "No se pudo sincronizar. Abre otra búsqueda." { notice = "" }
    }

    private func completeLiveText(_ success: Bool) {
        let completion = liveConfirm
        let actions = liveActions
        resetLiveText()
        completion?(success)
        actions.forEach { $0() }
    }

    private func failLiveText() {
        // A timeout may mean the TV received a delta (or part of it). Never
        // retry unacknowledged input: that could duplicate letters or words.
        liveSyncing = false
        textNeedsReset = true
        notice = "No se pudo sincronizar. Abre otra búsqueda."
        let completion = liveConfirm
        liveConfirm = nil
        sendingText = false
        completion?(false)
        if liveEnding { completeLiveText(false) }
    }

    private func flushLiveText() {
        liveDebounce?.cancel()
        liveDebounce = nil
        guard !liveSyncing else { return }
        if textNeedsReset {
            if liveEnding { completeLiveText(false) }
            return
        }
        guard state == .connected else { failLiveText(); return }
        let desired = ADB.plainText(liveText)
        let delta = ADB.textDelta(from: liveAcknowledged, to: desired)
        if !delta.isEmpty {
            var commands: [String] = []
            var fastCommands: [String] = []
            if delta.erase > 0 {
                commands.append("input keyevent " + Array(repeating: "67", count: delta.erase).joined(separator: " "))
                fastCommands.append("D \(delta.erase)")
            }
            if !delta.append.isEmpty {
                commands.append(contentsOf: ADB.textCommands(delta.append).commands)
                fastCommands.append("T " + Data(delta.append.utf8).base64EncodedString())
            }
            liveSyncing = true
            command(commands, fastCommands: fastCommands, textJob: true) { [weak self] success in
                guard let self else { return }
                self.liveSyncing = false
                guard success else { self.failLiveText(); return }
                // Advance the acknowledged snapshot only after the TV replies.
                self.liveAcknowledged = desired
                self.flushLiveText()
            }
        } else if liveConfirm != nil {
            // Search text is already present and results update as it is typed.
            // Fire TV's on-screen keyboard interprets KEYCODE_ENTER as a
            // click on its focused character. Finishing locally must not
            // send another key to the TV.
            completeLiveText(true)
        } else if liveEnding {
            completeLiveText(true)
        }
    }

    private func command(_ commands: [String], fastCommands: [String]? = nil, textJob: Bool = false, navigation: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard let adb, state == .connected else { completion?(false); return }
        let target = endpoint, token = generation
        let queuedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self else { return }
            if navigation && ProcessInfo.processInfo.systemUptime - queuedAt > 0.65 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    completion?(true)
                }
                return
            }
            var success = true
            var lostChannel = false
            var latency: Int?
            if let fastCommands, let channel = self.channel, channel.target == target {
                for command in fastCommands {
                    switch channel.request(command, timeout: textJob ? 30 : 1.5) {
                    case .ok(let milliseconds):
                        if navigation { latency = Int(milliseconds.rounded()) }
                    case .rejected: success = false
                    case .disconnected: success = false; lostChannel = true
                    }
                    if !success { break }
                }
                if lostChannel {
                    channel.close()
                    self.channel = nil
                    self.lastFastAttempt = .distantPast
                }
            } else {
                let start = ProcessInfo.processInfo.systemUptime
                for command in commands {
                    let result = ADB.run(adb, ["-s", target, "shell", command], timeout: textJob ? 20 : 5)
                    if !result.ok || result.output.hasPrefix("Error:") { success = false; break }
                }
                if navigation && success { latency = Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded()) }
            }
            let stillConnected = success || ADB.run(adb, ["-s", target, "get-state"], timeout: 3).output == "device"
            let fast = self.channel != nil
            let finalLatency = latency
            let reconnect = lostChannel
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.fastMode = fast
                if let finalLatency { self.latencyMS = finalLatency }
                if !stillConnected { self.latencyMS = nil }
                if !success {
                    self.notice = stillConnected ? "No se pudo enviar el comando." : "Se perdió la conexión."
                    if !stillConnected { self.state = .disconnected }
                }
                completion?(success)
                if reconnect && self.autoReconnect { self.refresh() }
            }
        }
    }
}
