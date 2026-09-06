#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/.build"
output_dir="${1:-$project_dir/dist}"
app_dir="$output_dir/盒盖在线.app"
contents="$app_dir/Contents"

/bin/rm -rf "$build_dir" "$app_dir"
/bin/mkdir -p "$build_dir" "$contents/MacOS" "$contents/Resources"

/usr/bin/swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework ServiceManagement \
    "$project_dir/Sources/main.swift" \
    -o "$contents/MacOS/LidLink"

/bin/cp "$project_dir/Resources/lidlink-helper.sh" "$contents/Resources/lidlink-helper.sh"
/bin/cp "$project_dir/Resources/com.codex.lidlink.plist" "$contents/Resources/com.codex.lidlink.plist"

/usr/bin/plutil -create xml1 "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "盒盖在线" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "盒盖在线" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "com.codex.lidlink" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "LidLink" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "1.0.2" "$contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "3" "$contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$contents/Info.plist"
/usr/bin/plutil -insert NSHumanReadableCopyright -string "Built for local use" "$contents/Info.plist"

/usr/bin/codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
