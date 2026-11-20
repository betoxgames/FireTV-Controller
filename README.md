# FireTV Controller

## Instalación rápida

1. Descarga el ZIP listo para usar desde [Releases v1.0](https://github.com/betoxgames/FireTV-Controller/releases/tag/v1.0) y descomprímelo.
2. Abre `Instalar-dependencias.command` para descargar las herramientas ADB oficiales; si ya tienes ADB, no instala nada.
3. Abre `ControlRemoto.app`, pulsa el engrane e introduce la IP de tu propio dispositivo y su puerto ADB.

Requiere macOS 13 o posterior. No necesitas Xcode ni compilar nada. La app guarda la dirección únicamente en las preferencias locales y se reconecta automáticamente. No solicita permisos de accesibilidad ni captura las teclas de otras aplicaciones.

También puedes instalar ADB por separado con `brew install android-platform-tools` o desde [Android Platform Tools](https://developer.android.com/tools/releases/platform-tools). La app no está notarizada; si macOS muestra una advertencia, consulta [la documentación de Apple](https://support.apple.com/es-mx/102445) antes de decidir si autorizas la apertura.

## Modo rápido (v2)

La app mantiene un único canal ADB abierto y reutiliza el comando de entrada del dispositivo sin tener que iniciarlo para cada tecla. En la prueba, la mediana de una pulsación pasó de 814 ms a 14 ms (58 veces más rápido). La luz verde/roja indica el estado de conexión y muestra el tiempo de respuesta de la última comprobación o pulsación. La app recurre al modo convencional si el canal rápido no está disponible. El pequeño auxiliar se coloca en `/data/local/tmp` del dispositivo, no instala una aplicación ni abre un puerto y se detiene al cerrarse la conexión ADB. No requiere permisos adicionales. La navegación real también depende de cómo responda cada aplicación del dispositivo.

## Navegación

| Teclas | Acción |
|---|---|
| W / ↑ | Arriba |
| A / ← | Izquierda |
| S / ↓ | Abajo |
| D / → | Derecha |
| Enter / Espacio | Aceptar |
| Esc / Retroceso | Atrás |
| Home | Inicio de la TV |
| ⌘ L | Escribir texto |
| ⌘ , | Ajustes de conexión |

El aro direccional y los botones de Atrás, Inicio y Menú (☰) también se pueden pulsar con el mouse.

## Escritura rápida

Abre un campo de búsqueda en tu TV. Escribe en la caja de la Mac y pulsa la lupa o Enter para enviar el texto seguido de Enter. Mientras escribes, las teclas editan el texto local en lugar de navegar por la TV; Esc devuelve el foco al control. La entrada nativa de ADB admite principalmente caracteres latinos básicos: las tildes se adaptan y los caracteres no compatibles se omiten. Algunas aplicaciones tienen teclados propios que no admiten la entrada de ADB.

## Conexión

Si cambia la IP, usa el engrane de la parte superior y guarda la nueva dirección. El puerto habitual es 5555. Asegúrate de que tu Fire TV y la Mac estén en la misma red y de que la depuración ADB esté autorizada. Si aparece una solicitud de autorización en tu TV, acepta únicamente si corresponde a esta Mac.

## Compilar de nuevo

Ejecuta `zsh build.sh` desde esta carpeta. El resultado estará en `dist/ControlRemoto.app`. Requiere Xcode Command Line Tools, macOS 13 o posterior y ADB instalado (Homebrew o Android SDK).
