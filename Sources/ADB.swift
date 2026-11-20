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
    static func find() -> String? {
        let candidates = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/opt/homebrew/share/android-platform-tools/adb", "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
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
    @Published private(set) var fastMode = false
    @Published private(set) var latencyMS: Int?
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect") }
    }
    private let queue = DispatchQueue(label: "mx.firetvremote.commands", qos: .userInitiated)
    private let adb = ADB.find()
    private var timer: Timer?
    private var generation = UUID()
    private var checking = false
    private var pendingNavigation = 0
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

    func configure(host: String, port: String) -> Bool {
        guard let target = ADB.endpoint(host, port) else { return false }
        generation = UUID()
        checking = false
        sendingText = false
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

    private func checkConnection(reconnect: Bool, showConnecting: Bool) {
        guard let adb else { state = .missingADB; return }
        guard !endpoint.isEmpty else { state = .disconnected; latencyMS = nil; return }
        guard !checking else { return }
        checking = true
        if showConnecting { state = .connecting; notice = "" }
        let target = endpoint, token = generation
        queue.async { [weak self] in
            guard let self else { return }
            if let channel = self.channel, channel.target == target, case .ok(let milliseconds) = channel.request("P", timeout: 1) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.checking = false
                    self.state = .connected
                    self.fastMode = true
                    self.latencyMS = Int(milliseconds.rounded())
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
            var measured: Int?
            if status == .connected && (showConnecting || Date().timeIntervalSince(self.lastFastAttempt) > 25) {
                self.lastFastAttempt = Date()
                self.channel = FastChannel.start(adb: adb, target: target)
                if let channel = self.channel {
                    if case .ok(let milliseconds) = channel.request("K 0") {
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
            }
        }
    }

    func press(_ key: RemoteKey) {
        // Limit queued directional input, never accumulate seconds of stale keys.
        guard state == .connected, pendingNavigation < (fastMode ? 8 : 2) else { return }
        pendingNavigation += 1
        command(["input keyevent \(key.rawValue)"], fastCommands: ["K \(key.rawValue)"], navigation: true) { [weak self] _ in
            guard let self else { return }
            self.pendingNavigation = max(0, self.pendingNavigation - 1)
        }
    }

    func sendText(_ value: String, confirm: Bool, completion: @escaping (Bool) -> Void) {
        guard !sendingText, state == .connected else { completion(false); return }
        let limited = String(value.prefix(500))
        let prepared = ADB.textCommands(limited)
        guard !prepared.commands.isEmpty else {
            notice = "El texto no contiene caracteres compatibles."
            completion(false)
            return
        }
        sendingText = true
        let cmds = prepared.commands + (confirm ? ["input keyevent 66"] : [])
        let encoded = Data(ADB.plainText(limited).utf8).base64EncodedString()
        let fastCommands = ["T \(encoded)"] + (confirm ? ["K 66"] : [])
        command(cmds, fastCommands: fastCommands, textJob: true) { [weak self] success in
            guard let self else { completion(false); return }
            self.sendingText = false
            if success {
                self.notice = prepared.changed ? "Enviado; se adaptaron algunos caracteres." : "Texto enviado."
            }
            completion(success)
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
