import SwiftUI
import AppKit

private let appBackground = Color(red: 0.027, green: 0.026, blue: 0.025)
private let keySurface = Color(red: 0.068, green: 0.065, blue: 0.061)
private let muted = Color(red: 0.69, green: 0.60, blue: 0.53)
private let mint = Color(red: 0.22, green: 1.00, blue: 0.66)
private let gold = Color(red: 1.00, green: 0.81, blue: 0.27)
private let amber = Color(red: 1.00, green: 0.65, blue: 0.16)
private let orange = Color(red: 1.00, green: 0.48, blue: 0.10)
private let peach = Color(red: 1.00, green: 0.68, blue: 0.39)
private let ember = Color(red: 1.00, green: 0.32, blue: 0.035)
private let copper = Color(red: 0.71, green: 0.35, blue: 0.16)
private let redLED = Color(red: 1.00, green: 0.27, blue: 0.36)
private let accent = orange
private let padDiameter: CGFloat = 256

private let warmRing = AngularGradient(stops: [
    .init(color: gold, location: 0), .init(color: amber, location: 0.22),
    .init(color: orange, location: 0.43), .init(color: ember, location: 0.62),
    .init(color: peach, location: 0.82), .init(color: gold, location: 1)
], center: .center, startAngle: .degrees(-135), endAngle: .degrees(225))

@main
struct FireTVRemoteApp: App {
    @StateObject private var remote = RemoteController()

    var body: some Scene {
        WindowGroup("Control remoto") {
            RemoteView(remote: remote)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 332, height: 490)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Reserve Command-H for the remote instead of macOS Hide.
            CommandGroup(replacing: .appVisibility) {
                Button("Inicio") {
                    if NSApp.keyWindow?.attachedSheet == nil { remote.press(.home) }
                }
                .keyboardShortcut("h", modifiers: .command)
                .disabled(remote.state != .connected)
                Divider()
                Button("Ocultar aplicación") { NSApp.hide(nil) }
                Button("Ocultar las demás") { NSApp.hideOtherApplications(nil) }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button("Mostrar todas") { NSApp.unhideAllApplications(nil) }
            }
        }
    }
}

struct RemoteView: View {
    @ObservedObject var remote: RemoteController
    private var search: String { remote.liveText }
    @State private var showSettings = false
    @State private var showDependency = false
    @State private var activeKey: RemoteKey?
    @State private var pulse = UUID()
    @State private var monitor: Any?
    @State private var swallowedReturn: UInt16?
    @State private var lastRepeat: TimeInterval = 0
    @FocusState private var writing: Bool

    private var connected: Bool { remote.state == .connected }

