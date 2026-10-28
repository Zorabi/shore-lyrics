// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CoreGraphics
let list=CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
for item in list where item[kCGWindowOwnerName as String] as? String == "Dock" {
    var report:[String:Any]=[:]
    for key in [kCGWindowBounds,kCGWindowLayer,kCGWindowAlpha,kCGWindowIsOnscreen]{report[key as String]=item[key as String]}
    if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys){print(String(data:data,encoding:.utf8)!)}
}
print("screens",NSScreen.screens.map{["frame":NSStringFromRect($0.frame),"visible":NSStringFromRect($0.visibleFrame)]})
let defaults=UserDefaults(suiteName:"com.apple.dock")
for key in ["orientation","tilesize","autohide","magnification","largesize"]{print(key,defaults?.object(forKey:key) ?? "unset")}
