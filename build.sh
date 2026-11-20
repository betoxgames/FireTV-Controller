#!/bin/zsh
set -euo pipefail
source_dir="${0:A:h}"
app_dir="${source_dir}/dist/ControlRemoto.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$source_dir/Info.plist" "$app_dir/Contents/Info.plist"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" \
    "$source_dir/Sources/ADB.swift" "$source_dir/Sources/FastChannel.swift" "$source_dir/Sources/FireTVRemote.swift" \
    -o "$app_dir/Contents/MacOS/FireTVRemote"
cp "$source_dir/DeviceHelper/FastRemote.jar" "$app_dir/Contents/Resources/FastRemote.jar"
if [[ -f "$source_dir/AppIcon.icns" ]]; then
    cp "$source_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi
# macOS may attach Finder metadata to newly created Desktop bundles.
if xattr -p com.apple.FinderInfo "$app_dir" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$app_dir"
fi
if ! codesign --force --sign - "$app_dir"; then
    # Finder can recreate the metadata between the first check and signing.
    if xattr -p com.apple.FinderInfo "$app_dir" >/dev/null 2>&1; then
        xattr -d com.apple.FinderInfo "$app_dir"
        codesign --force --sign - "$app_dir"
    else
        exit 1
    fi
fi
print -r -- "Aplicación lista: $app_dir"
