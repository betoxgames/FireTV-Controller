#!/bin/zsh
set -euo pipefail

print "FireTV Controller — instalador de ADB"
print ""

for adb in /opt/homebrew/bin/adb /usr/local/bin/adb /opt/homebrew/share/android-platform-tools/adb "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x "$adb" ]]; then
        print "ADB ya está instalado. Puedes abrir ControlRemoto.app."
        "$adb" version
        exit 0
    fi
done

print "Se descargarán las herramientas oficiales de Android en tu carpeta de usuario."
print "Consulta los términos y condiciones en:"
print "https://developer.android.com/tools/releases/platform-tools"
printf "¿Aceptas los términos de Android SDK y quieres continuar? [s/N] "
read -r answer
if [[ "${answer:l}" != s && "${answer:l}" != si && "${answer:l}" != sí ]]; then
    print "Instalación cancelada."
    exit 0
fi

sdk_dir="$HOME/Library/Android/sdk"
destination="$sdk_dir/platform-tools"
if [[ -e "$destination" ]]; then
    print "Ya existe una carpeta Platform Tools sin ADB. No se modificará."
    print "Revisa la instalación existente: $destination"
    exit 1
fi

temp_dir="$(mktemp -d -t firetv-platform-tools)"
trap 'rm -rf -- "$temp_dir"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --retry 2 \
    'https://dl.google.com/android/repository/platform-tools-latest-darwin.zip' \
    --output "$temp_dir/platform-tools.zip"
/usr/bin/ditto -x -k "$temp_dir/platform-tools.zip" "$temp_dir"
[[ -x "$temp_dir/platform-tools/adb" ]] || { print "El archivo no incluye un ADB válido."; exit 1; }
mkdir -p "$sdk_dir"
mv -n "$temp_dir/platform-tools" "$destination"
[[ -x "$destination/adb" ]] || { print "No se pudo instalar ADB."; exit 1; }
"$destination/adb" version
print ""
print "Instalación completada. Abre ControlRemoto.app y configura tu TV."
