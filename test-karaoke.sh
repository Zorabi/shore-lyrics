#!/bin/zsh
# Copyright (C) 2026 dongx
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
ROOT="${0:A:h}"
mkdir -p "$ROOT/build"
xcrun swiftc -swift-version 5 -O -parse-as-library \
  "$ROOT/Sources/LyricsCore.swift" "$ROOT/Sources/Library.swift" "$ROOT/Sources/Playback.swift" \
  "$ROOT/Sources/AppModel.swift" "$ROOT/Sources/KaraokeText.swift" "$ROOT/Tests/KaraokeTests.swift" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -o "$ROOT/build/KaraokeTests"
"$ROOT/build/KaraokeTests" "$ROOT/build/karaoke-preview.png"
