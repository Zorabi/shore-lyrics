#!/bin/zsh
# Copyright (C) 2026 dongx
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/build/岸词.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  "$ROOT"/Sources/*.swift -framework AppKit -framework SwiftUI -framework AVFoundation \
  -o "$APP/Contents/MacOS/ShoreLyrics"
cp "$ROOT/Resources/NowPlaying.js" "$APP/Contents/Resources/NowPlaying.js"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/NOTICE" "$APP/Contents/Resources/NOTICE"
python3 - "$APP" <<'PY'
import pathlib,plistlib,sys
app=pathlib.Path(sys.argv[1])
info={'CFBundleIdentifier':'dongx.shorelyrics','CFBundleName':'岸词','CFBundleDisplayName':'岸词','CFBundleExecutable':'ShoreLyrics','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.3.0','CFBundleVersion':'9','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'13.0','LSUIElement':False,'NSHighResolutionCapable':True,'CFBundleDevelopmentRegion':'zh_CN','NSHumanReadableCopyright':'dongx · 岸词'}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
python3 "$ROOT/Tools/sign-local.py" "$APP"
codesign --verify --deep --strict "$APP"
print "$APP"
