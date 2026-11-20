import Foundation

@main
struct RemoteTests {
    static func main() {
        assert(ADB.endpoint("192.0.2.42", "5555") == "192.0.2.42:5555")
        assert(ADB.endpoint("192.0.2.256", "5555") == nil)
        assert(ADB.endpoint("192.0.2.42;invalid", "5555") == nil)
        assert(ADB.endpoint("192.0.2.42", "99999") == nil)
        let ordinary = ADB.textCommands("star wars")
        assert(ordinary.commands == ["input text 'star%swars'"] && !ordinary.changed)
        let accented = ADB.textCommands("película y niño")
        assert(accented.commands == ["input text 'pelicula%sy%snino'"] && accented.changed)
        let apostrophe = ADB.textCommands("it's")
        assert(apostrophe.commands == ["input text 'it'\\''s'"])
        assert(ADB.textCommands("%s").commands == ["input text '%'", "input text 's'"])
        assert(ADB.textCommands("😃").commands.isEmpty)
        assert(RemoteKey.up.rawValue == "19" && RemoteKey.down.rawValue == "20")
        assert(RemoteKey.select.rawValue == "23" && RemoteKey.back.rawValue == "4")
        assert(ADB.powerState("mWakefulness=Asleep\nDisplay Power: state=OFF") == .asleep)
        assert(ADB.powerState("mWakefulness=Awake\nDisplay Power: state=ON") == .awake)
        assert(ADB.powerState("") == .unknown)
        var commands: [String] = []
        let wake = ADB.wake("adb", target: "192.0.2.42:5555", runCommand: { _, args, _ in
            let command = args.last ?? ""
            commands.append(command)
            return ADBResult(code: 0, output: command.hasPrefix("dumpsys") ? "mWakefulness=Awake\nDisplay Power: state=ON" : "")
        }, pause: { _ in })
        assert(wake == .awake)
        assert(commands.first == "input keyevent KEYCODE_WAKEUP")
        assert(!commands.contains(where: { $0.contains("KEYCODE_POWER") }))
        var wakeEvents = 0
        var polls = 0
        let retry = ADB.wake("adb", target: "192.0.2.42:5555", runCommand: { _, args, _ in
            if args.last == "input keyevent KEYCODE_WAKEUP" {
                wakeEvents += 1
                return ADBResult(code: 0, output: "")
            }
            polls += 1
            return ADBResult(code: 0, output: polls <= 3 ? "mWakefulness=Asleep" : "mWakefulness=Awake")
        }, pause: { _ in })
        assert(retry == .awake && wakeEvents == 2)
        var simulatedPower = "Awake"
        var powerCommands: [String] = []
        let simulatePower: (String, [String], TimeInterval) -> ADBResult = { _, args, _ in
            let command = args.last ?? ""
            if command == "input keyevent KEYCODE_SLEEP" { simulatedPower = "Asleep"; powerCommands.append(command) }
            if command == "input keyevent KEYCODE_WAKEUP" { simulatedPower = "Awake"; powerCommands.append(command) }
            return ADBResult(code: 0, output: command.hasPrefix("dumpsys") ? "mWakefulness=\(simulatedPower)" : "")
        }
        assert(ADB.togglePower("adb", target: "192.0.2.42:5555", runCommand: simulatePower, pause: { _ in }) == .asleep)
        assert(ADB.togglePower("adb", target: "192.0.2.42:5555", runCommand: simulatePower, pause: { _ in }) == .awake)
        assert(ADB.wake("adb", target: "192.0.2.42:5555", runCommand: simulatePower, pause: { _ in }) == .awake)
        assert(powerCommands == ["input keyevent KEYCODE_SLEEP", "input keyevent KEYCODE_WAKEUP", "input keyevent KEYCODE_WAKEUP"])
        assert(ADB.textDelta(from: "", to: "hola") == .init(erase: 0, append: "hola"))
        assert(ADB.textDelta(from: "hola", to: "hola ") == .init(erase: 0, append: " "))
        assert(ADB.textDelta(from: "hola ", to: "hola mundo") == .init(erase: 0, append: "mundo"))
        assert(ADB.textDelta(from: "hola mundo", to: "hola mundo").isEmpty)
        assert(ADB.textDelta(from: "hola mundo", to: "hola") == .init(erase: 6, append: ""))
        assert(ADB.textDelta(from: "hola mundo", to: "hola martes") == .init(erase: 4, append: "artes"))
        assert(ADB.textDelta(from: "hola", to: "") == .init(erase: 4, append: ""))
        assert(ADB.textDelta(from: "pelicula", to: ADB.plainText("película")).isEmpty)
        print("Pruebas de dirección, texto y comandos correctas.")
    }
}
