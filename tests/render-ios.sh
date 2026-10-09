#!/bin/bash
set -euo pipefail
render_dir="${RUNNER_TEMP:-/tmp}/BATRender"
mkdir -p "$render_dir/Render.app/BATWeb"
cp -R iPhone/COURTSIDE/BATWeb/broadcast "$render_dir/Render.app/BATWeb/"
cp iPhone/COURTSIDE/Assets.xcassets/BATLogo.imageset/BATLogo.png "$render_dir/Render.app/BATLogo.png"
cat > "$render_dir/Render.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>it.battv.rendercheck</string><key>CFBundleExecutable</key><string>Renderer</string><key>CFBundleName</key><string>Render</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundlePackageType</key><string>APPL</string><key>LSRequiresIPhoneOS</key><true/><key>UIDeviceFamily</key><array><integer>1</integer></array></dict></plist>
PLIST
xcrun --sdk iphonesimulator swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target "$(uname -m)-apple-ios17.0-simulator" iPhone/COURTSIDE/GameModels.swift iPhone/COURTSIDE/ScoreboardRenderer.swift tests/RenderHarness.swift -o "$render_dir/Render.app/Renderer"
render_device="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for a in d["devices"].values() for v in a if v["name"].startswith("iPhone")))')"
xcrun simctl boot "$render_device" || true
xcrun simctl bootstatus "$render_device" -b
xcrun simctl install "$render_device" "$render_dir/Render.app"
xcrun simctl launch "$render_device" it.battv.rendercheck
render_data="$(xcrun simctl get_app_container "$render_device" it.battv.rendercheck data)"
for render_attempt in {1..30}; do
 if [ -f "$render_data/Documents/result.txt" ]; then break; fi
 if [ -f "$render_data/Documents/error.txt" ]; then cat "$render_data/Documents/error.txt"; exit 1; fi
 sleep 1
done
cat "$render_data/Documents/result.txt"
mkdir -p native-render-check
cp "$render_data/Documents/"*.png native-render-check/
