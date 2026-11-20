import Foundation
import Darwin

/// One persistent ADB shell. The helper reuses Fire OS's own input command;
/// it has no listening network port and ends when the ADB stream closes.
final class FastChannel {
    static let remotePath = "/data/local/tmp/firetv-controller-v1.jar"
    let target: String
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var buffer = Data()
    private var replies: [String] = []
    private var ended = false

    private init(target: String) { self.target = target }

    static func start(adb: String, target: String) -> FastChannel? {
        guard let helper = Bundle.main.url(forResource: "FastRemote", withExtension: "jar") else { return nil }
        guard ADB.run(adb, ["-s", target, "push", helper.path, remotePath], timeout: 5).ok else { return nil }
        let channel = FastChannel(target: target)
        channel.process.executableURL = URL(fileURLWithPath: adb)
        channel.process.arguments = ["-s", target, "shell", "-T", "CLASSPATH=\(remotePath):/system/framework/input.jar app_process /system/bin org.firetvcontroller.remote.FastRemote"]
        channel.process.standardInput = channel.input
        channel.process.standardOutput = channel.output
        channel.process.standardError = channel.output
        _ = fcntl(channel.input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        channel.output.fileHandleForReading.readabilityHandler = { [weak channel] handle in
            channel?.receive(handle.availableData)
        }
        channel.process.terminationHandler = { [weak channel] _ in channel?.receive(Data()) }
        do { try channel.process.run() } catch { channel.close(); return nil }
        guard channel.nextReply(timeout: 5) == "FIRETV_READY_2" else { channel.close(); return nil }
        return channel
    }

    private func receive(_ data: Data) {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        if data.isEmpty { ended = true; return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            if ["FIRETV_READY_2", "FIRETV_OK", "FIRETV_ERROR"].contains(line) { replies.append(line) }
        }
        if buffer.count > 8192 { buffer.removeAll() }
    }

    private func nextReply(timeout: TimeInterval) -> String? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while replies.isEmpty && !ended {
            if !condition.wait(until: deadline) { return nil }
        }
        return replies.isEmpty ? nil : replies.removeFirst()
    }

    enum Reply { case ok(Double), rejected, disconnected }

    func request(_ command: String, timeout: TimeInterval = 1.5) -> Reply {
        guard process.isRunning else { return .disconnected }
        let start = ProcessInfo.processInfo.systemUptime
        do { try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8)) }
        catch { return .disconnected }
        switch nextReply(timeout: timeout) {
        case "FIRETV_OK": return .ok((ProcessInfo.processInfo.systemUptime - start) * 1000)
        case "FIRETV_ERROR": return .rejected
        default: return .disconnected
        }
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            try? input.fileHandleForWriting.write(contentsOf: Data("Q\n".utf8))
        }
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    deinit { close() }
}
