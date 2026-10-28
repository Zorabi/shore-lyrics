// Copyright (C) 2026 dongx
// SPDX-License-Identifier: AGPL-3.0-only

// Read-only system Now Playing adapter. No player allowlist, account access,
// AppleEvents, playback commands, or networking.
ObjC.import('Foundation');
ObjC.bindFunction('getppid', ['int', []]);
function readValue(map, suffix) {
    try { return ObjC.unwrap(map.valueForKey('kMRMediaRemoteNowPlayingInfo' + suffix)); }
    catch (_) { return null; }
}
function finite(value) { return typeof value === 'number' && Number.isFinite(value); }
function run() {
    const framework = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    if (!framework.load) throw Error('Cannot load the system media service');
    const api = $.NSClassFromString('MRNowPlayingRequest');
    const parent = $.getppid();
    const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
    while (parent > 1 && $.getppid() === parent) {
        const report = {capturedAt: Date.now() / 1000, playing: false, rate: 0};
        try {
            const client = api.localNowPlayingPlayerPath.client;
            report.bundle = ObjC.unwrap(client.bundleIdentifier) || '';
            const item = api.localNowPlayingItem;
            if (!item.isNil()) {
                const metadata = item.nowPlayingInfo;
                report.title = readValue(metadata, 'Title') || '';
                report.artist = readValue(metadata, 'Artist') || '';
                report.album = readValue(metadata, 'Album') || '';
                const duration = readValue(metadata, 'Duration');
                report.duration = finite(duration) && duration >= 0 ? duration : 0;
                const rawRate = readValue(metadata, 'PlaybackRate');
                try { report.playing = Boolean(api.localIsPlaying); }
                catch (_) { report.playing = finite(rawRate) && rawRate > 0; }
                report.rate = report.playing ? (finite(rawRate) && rawRate > 0 ? rawRate : 1) : 0;
                const anchor = readValue(metadata, 'ElapsedTime');
                const date = readValue(metadata, 'Timestamp');
                const timestamp = date instanceof Date ? date.getTime() / 1000 : Date.parse(date) / 1000;
                let position;
                if (finite(anchor) && (!report.playing || finite(timestamp))) {
                    position = anchor + (report.playing ? Math.max(0, report.capturedAt - timestamp) * report.rate : 0);
                } else {
                    try { position = Number(item.metadata.calculatedPlaybackPosition); } catch (_) {}
                }
                if (finite(position)) report.position = Math.max(0, position);
                // Accept only real local media URLs. Other content identifiers
                // (catalogue IDs, web links) never become filesystem paths.
                const keys = ['ContentItemIdentifier', 'ExternalContentIdentifier', 'AssetURL'];
                for (let i = 0; i < keys.length; i++) {
                    const value = readValue(metadata, keys[i]);
                    if (typeof value === 'string' && value.indexOf('file://') === 0) { report.fileURL = value; break; }
                }
                const id = readValue(metadata, 'ExternalContentIdentifier');
                report.advertisement = typeof id === 'string' && id.indexOf('spotify:ad:') === 0;
            }
        } catch (_) { report.error = '系统媒体服务暂时不可用'; }
        const line = $.NSString.alloc.initWithUTF8String(JSON.stringify(report) + '\n');
        stdout.writeData(line.dataUsingEncoding($.NSUTF8StringEncoding));
        $.NSThread.sleepForTimeInterval(0.35);
    }
}
