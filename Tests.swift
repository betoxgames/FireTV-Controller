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
        print("Pruebas de dirección, texto y comandos correctas.")
    }
}