    var body: some View {
        VStack(spacing: 16) {
            header
            directionPad
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            typingCard
            shortcuts
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(width: 332)
        .background {
            ZStack {
                appBackground
                RadialGradient(colors: [orange.opacity(0.045), .clear], center: .center, startRadius: 15, endRadius: 225)
                RadialGradient(colors: [ember.opacity(0.035), .clear], center: .bottomLeading, startRadius: 5, endRadius: 195)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(LinearGradient(colors: [gold.opacity(0.14), .clear, copper.opacity(0.29), orange.opacity(0.11)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { ConnectionSettings(remote: remote) }
        .sheet(isPresented: $showDependency) { DependencySetup(remote: remote) }
        .onAppear {
            if monitor == nil {
                remote.windowOpened()
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                    handle(event)
                }
            }
            // macOS otherwise gives the first text field initial keyboard focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { stopWriting() }
            if remote.state == .missingADB { showDependency = true }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            swallowedReturn = nil
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                stopWriting()
                remote.togglePower()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(orange)
                    .shadow(color: orange.opacity(0.38), radius: 4)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(NeonButtonStyle(tint: orange, radius: 17, strength: 0.76, lit: remote.waking))
            .disabled(!connected || remote.waking)
            .help("Encender o poner la TV en reposo")
            .accessibilityLabel("Encender o poner la TV en reposo")
            Button(action: {
                if remote.state == .missingADB { showDependency = true }
                else if remote.endpoint.isEmpty { showSettings = true }
                else { remote.connect() }
            }) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(connected ? mint : redLED)
                        .frame(width: 7, height: 7)
                        .shadow(color: connected ? mint : redLED, radius: 5)
                    Text(connected ? (remote.latencyMS.map { "\($0) ms" } ?? "— ms") : (remote.state == .missingADB ? "Instalar ADB" : (remote.endpoint.isEmpty ? "Configurar" : remote.state.label)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(connected ? mint.opacity(0.90) : redLED.opacity(0.92))
                    if !connected && remote.state != .connecting {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(.black.opacity(0.32), in: Capsule())
                .overlay(Capsule().strokeBorder((connected ? mint : redLED).opacity(0.13), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("\(remote.state.label) · \(remote.endpoint) · latencia de la última comprobación o pulsación · clic para reconectar")
            .accessibilityLabel("Estado de conexión: \(remote.state.label)")
            .disabled(remote.state == .connecting)
            Spacer()
            Button {
                stopWriting()
                if remote.state == .missingADB { showDependency = true } else { showSettings = true }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(muted)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(NeonButtonStyle(tint: copper, radius: 17, strength: 0.66))
            .help("Configurar conexión (⌘,)")
            .accessibilityLabel("Configurar conexión")
        }
    }

    private var directionPad: some View {
        ZStack {
            Circle().stroke(warmRing, lineWidth: 10).blur(radius: 12).opacity(0.23)
                .allowsHitTesting(false)
            Circle().stroke(warmRing, lineWidth: 4).blur(radius: 5).opacity(0.52)
                .allowsHitTesting(false)
            Circle().fill(RadialGradient(colors: [keySurface, appBackground], center: .center, startRadius: 14, endRadius: 138))
                .overlay(Circle().strokeBorder(warmRing, lineWidth: 1.7).opacity(0.91))
                .allowsHitTesting(false)
            padKey(.up, angle: -90, icon: "chevron.up", label: "Arriba", letter: "W", arrow: "↑", tint: gold)
            padKey(.right, angle: 0, icon: "chevron.right", label: "Derecha", letter: "D", arrow: "→", tint: amber)
            padKey(.down, angle: 90, icon: "chevron.down", label: "Abajo", letter: "S", arrow: "↓", tint: orange)
            padKey(.left, angle: 180, icon: "chevron.left", label: "Izquierda", letter: "A", arrow: "←", tint: peach)
            Button { press(.select) } label: {
                VStack(spacing: 4) {
                    Text("OK").font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("⏎  /  Espacio").font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(peach.opacity(0.88))
                }
                .frame(width: 110, height: 110)
            }
            .buttonStyle(NeonButtonStyle(tint: orange, radius: 55, strength: 0.72, lit: activeKey == .select))
            .disabled(!connected)
            .help("Aceptar (Enter o Espacio)")
            .accessibilityLabel("Aceptar")
        }
        .frame(width: padDiameter, height: padDiameter)
        .opacity(connected ? 1 : 0.55)
    }

    private func padKey(_ key: RemoteKey, angle: Double, icon: String, label: String, letter: String, arrow: String, tint: Color) -> some View {
        Button { press(key) } label: {
            PadSectorLabel(angle: angle, icon: icon, hint: "\(letter) / \(arrow)", tint: tint, lit: activeKey == key)
        }
        .buttonStyle(.plain)
        .disabled(!connected)
        .accessibilityLabel(label)
        .help("\(label) (\(letter) o flecha)")
    }

    private var shortcuts: some View {
        HStack(spacing: 25) {
            roundKey("Esc / ⌫", icon: "arrow.uturn.backward", key: .back, tint: peach, hint: "Atrás (Esc o Backspace)")
            roundKey("⌘ + H", icon: "house", key: .home, tint: amber, hint: "Inicio (⌘ + H)")
            roundKey("M", icon: "line.3.horizontal", key: .menu, tint: Color(red: 1, green: 0.57, blue: 0.14), hint: "Menú (M)")
        }
    }

    private func roundKey(_ label: String, icon: String, key: RemoteKey, tint: Color, hint: String) -> some View {
        VStack(spacing: 7) {
            Button { press(key) } label: {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(key == .menu ? 0.48 : 0.38), radius: key == .menu ? 5 : 4)
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(NeonButtonStyle(tint: tint, radius: 31, strength: key == .menu ? 0.84 : 0.75, lit: activeKey == key))
            .disabled(!connected)
            .help(hint)
            .accessibilityLabel(hint)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
        }
    }

    private var typingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Escribir", text: Binding(get: { remote.liveText }, set: { remote.updateLiveText($0) }), prompt: Text("Escribir").foregroundColor(muted.opacity(0.69)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($writing)
                    .onSubmit { finishSearch() }
                    .disabled(!connected || remote.sendingText || remote.textNeedsReset)
                    .accessibilityLabel("Texto para TV")
                if search.isEmpty {
                    Text("⌘ + L").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted.opacity(0.74))
                }
                Button { finishSearch() } label: {
                    Group {
                        if remote.sendingText { ProgressView().controlSize(.small) }
                        else { Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)) }
                    }
                    .foregroundStyle(amber)
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(NeonButtonStyle(tint: orange, radius: 15, strength: 0.72, disabledOpacity: 0.69))
                .disabled(!connected || search.isEmpty || remote.sendingText || remote.textNeedsReset)
                .help("Finaliza la búsqueda y vuelve al mando")
                .accessibilityLabel("Buscar")
            }
            .padding(.leading, 13).padding(.trailing, 6).padding(.vertical, 6)
            .background(Color.white.opacity(0.025), in: Capsule())
            .overlay(Capsule().strokeBorder(writing ? orange.opacity(0.76) : copper.opacity(0.40), lineWidth: 1))
            .help("Escribe en tiempo real en el buscador de la TV (⌘ + L). Pulsa Enter o la lupa para confirmar.")
            if !remote.notice.isEmpty && remote.notice != "Texto enviado." {
                Text(remote.notice).font(.system(size: 10)).foregroundStyle(muted)
                    .lineLimit(1)
            }
        }
    }

    private func press(_ key: RemoteKey) {
        guard connected else { return }
        stopWriting()
        remote.press(key)
        activeKey = key
        let token = UUID()
        pulse = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            if pulse == token { activeKey = nil }
        }
    }

    private func finishSearch() {
        if !search.isEmpty && connected {
            remote.confirmLiveText { _ in }
        }
        // Release the local field immediately. Any outstanding text is
        // flushed by RemoteController before subsequent navigation keys.
        stopWriting()
    }

    private func stopWriting() {
        writing = false
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if event.type == .keyUp {
            if isReturn && swallowedReturn == event.keyCode {
                swallowedReturn = nil
                return nil
            }
            return event
        }
        guard NSApp.isActive, !showSettings, !showDependency, NSApp.keyWindow?.attachedSheet == nil else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "l": writing = true; return nil
            case "h":
                guard !modifiers.contains(.option), !modifiers.contains(.control), !modifiers.contains(.shift) else { return event }
                if !event.isARepeat { press(.home) }
                return nil
            case ",": stopWriting(); if remote.state == .missingADB { showDependency = true } else { showSettings = true }; return nil
            default: return event
            }
        }
        if modifiers.contains(.option) || modifiers.contains(.control) { return event }
        let inTextField = writing || NSApp.keyWindow?.firstResponder is NSTextView
        if isReturn {
            // Holding the Return key after focus changes must not produce OK.
            if swallowedReturn == event.keyCode {
                if event.isARepeat { return nil }
                swallowedReturn = nil // a distinct press after a lost key-up
            }
            if inTextField || remote.sendingText {
                swallowedReturn = event.keyCode
                if !event.isARepeat && !remote.sendingText { finishSearch() }
                return nil
            }
        }
        if inTextField {
            if event.keyCode == 53 { stopWriting(); return nil }
            return event
        }
        let key: RemoteKey?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 36, 76, 49: key = .select
        case 53, 51, 117: key = .back
        case 115: key = .home
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w": key = .up
            case "s": key = .down
            case "a": key = .left
            case "d": key = .right
            case "m": key = .menu
            default: key = nil
            }
        }
        guard let key else { return event }
        if event.isARepeat {
            guard [.up, .down, .left, .right].contains(key), event.timestamp - lastRepeat >= (remote.fastMode ? 0.060 : 0.30) else { return nil }
            lastRepeat = event.timestamp
        }
        press(key)
        return nil
    }
}

/// A real annular hit region: clicking any part of a direction's quarter
/// triggers that direction, with the middle reserved for OK.
private struct PadSector: Shape {
    let angle: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let outer = radius - 3
        let inner = radius * 0.435
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let radians = degrees * Double.pi / 180
            return CGPoint(x: center.x + CGFloat(cos(radians)) * r, y: center.y + CGFloat(sin(radians)) * r)
        }
        var path = Path()
        let from = angle - 44, to = angle + 44
        path.move(to: point(from, outer))
        for i in 1...36 { path.addLine(to: point(from + (to - from) * Double(i) / 36, outer)) }
        path.addLine(to: point(to, inner))
        for i in 1...36 { path.addLine(to: point(to - (to - from) * Double(i) / 36, inner)) }
        path.closeSubpath()
        return path
    }
}

