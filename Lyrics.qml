import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool cachingEnabled: pluginData.cachingEnabled ?? true
    property bool lrclibEnabled: pluginData.lrclibEnabled ?? true
    property bool neteaseEnabled: pluginData.neteaseEnabled ?? true
    property bool customApiEnabled: pluginData.customApiEnabled ?? false
    property string customApiUrl: pluginData.customApiUrl ?? ""
    property string customApiMethod: pluginData.customApiMethod ?? "GET"

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    property var allPlayers: MprisController.availablePlayers

    // -------------------------------------------------------------------------
    // Enum namespaces
    // -------------------------------------------------------------------------

    // Chip-visible statuses for navidromeStatus, lrclibStatus, and cacheStatus.
    // Values are globally unique so all three properties share one _chipMeta map.
    QtObject {
        id: status
        readonly property int none: 0
        readonly property int searching: 1
        readonly property int found: 2
        readonly property int notFound: 3
        readonly property int error: 4
        readonly property int skippedConfig: 5
        readonly property int skippedFound: 6
        readonly property int skippedPlain: 7
        readonly property int cacheHit: 8
        readonly property int cacheMiss: 9
        readonly property int cacheDisabled: 10
    }

    // Lyrics-fetch lifecycle.
    QtObject {
        id: lyricState
        readonly property int idle: 0
        readonly property int loading: 1
        readonly property int synced: 2
        readonly property int notFound: 3
    }

    // Lyrics sources.
    QtObject {
        id: lyricSrc
        readonly property int none: 0
        readonly property int lrclib: 1
        readonly property int cache: 2
        readonly property int netease: 3
        readonly property int custom: 4
    }

    // -------------------------------------------------------------------------
    // Lyrics state
    // -------------------------------------------------------------------------

    property var lyricsLines: []
    property int currentLineIndex: -1
    property bool lyricsLoading: lyricStatus === lyricState.loading
    property string _lastFetchedTrack: ""
    property string _lastFetchedArtist: ""
    property var _cancelActiveFetch: null

    // Chip status properties
    property int lrclibStatus: status.none
    property int neteaseStatus: status.none
    property int cacheStatus: status.none

    // Fetch state and source
    property int lyricStatus: lyricState.idle
    property int lyricSource: lyricSrc.none

    // Track current song info
    property string currentTitle: activePlayer?.trackTitle ?? ""
    property string currentArtist: activePlayer?.trackArtist ?? ""
    property string currentAlbum: activePlayer?.trackAlbum ?? ""
    property real currentDuration: activePlayer?.length ?? 0

    // Current lyric line for bar pill display

    property string currentLyricText: {
        if (lyricsLoading)
            return "搜索歌词中…";
        if (lyricsLines.length > 0 && currentLineIndex >= 0)
            return lyricsLines[currentLineIndex].text || "♪ ♪ ♪";
        if (currentTitle)
            return currentTitle;
        return "暂无歌词";
    }

    // Debounce timer — avoids double-fetch when title and artist change simultaneously
    Timer {
        id: fetchDebounceTimer
        interval: 300
        onTriggered: root.fetchLyricsIfNeeded()
    }
    onCurrentTitleChanged: fetchDebounceTimer.restart()
    onCurrentArtistChanged: fetchDebounceTimer.restart()

    // Force-update toggle to poll MPRIS position
    property bool _forceUpdate: false

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _resetLyricsState() {
        lyricsLines = [];
        currentLineIndex = -1;
        lrclibStatus = status.none;
        neteaseStatus = status.none;
        cacheStatus = status.none;
        lyricStatus = lyricState.loading;
        lyricSource = lyricSrc.none;
    }

    // Sets the final "no synced lyrics" state after all sources exhausted
    function _setFinalNotFound(sourceStatusVal) {
        lrclibStatus = sourceStatusVal;
        neteaseStatus = sourceStatusVal;
        lyricStatus = lyricState.notFound;
        root._cancelActiveFetch = null;
    }

    // -------------------------------------------------------------------------
    // Cache helpers
    // -------------------------------------------------------------------------

    function _fnv1a32(str) {
        var hash = 0x811c9dc5;
        for (var i = 0; i < str.length; i++) {
            hash = ((hash ^ str.charCodeAt(i)) * 0x01000193) >>> 0;
        }
        return ("00000000" + hash.toString(16)).slice(-8);
    }

    function _cacheKey(title, artist) {
        return _fnv1a32((title + "\x00" + artist).toLowerCase());
    }

    readonly property string _cacheDir: (Quickshell.env("HOME") || "") + "/.cache/musicLyrics"

    function _cacheFilePath(title, artist) {
        return _cacheDir + "/" + _cacheKey(title, artist) + ".json";
    }

    // Static one-shot timer for XHR request timeouts
    Timer {
        id: xhrTimeoutTimer
        repeat: false
        property var onTimeout: null
        onTriggered: if (onTimeout)
            onTimeout()
    }

    // Static one-shot timer for retry delays
    Timer {
        id: xhrRetryTimer
        repeat: false
        property var onRetry: null
        onTriggered: if (onRetry)
            onRetry()
    }

    // Cache directory creation
    property bool _cacheDirReady: false

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root._cacheDir]
        running: false
    }

    function _ensureCacheDir() {
        if (_cacheDirReady)
            return;
        _cacheDirReady = true;
        mkdirProcess.running = true;
    }

    // Cache read using FileView
    Component {
        id: cacheReaderComponent
        FileView {
            property var callback
            blockLoading: true
            preload: true
            onLoaded: {
                try {
                    callback(JSON.parse(text()));
                } catch (e) {
                    callback(null);
                }
                destroy();
            }
            onLoadFailed: {
                callback(null);
                destroy();
            }
        }
    }

    function readFromCache(title, artist, callback) {
        cacheReaderComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            callback: callback
        });
    }

    function writeToCache(title, artist, lines, source) {
        _ensureCacheDir();
        var writer = cacheWriterComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            cTitle: title,
            cArtist: artist
        });
        writer.setText(JSON.stringify({
            lines: lines,
            source: source
        }));
    }

    // Cache write using FileView
    Component {
        id: cacheWriterComponent
        FileView {
            property string cTitle
            property string cArtist
            blockWrites: false
            atomicWrites: true
            onSaved: {
                console.info("[Lyrics] 缓存: 已保存 \"" + cTitle + "\" 的歌词 (" + path + ")");
                destroy();
            }
            onSaveFailed: {
                console.warn("[Lyrics] 缓存: 保存失败 \"" + cTitle + "\"");
                destroy();
            }
        }
    }

    // -------------------------------------------------------------------------
    // Fetch orchestration
    // -------------------------------------------------------------------------

    function fetchLyricsIfNeeded() {
        if (!currentTitle)
            return;
        if (currentTitle === _lastFetchedTrack && currentArtist === _lastFetchedArtist)
            return;

        // Cancel any in-flight XHR before starting fresh
        if (_cancelActiveFetch) {
            _cancelActiveFetch();
            _cancelActiveFetch = null;
        }

        _lastFetchedTrack = currentTitle;
        _lastFetchedArtist = currentArtist;
        _resetLyricsState();

        var durationStr = currentDuration > 0 ? (Math.floor(currentDuration / 60) + ":" + ("0" + Math.floor(currentDuration % 60)).slice(-2)) : "未知";
        console.info("[Lyrics] ▶ 歌曲切换: \"" + currentTitle + "\" - " + currentArtist + (currentAlbum ? " [" + currentAlbum + "]" : "") + " (" + durationStr + ")");

        var capturedTitle = currentTitle;
        var capturedArtist = currentArtist;

        function _startFetch() {
            _fetchFromLrclib(capturedTitle, capturedArtist);
        }

        function _fetchFromNeteaseFallback(title, artist) {
            _fetchFromNetease(title, artist);
        }

        // 如果启用了自定义 API，优先尝试
        if (customApiEnabled && customApiUrl) {
            _fetchFromCustomApi(capturedTitle, capturedArtist);
            return;
        }

        // 尝试缓存
        if (cachingEnabled) {
            readFromCache(capturedTitle, capturedArtist, function (cached) {
                // Guard: track may have changed while the file read was in progress
                if (capturedTitle !== root._lastFetchedTrack || capturedArtist !== root._lastFetchedArtist)
                    return;
                if (cached && cached.lines && cached.lines.length > 0) {
                    root.lyricsLines = cached.lines;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
                    root.cacheStatus = status.cacheHit;
                    root.lrclibStatus = status.skippedFound;
                    root.neteaseStatus = status.skippedFound;
                    console.info("[Lyrics] ✓ 缓存: 已加载 \"" + capturedTitle + "\" 的歌词 (" + cached.lines.length + " 行)");
                    return;
                }
                root.cacheStatus = status.cacheMiss;
                _startFetch();
            });
        } else {
            cacheStatus = status.cacheDisabled;
            _startFetch();
        }
    }

    function _startFetch() {
        // 根据启用的源按顺序获取
        if (lrclibEnabled) {
            _fetchFromLrclib(_lastFetchedTrack, _lastFetchedArtist);
        } else if (neteaseEnabled) {
            lrclibStatus = status.skippedConfig;
            _fetchFromNetease(_lastFetchedTrack, _lastFetchedArtist);
        } else {
            lrclibStatus = status.skippedConfig;
            neteaseStatus = status.skippedConfig;
            _setFinalNotFound(status.notFound);
        }
    }

    // -------------------------------------------------------------------------
    // XMLHttpRequest helper
    // -------------------------------------------------------------------------

    function _xhrRequest(url, method, timeoutMs, onSuccess, onError, customHeaders, postData) {
        var retriesLeft = 2;
        var retryDelay = 3000;
        var attempt = 0;
        var cancelled = false;
        var currentXhr = null;
        var httpMethod = method || "GET";

        function _attempt() {
            attempt++;
            currentXhr = new XMLHttpRequest();
            var done = false;

            xhrTimeoutTimer.stop();
            xhrTimeoutTimer.interval = timeoutMs;
            xhrTimeoutTimer.onTimeout = function () {
                if (!done && !cancelled) {
                    done = true;
                    currentXhr.abort();
                    _retry("timeout");
                }
            };
            xhrTimeoutTimer.start();

            currentXhr.onreadystatechange = function () {
                if (currentXhr.readyState !== XMLHttpRequest.DONE || done || cancelled)
                    return;
                done = true;
                xhrTimeoutTimer.stop();
                if (currentXhr.status === 0) {
                    _retry("network error (status 0)");
                    return;
                }
                var responseBody = (currentXhr.responseText || "").trim();
                if (responseBody.length === 0) {
                    _retry("empty response (HTTP " + currentXhr.status + ")");
                    return;
                }
                onSuccess(currentXhr.responseText, currentXhr.status);
            };
            currentXhr.open(httpMethod, url);
            if (customHeaders) {
                for (var key in customHeaders)
                    currentXhr.setRequestHeader(key, customHeaders[key]);
            } else {
                currentXhr.setRequestHeader("User-Agent", "DankMaterialShell Lyrics/1.5.0 (https://github.com/xubuyuan18/dms-plugin-Lyrics)");
                currentXhr.setRequestHeader("Accept", "application/json");
            }
            
            // 发送请求
            if (httpMethod === "POST" && postData) {
                currentXhr.setRequestHeader("Content-Type", "application/json");
                currentXhr.send(JSON.stringify(postData));
            } else {
                currentXhr.send();
            }
        }

        function _retry(errMsg) {
            if (cancelled)
                return;
            if (retriesLeft > 0) {
                retriesLeft--;
                console.warn("[Lyrics] _xhrRequest: " + errMsg + " — retrying (attempt " + (attempt + 1) + ", " + retriesLeft + " left): " + url);
                xhrRetryTimer.stop();
                xhrRetryTimer.interval = retryDelay;
                xhrRetryTimer.onRetry = _attempt;
                xhrRetryTimer.start();
            } else {
                onError(errMsg);
            }
        }

        _attempt();

        // Return a cancel function the caller can invoke to abort the entire chain
        return function cancel() {
            cancelled = true;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
            if (currentXhr)
                currentXhr.abort();
            console.info("[Lyrics] ⊘ XHR cancelled: " + url);
        };
    }

    // 兼容旧代码的 GET 请求辅助函数
    function _xhrGet(url, timeoutMs, onSuccess, onError, customHeaders) {
        return _xhrRequest(url, "GET", timeoutMs, onSuccess, onError, customHeaders, null);
    }

    // -------------------------------------------------------------------------
    // lrclib.net fetch
    // -------------------------------------------------------------------------

    function _fetchFromLrclib(expectedTitle, expectedArtist) {
        if (!lrclibEnabled) {
            lrclibStatus = status.skippedConfig;
            console.info("[Lyrics] lrclib: 已禁用，跳过");
            // 尝试下一个源
            if (neteaseEnabled) {
                _fetchFromNetease(expectedTitle, expectedArtist);
            } else {
                _setFinalNotFound(status.notFound);
            }
            return;
        }

        if (lyricStatus === lyricState.synced) {
            lrclibStatus = status.skippedFound;
            console.info("[Lyrics] lrclib: 已跳过 (已找到同步歌词)");
            return;
        }

        lrclibStatus = status.searching;
        console.info("[Lyrics] lrclib: 正在搜索 \"" + expectedTitle + "\" - " + expectedArtist);

        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(expectedArtist) + "&track_name=" + encodeURIComponent(expectedTitle);
        if (currentAlbum)
            url += "&album_name=" + encodeURIComponent(currentAlbum);
        if (currentDuration > 0)
            url += "&duration=" + Math.round(currentDuration);

        root._cancelActiveFetch = _xhrGet(url, 20000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[Lyrics] lrclib: response length = " + rawData.length);
            if (rawData.length === 0) {
                root._setFinalNotFound(status.error);
                console.warn("[Lyrics] lrclib: empty response (HTTP " + httpStatus + ")");
                return;
            }
            try {
                var result = JSON.parse(rawData);
                if (result.statusCode === 404 || result.error) {
                    root._setFinalNotFound(status.notFound);
                    console.info("[Lyrics] ✗ lrclib: no lyrics found for \"" + expectedTitle + "\"");
                } else if (result.syncedLyrics) {
                    root.lyricsLines = root.parseLrc(result.syncedLyrics);
                    root.lrclibStatus = status.found;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = lyricSrc.lrclib;
                    console.info("[Lyrics] ✓ lrclib: 已找到同步歌词 (" + root.lyricsLines.length + " 行) - \"" + expectedTitle + "\"");
                    root._cancelActiveFetch = null;
                    if (root.cachingEnabled)
                        root.writeToCache(expectedTitle, expectedArtist, root.lyricsLines, lyricSrc.lrclib);
                } else if (result.plainLyrics) {
                    // Convert plain lyrics to synced format (all at time 0)
                    var plainLines = result.plainLyrics.split("\n").map(function(line) {
                        return { time: 0, text: line.trim() };
                    }).filter(function(l) { return l.text !== ""; });
                    if (plainLines.length > 0) {
                        root.lyricsLines = plainLines;
                        root.lrclibStatus = status.found;
                        root.lyricStatus = lyricState.synced;
                        root.lyricSource = lyricSrc.lrclib;
                        console.info("[Lyrics] ✓ lrclib: 已找到纯文本歌词 (" + plainLines.length + " 行) - \"" + expectedTitle + "\"");
                        root._cancelActiveFetch = null;
                        if (root.cachingEnabled)
                            root.writeToCache(expectedTitle, expectedArtist, plainLines, lyricSrc.lrclib);
                    } else {
                        root._setFinalNotFound(status.notFound);
                        console.info("[Lyrics] ✗ lrclib: 纯文本歌词为空 - \"" + expectedTitle + "\"");
                    }

                } else {
                    root.lrclibStatus = status.notFound;
                    console.info("[Lyrics] ✗ lrclib: 未找到歌词 - \"" + expectedTitle + "\"，尝试网易云...");
                    root._fetchFromNetease(expectedTitle, expectedArtist);
                }
            } catch (e) {
                root.lrclibStatus = status.error;
                console.warn("[Lyrics] lrclib: 解析响应失败 — " + e);
                console.warn("[Lyrics] lrclib: 原始数据: " + rawData.substring(0, 200));
                if (neteaseEnabled) {
                    root._fetchFromNetease(expectedTitle, expectedArtist);
                } else {
                    _setFinalNotFound(status.error);
                }
            }
        }, function (errMsg) {
            root.lrclibStatus = status.error;
            console.warn("[Lyrics] lrclib: 请求失败 — " + errMsg);
            if (neteaseEnabled) {
                root._fetchFromNetease(expectedTitle, expectedArtist);
            } else {
                _setFinalNotFound(status.error);
            }
        });
    }

    // -------------------------------------------------------------------------
    // Netease fetch (via music.163.com search + paugram lyrics)
    // -------------------------------------------------------------------------

    function _fetchFromNetease(expectedTitle, expectedArtist) {
        if (!neteaseEnabled) {
            neteaseStatus = status.skippedConfig;
            console.info("[Lyrics] 网易云: 已禁用，跳过");
            _setFinalNotFound(status.notFound);
            return;
        }

        if (lyricStatus === lyricState.synced) {
            neteaseStatus = status.skippedFound;
            console.info("[Lyrics] 网易云: 已跳过 (已找到同步歌词)");
            return;
        }

        neteaseStatus = status.searching;
        console.info("[Lyrics] 网易云: 步骤1 - 搜索歌曲ID - \"" + expectedTitle + "\" - " + expectedArtist);

        // Step 1: Search song ID using Netease search API
        var searchUrl = "https://music.163.com/api/search/get/web?s=" + encodeURIComponent(expectedTitle + " " + expectedArtist) + "&type=1&limit=5";

        root._cancelActiveFetch = _xhrGet(searchUrl, 15000, function (responseText, httpStatus) {
            // Guard: track may have changed
            if (expectedTitle !== root._lastFetchedTrack || expectedArtist !== root._lastFetchedArtist)
                return;

            var rawData = (responseText || "").trim();
            console.log("[Lyrics] Netease: search response length = " + rawData.length);
            if (rawData.length === 0) {
                root._setFinalNotFound(status.error);
                console.warn("[Lyrics] Netease: empty search response (HTTP " + httpStatus + ")");
                return;
            }

            try {
                var result = JSON.parse(rawData);
                var songs = result?.result?.songs;
                
                if (!songs || songs.length === 0) {
                    root.neteaseStatus = status.notFound;
                    root._setFinalNotFound(status.notFound);
                    console.info("[Lyrics] ✗ 网易云: 未找到歌曲 - \"" + expectedTitle + "\"");
                    return;
                }

                // Find best match (prefer exact title match, fallback to first)
                var matchedSong = songs[0];
                for (var i = 0; i < songs.length; i++) {
                    if (songs[i].name.toLowerCase() === expectedTitle.toLowerCase()) {
                        matchedSong = songs[i];
                        break;
                    }
                }

                var songId = matchedSong.id;
                var songName = matchedSong.name;
                var artistName = matchedSong.artists?.[0]?.name || "未知";

                console.info("[Lyrics] 网易云: 匹配到歌曲 \"" + songName + "\" - " + artistName + " (ID: " + songId + ")");
                
                // Step 2: Fetch lyrics using paugram API with the song ID
                root._fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, songName, artistName);

            } catch (e) {
                root.neteaseStatus = status.error;
                root._setFinalNotFound(status.error);
                console.warn("[Lyrics] 网易云: 解析搜索响应失败 — " + e);
                console.warn("[Lyrics] 网易云: 原始数据: " + rawData.substring(0, 200));
            }
        }, function (errMsg) {
            root.neteaseStatus = status.error;
            root._setFinalNotFound(status.error);
            console.warn("[Lyrics] 网易云: 搜索请求失败 — " + errMsg);
        });
    }

    function _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, matchedName, matchedArtist) {
        console.info("[Lyrics] 网易云: 步骤2 - 获取歌词 ID: " + songId);

        var lyricUrl = "https://api.paugram.com/netease/?id=" + encodeURIComponent(songId);

        root._cancelActiveFetch = _xhrGet(lyricUrl, 15000, function (responseText, httpStatus) {
            // Guard: track may have changed
            if (expectedTitle !== root._lastFetchedTrack || expectedArtist !== root._lastFetchedArtist)
                return;

            var rawData = (responseText || "").trim();
            console.log("[Lyrics] 网易云: 歌词响应长度 = " + rawData.length);
            if (rawData.length === 0) {
                root.neteaseStatus = status.error;
                root._setFinalNotFound(status.error);
                console.warn("[Lyrics] 网易云: 歌词响应为空 (HTTP " + httpStatus + ")");
                return;
            }

            try {
                var result = JSON.parse(rawData);
                
                if (!result.title) {
                    root.neteaseStatus = status.notFound;
                    root._setFinalNotFound(status.notFound);
                    console.info("[Lyrics] ✗ 网易云: 未返回歌曲数据 ID: " + songId);
                    return;
                }

                var lyricText = result.lyric || "";
                if (lyricText.trim() === "") {
                    root.neteaseStatus = status.notFound;
                    root._setFinalNotFound(status.notFound);
                    console.info("[Lyrics] ✗ 网易云: 该歌曲无歌词 - \"" + matchedName + "\"");
                    return;
                }

                var lines = root.parseLrc(lyricText);
                if (lines.length === 0) {
                    root.neteaseStatus = status.notFound;
                    root._setFinalNotFound(status.notFound);
                    console.info("[Lyrics] ✗ 网易云: LRC解析失败 - \"" + matchedName + "\"");
                    return;
                }

                root.lyricsLines = lines;
                root.neteaseStatus = status.found;
                root.lyricStatus = lyricState.synced;
                root.lyricSource = lyricSrc.netease;
                console.info("[Lyrics] ✓ 网易云: 已找到同步歌词 (" + lines.length + " 行) - \"" + expectedTitle + "\" (匹配: \"" + matchedName + "\" - " + matchedArtist + ")");
                root._cancelActiveFetch = null;
                if (root.cachingEnabled)
                    root.writeToCache(expectedTitle, expectedArtist, lines, lyricSrc.netease);
            } catch (e) {
                root.neteaseStatus = status.error;
                root._setFinalNotFound(status.error);
                console.warn("[Lyrics] 网易云: 解析歌词响应失败 — " + e);
                console.warn("[Lyrics] 网易云: 原始数据: " + rawData.substring(0, 200));
            }
        }, function (errMsg) {
            root.neteaseStatus = status.error;
            root._setFinalNotFound(status.error);
            console.warn("[Lyrics] 网易云: 歌词请求失败 — " + errMsg);
        });
    }

    // -------------------------------------------------------------------------
    // Custom API fetch
    // -------------------------------------------------------------------------

    function _fetchFromCustomApi(expectedTitle, expectedArtist) {
        console.info("[Lyrics] 自定义API: 正在获取 \"" + expectedTitle + "\" - " + expectedArtist);

        // 替换 URL 中的变量
        var url = customApiUrl
            .replace(/{title}/g, encodeURIComponent(expectedTitle))
            .replace(/{artist}/g, encodeURIComponent(expectedArtist))
            .replace(/{album}/g, encodeURIComponent(currentAlbum || ""));

        console.info("[Lyrics] 自定义API: 请求 URL: " + url);
        console.info("[Lyrics] 自定义API: 请求方法: " + customApiMethod);

        // 准备 POST 数据（如果是 POST 请求）
        var postData = null;
        if (customApiMethod === "POST") {
            postData = {
                title: expectedTitle,
                artist: expectedArtist,
                album: currentAlbum || ""
            };
        }

        root._cancelActiveFetch = _xhrRequest(url, customApiMethod, 20000, function (responseText, httpStatus) {
            var rawData = (responseText || "").trim();
            console.log("[Lyrics] 自定义API: response length = " + rawData.length);

            if (rawData.length === 0) {
                console.warn("[Lyrics] 自定义API: 空响应，回退到内置源");
                _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
                return;
            }

            try {
                var result = JSON.parse(rawData);

                // 支持多种响应格式
                var lyricText = result.lyrics || result.lyric || result.lrc || result.content || result.data;

                if (!lyricText || lyricText.trim() === "") {
                    console.warn("[Lyrics] 自定义API: 响应中无歌词，回退到内置源");
                    _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
                    return;
                }

                var lines = root.parseLrc(lyricText);
                if (lines.length === 0) {
                    // 尝试将纯文本转换为歌词格式
                    var plainLines = lyricText.split("\n").map(function(line) {
                        return { time: 0, text: line.trim() };
                    }).filter(function(l) { return l.text !== ""; });

                    if (plainLines.length > 0) {
                        lines = plainLines;
                    }
                }

                if (lines.length === 0) {
                    console.warn("[Lyrics] 自定义API: 解析失败，回退到内置源");
                    _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
                    return;
                }

                root.lyricsLines = lines;
                root.lyricStatus = lyricState.synced;
                root.lyricSource = lyricSrc.custom;
                console.info("[Lyrics] ✓ 自定义API: 已找到歌词 (" + lines.length + " 行) - \"" + expectedTitle + "\"");
                root._cancelActiveFetch = null;

                if (root.cachingEnabled)
                    root.writeToCache(expectedTitle, expectedArtist, lines, lyricSrc.custom);

            } catch (e) {
                console.warn("[Lyrics] 自定义API: 解析失败 — " + e);
                console.warn("[Lyrics] 自定义API: 原始数据: " + rawData.substring(0, 200));
                _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
            }
        }, function (errMsg) {
            console.warn("[Lyrics] 自定义API: 请求失败 — " + errMsg + "，回退到内置源");
            _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
        });
    }

    function _fetchFromCacheOrBuiltin(title, artist) {
        // 回退到缓存或内置源
        if (cachingEnabled) {
            readFromCache(title, artist, function (cached) {
                if (cached && cached.lines && cached.lines.length > 0) {
                    root.lyricsLines = cached.lines;
                    root.lyricStatus = lyricState.synced;
                    root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
                    root.cacheStatus = status.cacheHit;
                    root.lrclibStatus = status.skippedFound;
                    root.neteaseStatus = status.skippedFound;
                    console.info("[Lyrics] ✓ 缓存: 已加载 \"" + title + "\" 的歌词 (" + cached.lines.length + " 行)");
                    return;
                }
                root.cacheStatus = status.cacheMiss;
                _fetchFromLrclib(title, artist);
            });
        } else {
            cacheStatus = status.cacheDisabled;
            _fetchFromLrclib(title, artist);
        }
    }

    // -------------------------------------------------------------------------
    // LRC parser
    // -------------------------------------------------------------------------

    function parseLrc(lrcText) {
        var timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/;
        var result = lrcText.split("\n").reduce(function (acc, rawLine) {
            var line = rawLine.trim();
            if (!line)
                return acc;
            var match = timeRegex.exec(line);
            if (!match)
                return acc;
            var millis = parseInt(match[3]);
            if (match[3].length === 2)
                millis *= 10;
            acc.push({
                time: parseInt(match[1]) * 60 + parseInt(match[2]) + millis / 1000,
                text: line.replace(/\[\d{2}:\d{2}\.\d{2,3}\]/g, "").trim()
            });
            return acc;
        }, []);
        result.sort(function (a, b) {
            return a.time - b.time;
        });
        return result;
    }

    // -------------------------------------------------------------------------
    // Position tracking for synced lyrics
    // -------------------------------------------------------------------------

    Timer {
        id: positionTimer
        interval: 200
        running: activePlayer && lyricsLines.length > 0
        repeat: true
        onTriggered: {
            var pos = activePlayer.position || 0;
            var newIndex = -1;
            for (var i = lyricsLines.length - 1; i >= 0; i--) {
                if (pos >= lyricsLines[i].time) {
                    newIndex = i;
                    break;
                }
            }
            if (newIndex !== currentLineIndex)
                currentLineIndex = newIndex;
        }
    }

    // -------------------------------------------------------------------------
    // Status chip helpers
    // -------------------------------------------------------------------------

    readonly property var _chipMeta: ({
            [status.searching]: {
                color: Theme.secondary,
                icon: "hourglass_top",
                label: "搜索中…"
            },
            [status.found]: {
                color: Theme.primary,
                icon: "check_circle",
                label: "已找到 - 同步歌词"
            },
            [status.notFound]: {
                color: Theme.warning,
                icon: "cancel",
                label: "未找到"
            },
            [status.error]: {
                color: Theme.error,
                icon: "error",
                label: "错误"
            },
            [status.skippedConfig]: {
                color: Theme.warning,
                icon: "block",
                label: "已跳过 - 未配置"
            },
            [status.skippedFound]: {
                color: Theme.warning,
                icon: "block",
                label: "已跳过 - 已找到"
            },
            [status.cacheHit]: {
                color: Theme.primary,
                icon: "check_circle",
                label: "缓存命中 - 从缓存加载"
            },
            [status.cacheMiss]: {
                color: Theme.warning,
                icon: "cancel",
                label: "缓存未命中"
            },
            [status.cacheDisabled]: {
                color: Theme.surfaceVariantText,
                icon: "do_not_disturb_on",
                label: "已禁用"
            }
        })

    function _chip(val) {
        return _chipMeta[val] ?? {
            color: Theme.surfaceContainerHighest,
            icon: "radio_button_unchecked",
            label: "空闲"
        };
    }

    function chipColor(val) {
        return _chip(val).color;
    }
    function chipIcon(val) {
        return _chip(val).icon;
    }
    function chipLabel(val) {
        return _chip(val).label;
    }

    // -------------------------------------------------------------------------
    // Bar Pills: show current lyric line
    // -------------------------------------------------------------------------

    horizontalBarPill: root.activePlayer ? hPillComponent : null

    Component {
        id: hPillComponent
        Row {
            spacing: Theme.spacingS

            // Circular album cover using DankAlbumArt
            Rectangle {
                width: 36
                height: 36
                radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceContainerHighest
                clip: true

                DankAlbumArt {
                    anchors.fill: parent
                    activePlayer: root.activePlayer
                    showAnimation: false
                }
            }

            StyledText {
                text: root.currentLyricText
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
                maximumLineCount: 1
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 300)
            }
        }
    }

    verticalBarPill: root.activePlayer ? vPillComponent : null

    Component {
        id: vPillComponent
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "lyrics"
                size: Theme.iconSize
                color: root.lyricsLines.length > 0 ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: "♪"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // -------------------------------------------------------------------------
    // API Status Indicators Component (must be defined before use)
    // -------------------------------------------------------------------------
    component ApiStatusIndicators: Row {
        id: apiIndicators
        spacing: 6

        // 缓存指示器
        Rectangle {
            width: 8
            height: 8
            radius: 2
            color: root._apiStatusColor(root.cacheStatus)
            ToolTip.text: "缓存: " + root.chipLabel(root.cacheStatus)
            ToolTip.visible: cacheMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: cacheMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // lrclib 指示器
        Rectangle {
            width: 8
            height: 8
            radius: 2
            color: root._apiStatusColor(root.lrclibStatus)
            ToolTip.text: "lrclib: " + root.chipLabel(root.lrclibStatus)
            ToolTip.visible: lrclibMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: lrclibMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // 网易云指示器
        Rectangle {
            width: 8
            height: 8
            radius: 2
            color: root._apiStatusColor(root.neteaseStatus)
            ToolTip.text: "网易云: " + root.chipLabel(root.neteaseStatus)
            ToolTip.visible: neteaseMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: neteaseMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }
    }

    // -------------------------------------------------------------------------
    // Popout: Now Playing + Lyrics Sources
    // -------------------------------------------------------------------------

    function _formatDuration(seconds) {
        if (seconds <= 0) return "—";
        var m = Math.floor(seconds / 60);
        var s = Math.floor(seconds % 60);
        return m + ":" + ("0" + s).slice(-2);
    }

    popoutContent: Component {
        PopoutComponent {

            Item {
                width: parent.width
                implicitHeight: popoutLayout.implicitHeight

                Column {
                    id: popoutLayout
                    width: parent.width
                    spacing: Theme.spacingM

                    // ── Now Playing Card ──
                    Rectangle {
                        id: nowPlayingCard
                        width: parent.width
                        height: nowPlayingContent.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: root.activePlayer
                              ? Theme.surfaceContainerHigh
                              : Theme.surfaceContainer
                        clip: true

                        // ============================================
                        // 专辑封面显示区域
                        // ============================================
                        // 设计说明：
                        // - 尺寸：200x200，较大的视觉冲击力
                        // - 位置：卡片右上角，部分超出边界（-50, -33）营造视觉层次感
                        // - z-index: 10，确保封面显示在歌曲信息（z:1）上方
                        // - 使用 DankAlbumArt 组件自动加载和显示封面
                        // ============================================
                        DankAlbumArt {
                            id: _coverArtContainer
                            width: 200
                            height: 200
                            visible: root.activePlayer && (root.activePlayer.trackArtUrl ?? "") !== ""
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -40      // 向上偏移，部分超出卡片边界
                            anchors.rightMargin: -35    // 向右偏移，部分超出卡片边界
                            z: 10                       // 高层级，覆盖在文字上方
                            activePlayer: root.activePlayer
                            showAnimation: true         // 启用加载动画
                        }

                        // API 状态指示器 - 右下角
                        ApiStatusIndicators {
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                                margins: Theme.spacingM
                            }
                            z: 20
                        }

                        Row {
                            id: nowPlayingContent
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top
                                bottom: parent.bottom
                                margins: Theme.spacingM
                            }
                            spacing: Theme.spacingM
                            clip: false
                            z: 1

                            // Track info column (takes full width, cover overlays on top)
                            Column {
                                width: parent.width
                                spacing: Theme.spacingS

                                // Header row: icon + "Now Playing"
                                Row {
                                    spacing: Theme.spacingS
                                    width: parent.width

                                    DankIcon {
                                        name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                                              ? "play_circle" : "pause_circle"
                                        size: 20
                                        color: root.activePlayer ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: root.activePlayer ? (root.activePlayer.identity || "未知播放器") + " 正在播放" : "无活动播放器"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: root.activePlayer ? Theme.primary : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Song title
                                StyledText {
                                    width: parent.width
                                    text: root.currentTitle || "—"
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    wrapMode: Text.WordWrap
                                    visible: root.activePlayer
                                }

                                // Artist & Album
                                Column {
                                    width: parent.width
                                    spacing: 2
                                    visible: root.activePlayer

                                    Row {
                                        spacing: Theme.spacingXS
                                        DankIcon {
                                            name: "person"
                                            size: 14
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: root.currentArtist || "未知艺术家"
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Row {
                                        spacing: Theme.spacingXS
                                        visible: root.currentAlbum !== ""
                                        DankIcon {
                                            name: "album"
                                            size: 14
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: root.currentAlbum
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // Progress bar with timestamps
                                Column {
                                    width: parent.width
                                    spacing: 4
                                    visible: root.activePlayer && root.currentDuration > 0

                                    // ============================================
                                    // macOS Style Progress Bar
                                    // ============================================
                                    // 设计说明：
                                    // - 宽度：与父容器对齐，占满可用空间
                                    // - 轨道高度：16px，较粗的视觉效果
                                    // - 中间圆点：比轨道稍大（20px），突出显示当前位置
                                    // - 点击/拖动：支持跳转播放位置
                                    // ============================================
                                    Item {
                                        id: macProgressBar
                                        width: parent.width
                                        height: 32
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        property real progress: {
                                            if (!root.activePlayer || !root.activePlayer.length) return 0;
                                            return Math.min(1, (root.activePlayer.position || 0) / root.activePlayer.length);
                                        }

                                        // Background track - 轨道背景（16px 高度）
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width
                                            height: 16
                                            radius: 8
                                            color: Theme.surfaceContainerHighest
                                        }

                                        // Progress fill - 进度填充（与轨道同高）
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            width: parent.width * macProgressBar.progress
                                            height: 16
                                            radius: 8
                                            color: Theme.primary
                                        }

                                        // Progress handle - 进度圆点（20px，比轨道稍大）
                                        Rectangle {
                                            id: progressHandle
                                            anchors.verticalCenter: parent.verticalCenter
                                            // 圆点中心与进度填充的右边缘对齐
                                            x: parent.width * macProgressBar.progress - width / 2
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: Theme.surface
                                            border.color: Theme.outlineVariant
                                            border.width: 1
                                        }

                                        // Click and drag to seek - 点击拖动跳转
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: (mouse) => {
                                                if (!root.activePlayer || !root.activePlayer.length) return;
                                                var newProgress = Math.max(0, Math.min(1, mouse.x / parent.width));
                                                root.activePlayer.position = newProgress * root.activePlayer.length;
                                            }
                                            onPositionChanged: (mouse) => {
                                                if (!pressed || !root.activePlayer || !root.activePlayer.length) return;
                                                var newProgress = Math.max(0, Math.min(1, mouse.x / parent.width));
                                                root.activePlayer.position = newProgress * root.activePlayer.length;
                                            }
                                        }
                                    }

                                    // Poll MPRIS position to keep time text updated
                                    Timer {
                                        interval: 50
                                        running: root.activePlayer !== null
                                        repeat: true
                                        onTriggered: {
                                            root._forceUpdate = !root._forceUpdate;
                                        }
                                    }

                                    Row {
                                        width: parent.width

                                        StyledText {
                                            id: _currentTime
                                            text: {
                                                void root._forceUpdate; // depend on polling toggle
                                                if (!activePlayer)
                                                    return "0:00";
                                                const rawPos = Math.max(0, activePlayer.position || 0);
                                                const pos = activePlayer.length ? rawPos % Math.max(1, activePlayer.length) : rawPos;
                                                const minutes = Math.floor(pos / 60);
                                                const seconds = Math.floor(pos % 60);
                                                const timeStr = minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                                                return timeStr;
                                            }
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                        }

                                        Item { width: parent.width - _currentTime.implicitWidth - _endTime.implicitWidth; height: 1 }

                                        StyledText {
                                            id: _endTime
                                            text: {
                                                if (!activePlayer || !activePlayer.length)
                                                    return "0:00";
                                                const dur = Math.max(0, activePlayer.length || 0);
                                                const minutes = Math.floor(dur / 60);
                                                const seconds = Math.floor(dur % 60);
                                                return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
                                            }
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                        }
                                    }

                                    // Playback controls
                                    Row {
                                        width: parent.width
                                        height: 36
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: Theme.spacingL

                                        // Previous button
                                        MouseArea {
                                            width: 36
                                            height: 36
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: {
                                                if (root.activePlayer)
                                                    root.activePlayer.previous();
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "skip_previous"
                                                size: 28
                                                color: Theme.surfaceText
                                            }
                                        }

                                        // Play/Pause button
                                        MouseArea {
                                            width: 40
                                            height: 40
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: {
                                                if (root.activePlayer) {
                                                    if (root.activePlayer.playbackState === MprisPlaybackState.Playing)
                                                        root.activePlayer.pause();
                                                    else
                                                        root.activePlayer.play();
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 20
                                                color: Theme.primary
                                                opacity: 0.1
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                                                size: 32
                                                color: Theme.primary
                                            }
                                        }

                                        // Next button
                                        MouseArea {
                                            width: 36
                                            height: 36
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: {
                                                if (root.activePlayer)
                                                    root.activePlayer.next();
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "skip_next"
                                                size: 28
                                                color: Theme.surfaceText
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // API status indicator color helper
    // -------------------------------------------------------------------------

    function _apiStatusColor(statusVal) {
        switch (statusVal) {
            case status.error:
                return Theme.error;      // 红色
            case status.searching:
                return Theme.warning;    // 黄色
            case status.found:
            case status.cacheHit:
                return Theme.success;    // 绿色
            case status.none:
            case status.skippedConfig:
            default:
                return Theme.surfaceVariantText; // 灰色
        }
    }

    // -------------------------------------------------------------------------
    // Reusable source status card
    // -------------------------------------------------------------------------

    component SourceCard: Rectangle {
        id: sourceCard
        property string icon: ""
        property string label: ""
        property int sourceStatus: 0

        height: 44
        radius: Theme.cornerRadius
        color: sourceStatus === 0
               ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.3)
               : Theme.withAlpha(root.chipColor(sourceStatus), 0.06)
        visible: true

        Row {
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
            }
            spacing: Theme.spacingS

            // Source icon
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: sourceCard.sourceStatus === 0
                       ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)
                       : Theme.withAlpha(root.chipColor(sourceCard.sourceStatus), 0.15)
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    anchors.centerIn: parent
                    name: sourceCard.icon
                    size: 14
                    color: sourceCard.sourceStatus === 0
                           ? Theme.surfaceVariantText
                           : root.chipColor(sourceCard.sourceStatus)
                }
            }

            // Label
            StyledText {
                text: sourceCard.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
                width: 90
            }

            // Status chip – fills remaining width
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - parent.spacing * 2 - 28 - 90
                height: 22

                Rectangle {
                    visible: sourceCard.sourceStatus !== 0
                    anchors.fill: parent
                    radius: 11
                    color: Theme.withAlpha(root.chipColor(sourceCard.sourceStatus), 0.15)

                    Row {
                        id: statusChipContent
                        anchors.centerIn: parent
                        spacing: 4

                        DankIcon {
                            name: root.chipIcon(sourceCard.sourceStatus)
                            size: 12
                            color: root.chipColor(sourceCard.sourceStatus)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.chipLabel(sourceCard.sourceStatus)
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: root.chipColor(sourceCard.sourceStatus)
                            anchors.verticalCenter: parent.verticalCenter
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                    }
                }

                // Idle label when no status
                Rectangle {
                    visible: sourceCard.sourceStatus === 0
                    anchors.fill: parent
                    radius: 11
                    color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.3)

                    StyledText {
                        anchors.centerIn: parent
                        text: "空闲"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    // ============================================
    // 弹出窗口尺寸设置
    // ============================================
    // 设计说明：
    // - 宽度：420px，适合显示歌曲信息
    // - 高度：360px，增加空间让组件自然下沉
    // ============================================
    popoutWidth: 420
    popoutHeight: 360

    Component.onCompleted: {
        console.info("[Lyrics] 插件已加载");
    }
}
