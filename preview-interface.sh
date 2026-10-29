#!/bin/zsh
# Copyright (C) 2026 dongx
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
ROOT="${0:A:h}"
mkdir -p "$ROOT/build"
SOURCES=("$ROOT"/Sources/*.swift)
SOURCES=("${(@)SOURCES:#*/App.swift}")
xcrun swiftc -swift-version 5 -O -parse-as-library "${SOURCES[@]}" \
  "$ROOT/Tools/InterfacePreview.swift" -framework AppKit -framework SwiftUI -framework AVFoundation \
  -o "$ROOT/build/InterfacePreview"
"$ROOT/build/InterfacePreview" "$ROOT/build"