private struct PadSectorLabel: View {
    let angle: Double
    let icon: String
    let hint: String
    let tint: Color
    let lit: Bool

    var body: some View {
        ZStack {
            PadSector(angle: angle)
                .fill(tint.opacity(lit ? 0.19 : 0.012))
                .overlay(PadSector(angle: angle).stroke(tint.opacity(lit ? 0.44 : 0.065), lineWidth: 0.7))
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(lit ? tint : .white.opacity(0.92))
                    .shadow(color: tint.opacity(lit ? 0.80 : 0.32), radius: lit ? 6 : 3.5)
                Text(hint)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.82))
            }
            .offset(x: CGFloat(cos(angle * .pi / 180)) * padDiameter * 0.349, y: CGFloat(sin(angle * .pi / 180)) * padDiameter * 0.349)
            .allowsHitTesting(false)
        }
        .frame(width: padDiameter, height: padDiameter)
        .contentShape(PadSector(angle: angle))
        .animation(.easeOut(duration: 0.09), value: lit)
    }
}

private struct NeonButtonStyle: ButtonStyle {
    var tint: Color
    var radius: CGFloat
    var strength: Double = 0.70
    var lit: Bool = false
    var disabledOpacity: Double = 0.36
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let bright = configuration.isPressed || lit
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(tint.opacity(bright ? 0.56 : strength * 0.35), lineWidth: bright ? 4 : 3)
                        .blur(radius: bright ? 6 : 4)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(colors: [bright ? tint.opacity(0.16) : keySurface, appBackground], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(LinearGradient(colors: [tint.opacity(bright ? 1 : strength), tint.opacity(bright ? 0.84 : strength * 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: bright ? 1.8 : 1.3)
                }
            }
            .scaleEffect(bright ? 0.95 : 1)
            .opacity(enabled ? 1 : disabledOpacity)
            .animation(.easeOut(duration: 0.10), value: bright)
            .contentShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct DependencySetup: View {
    @ObservedObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34, weight: .medium)).foregroundStyle(amber)
            Text("Preparar conexión").font(.system(size: 23, weight: .bold, design: .rounded))
            Text("Solo falta ADB. Se descargará desde el sitio oficial de Android y se instalará en tu carpeta de usuario.")
                .foregroundStyle(muted).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Link("Términos de Android SDK", destination: URL(string: "https://developer.android.com/studio/terms")!)
                .font(.system(size: 12)).foregroundStyle(amber)
            if !error.isEmpty { Text(error).foregroundStyle(redLED).font(.system(size: 12)) }
            if installing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Descargando e instalando…").font(.system(size: 12))
                }
            }
            HStack {
                Button("Cancelar") { dismiss() }.disabled(installing)
                Spacer()
                Button("Aceptar e instalar") {
                    installing = true
                    error = ""
                    remote.installDependency { failure in
                        installing = false
                        if let failure { error = failure } else { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).disabled(installing).tint(accent)
            }
        }
        .padding(24).frame(width: 345)
        .interactiveDismissDisabled(installing)
    }
}

struct ConnectionSettings: View {
    @ObservedObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "5555"
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuración").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Conexión con tu dispositivo").foregroundStyle(muted)
            VStack(alignment: .leading, spacing: 5) {
                Text("Dirección IP").font(.system(size: 12, weight: .semibold))
                TextField("Dirección IPv4", text: $host).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Puerto ADB").font(.system(size: 12, weight: .semibold))
                TextField("5555", text: $port).textFieldStyle(.roundedBorder)
            }
            Toggle("Reconectar automáticamente", isOn: $remote.autoReconnect).toggleStyle(.switch)
            Text("Ambos dispositivos deben estar en la misma red y la depuración ADB debe estar autorizada en la TV.")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Guardar y conectar") {
                    if remote.configure(host: host, port: port) { dismiss() }
                    else { error = "Introduce una IP válida y un puerto del 1 al 65535." }
                }.keyboardShortcut(.defaultAction).tint(accent)
            }
        }
        .padding(22).frame(width: 365)
        .onAppear {
            let pieces = remote.endpoint.split(separator: ":")
            if let ip = pieces.first { host = String(ip) }
            if pieces.count > 1 { port = String(pieces[1]) }
        }
    }
}
