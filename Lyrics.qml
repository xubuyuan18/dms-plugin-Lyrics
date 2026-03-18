import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

/**
 * Lyrics Plugin for DankMaterialShell
 * 提供多源歌词获取和显示功能
 */

PluginComponent {
    id: root

    // ============================================
    // 配置属性
    // ============================================
    property bool cachingEnabled: pluginData.cachingEnabled ?? true
    property bool lrclibEnabled: pluginData.lrclibEnabled ?? true
    property bool neteaseEnabled: pluginData.neteaseEnabled ?? true
    property bool customApiEnabled: pluginData.customApiEnabled ?? false
    property string customApiUrl: pluginData.customApiUrl ?? ""
    property string customApiMethod: pluginData.customApiMethod ?? "GET"

    // ============================================
    // MPRIS 播放器
    // ============================================
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    property var allPlayers: MprisController.availablePlayers

    // ============================================
    // 状态枚举
    // ============================================

    // 状态码（用于 lrclibStatus, neteaseStatus, cacheStatus）
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

    // 歌词获取生命周期
    QtObject {
        id: lyricState
        readonly property int idle: 0
        readonly property int loading: 1
        readonly property int synced: 2
        readonly property int notFound: 3
    }

    // 歌词来源
    QtObject {
        id: lyricSrc
        readonly property int none: 0
        readonly property int lrclib: 1
        readonly property int cache: 2
        readonly property int netease: 3
        readonly property int custom: 4
    }

    // ============================================
    // 歌词状态
    // ============================================
    property var lyricsLines: []
    property int currentLineIndex: -1
    property bool lyricsLoading: lyricStatus === lyricState.loading

    // 内部状态跟踪
    property string _lastFetchedTrack: ""
    property string _lastFetchedArtist: ""
    property string _lastSyncedTrack: ""
    property string _lastSyncedArtist: ""
    property var _cancelActiveFetch: null

    // 各源状态
    property int lrclibStatus: status.none
    property int neteaseStatus: status.none
    property int cacheStatus: status.none

    // 当前状态
    property int lyricStatus: lyricState.idle
    property int lyricSource: lyricSrc.none

    // 当前歌曲信息
    property string currentTitle: activePlayer?.trackTitle ?? ""
    property string currentArtist: activePlayer?.trackArtist ?? ""
    property string currentAlbum: activePlayer?.trackAlbum ?? ""
    property real currentDuration: activePlayer?.length ?? 0

    // 强制更新标志（用于轮询）
    property bool _forceUpdate: false

    // ============================================
    // 计算属性
    // ============================================
    property string currentLyricText: {
        if (lyricsLoading)
            return "搜索歌词中…";
        if (lyricsLines.length > 0 && currentLineIndex >= 0)
            return lyricsLines[currentLineIndex].text || "♪ ♪ ♪";
        if (currentTitle)
            return currentTitle;
        return "暂无歌词";
    }

    // ============================================
    // 定时器
    // ============================================

    // 防抖定时器 - 避免标题和艺术家同时变化时重复获取
    Timer {
        id: fetchDebounceTimer
        interval: 300
        onTriggered: root.fetchLyricsIfNeeded()
    }

    onCurrentTitleChanged: fetchDebounceTimer.restart()
    onCurrentArtistChanged: fetchDebounceTimer.restart()

    // XHR 超时定时器
    Timer {
        id: xhrTimeoutTimer
        repeat: false
        property var onTimeout: null
        onTriggered: if (onTimeout) onTimeout()
    }

    // XHR 重试定时器
    Timer {
        id: xhrRetryTimer
        repeat: false
        property var onRetry: null
        onTriggered: if (onRetry) onRetry()
    }

    // ============================================
    // 状态管理函数
    // ============================================

    /**
     * 重置歌词状态（保留 _lastFetchedTrack/_lastFetchedArtist）
     */
    function _resetLyricsState() {
        lyricsLines = [];
        currentLineIndex = -1;
        lrclibStatus = status.none;
        neteaseStatus = status.none;
        cacheStatus = status.none;
        lyricStatus = lyricState.loading;
        lyricSource = lyricSrc.none;
    }

    /**
     * 设置最终"未找到"状态
     */
    function _setFinalNotFound(sourceStatusVal) {
        lrclibStatus = sourceStatusVal;
        neteaseStatus = sourceStatusVal;
        lyricStatus = lyricState.notFound;
        root._cancelActiveFetch = null;
    }

    // ============================================
    // 缓存管理
    // ============================================

    readonly property string _cacheDir: (Quickshell.env("HOME") || "") + "/.cache/Lyrics"
    property bool _cacheDirReady: false

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root._cacheDir]
        running: false
    }

    function _ensureCacheDir() {
        if (_cacheDirReady) return;
        _cacheDirReady = true;
        mkdirProcess.running = true;
    }

    /**
     * FNV-1a 32位哈希
     */
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

    function _cacheFilePath(title, artist) {
        return _cacheDir + "/" + _cacheKey(title, artist) + ".json";
    }

    /**
     * 从缓存读取歌词
     */
    function readFromCache(title, artist, callback) {
        cacheReaderComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            callback: callback
        });
    }

    /**
     * 写入缓存
     */
    function writeToCache(title, artist, lines, source) {
        _ensureCacheDir();
        cacheWriterComponent.createObject(root, {
            path: _cacheFilePath(title, artist),
            cTitle: title,
            cArtist: artist,
            cLines: lines,
            cSource: source
        });
    }

    // 缓存读取组件
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

    // 缓存写入组件
    Component {
        id: cacheWriterComponent
        FileView {
            property string cTitle
            property string cArtist
            property var cLines
            property int cSource

            blockWrites: false
            atomicWrites: true

            Component.onCompleted: {
                setText(JSON.stringify({
                    lines: cLines,
                    source: cSource,
                    cachedAt: new Date().toISOString()
                }));
            }

            onSaved: {
                console.info("[Lyrics] 缓存: 已保存 \"" + cTitle + "\" 的歌词 (" + cLines.length + " 行)");
                destroy();
            }
            onSaveFailed: {
                console.warn("[Lyrics] 缓存: 保存失败 \"" + cTitle + "\"");
                destroy();
            }
        }
    }

    // ============================================
    // 歌词获取协调
    // ============================================

    /**
     * 主入口：检查并获取歌词
     * 优先级：自定义API → 缓存 → 网易云 → lrclib
     */
    function fetchLyricsIfNeeded() {
        if (!currentTitle) return;

        // 如果歌曲相同且已同步，跳过
        if (currentTitle === _lastFetchedTrack &&
            currentArtist === _lastFetchedArtist &&
            lyricStatus === lyricState.synced) {
            return;
        }

        // 取消进行中的请求
        if (_cancelActiveFetch) {
            _cancelActiveFetch();
            _cancelActiveFetch = null;
        }

        _lastFetchedTrack = currentTitle;
        _lastFetchedArtist = currentArtist;
        _resetLyricsState();

        _logSongChange();

        var capturedTitle = currentTitle;
        var capturedArtist = currentArtist;

        // 优先级1：自定义API
        if (customApiEnabled && customApiUrl) {
            _fetchFromCustomApi(capturedTitle, capturedArtist);
            return;
        }

        // 优先级2：缓存
        if (cachingEnabled) {
            _tryCacheThenFetch(capturedTitle, capturedArtist);
        } else {
            cacheStatus = status.cacheDisabled;
            _startFetchFromSources(capturedTitle, capturedArtist);
        }
    }

    /**
     * 尝试从缓存读取，失败则从源获取
     */
    function _tryCacheThenFetch(title, artist) {
        readFromCache(title, artist, function (cached) {
            // 守卫：歌曲已切换
            if (title !== root._lastFetchedTrack || artist !== root._lastFetchedArtist) return;

            if (cached?.lines?.length > 0) {
                _applyCachedLyrics(cached, title, artist);
                return;
            }

            root.cacheStatus = status.cacheMiss;
            _startFetchFromSources(title, artist);
        });
    }

    /**
     * 应用缓存的歌词
     */
    function _applyCachedLyrics(cached, title, artist) {
        root.lyricsLines = cached.lines;
        root.lyricStatus = lyricState.synced;
        root.lyricSource = cached.source > 0 ? cached.source : lyricSrc.cache;
        root.cacheStatus = status.cacheHit;
        root.lrclibStatus = status.skippedFound;
        root.neteaseStatus = status.skippedFound;
        root._lastSyncedTrack = title;
        root._lastSyncedArtist = artist;
        console.info("[Lyrics] ✓ 缓存: 已加载 \"" + title + "\" 的歌词 (" + cached.lines.length + " 行)");
    }

    /**
     * 从各源获取歌词（网易云优先）
     */
    function _startFetchFromSources(title, artist) {
        if (neteaseEnabled) {
            _fetchFromNetease(title, artist);
        } else {
            lrclibStatus = status.skippedConfig;
            _fetchFromLrclib(title, artist);
        }
    }

    /**
     * 记录歌曲切换日志
     */
    function _logSongChange() {
        var durationStr = currentDuration > 0
            ? (Math.floor(currentDuration / 60) + ":" + ("0" + Math.floor(currentDuration % 60)).slice(-2))
            : "未知";
        console.info("[Lyrics] ▶ 歌曲切换: \"" + currentTitle + "\" - " + currentArtist +
                    (currentAlbum ? " [" + currentAlbum + "]" : "") + " (" + durationStr + ")");
    }

    // ============================================
    // 网络请求工具
    // ============================================

    /**
     * XHR 请求（带重试机制）
     * @returns {Function} 取消函数
     */
    function _xhrRequest(url, method, timeoutMs, onSuccess, onError, customHeaders, postData) {
        const MAX_RETRIES = 2;
        const RETRY_DELAY = 3000;

        var retriesLeft = MAX_RETRIES;
        var attempt = 0;
        var cancelled = false;
        var currentXhr = null;
        var httpMethod = method || "GET";

        function _attempt() {
            attempt++;
            currentXhr = new XMLHttpRequest();
            var done = false;

            // 设置超时
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

            // 状态处理
            currentXhr.onreadystatechange = function () {
                if (currentXhr.readyState !== XMLHttpRequest.DONE || done || cancelled) return;

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

            // 发送请求
            currentXhr.open(httpMethod, url);

            if (customHeaders) {
                for (var key in customHeaders) {
                    currentXhr.setRequestHeader(key, customHeaders[key]);
                }
            } else {
                currentXhr.setRequestHeader("User-Agent", "DankMaterialShell Lyrics/1.5.0");
                currentXhr.setRequestHeader("Accept", "application/json");
            }

            if (httpMethod === "POST" && postData) {
                currentXhr.setRequestHeader("Content-Type", "application/json");
                currentXhr.send(JSON.stringify(postData));
            } else {
                currentXhr.send();
            }
        }

        function _retry(errMsg) {
            if (cancelled) return;

            if (retriesLeft > 0) {
                retriesLeft--;
                console.warn("[Lyrics] 请求失败，重试中 (" + (MAX_RETRIES - retriesLeft) + "/" + MAX_RETRIES + "): " + url);
                xhrRetryTimer.stop();
                xhrRetryTimer.interval = RETRY_DELAY;
                xhrRetryTimer.onRetry = _attempt;
                xhrRetryTimer.start();
            } else {
                onError(errMsg);
            }
        }

        _attempt();

        return function cancel() {
            cancelled = true;
            xhrTimeoutTimer.stop();
            xhrRetryTimer.stop();
            if (currentXhr) currentXhr.abort();
        };
    }

    function _xhrGet(url, timeoutMs, onSuccess, onError, customHeaders) {
        return _xhrRequest(url, "GET", timeoutMs, onSuccess, onError, customHeaders, null);
    }

    // ============================================
    // 歌词源：lrclib.net
    // ============================================

    function _fetchFromLrclib(expectedTitle, expectedArtist) {
        if (!_checkSourceEnabled("lrclib", lrclibEnabled, neteaseEnabled)) return;
        if (_checkAlreadySynced("lrclib")) return;

        lrclibStatus = status.searching;
        console.info("[Lyrics] lrclib: 正在搜索 \"" + expectedTitle + "\"");

        var url = _buildLrclibUrl(expectedTitle, expectedArtist);

        root._cancelActiveFetch = _xhrGet(url, 20000,
            function (responseText, httpStatus) {
                _handleLrclibResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                _handleLrclibError(errMsg, expectedTitle, expectedArtist);
            }
        );
    }

    function _buildLrclibUrl(title, artist) {
        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(artist)
                + "&track_name=" + encodeURIComponent(title);
        if (currentAlbum) url += "&album_name=" + encodeURIComponent(currentAlbum);
        if (currentDuration > 0) url += "&duration=" + Math.round(currentDuration);
        return url;
    }

    function _handleLrclibResponse(responseText, expectedTitle, expectedArtist) {
        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _fallbackAfterLrclib(status.error, "空响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            if (result.statusCode === 404 || result.error) {
                _fallbackAfterLrclib(status.notFound, "未找到", expectedTitle, expectedArtist);
                return;
            }

            if (result.syncedLyrics) {
                _applyLyricsFromSource(result.syncedLyrics, lyricSrc.lrclib, expectedTitle, expectedArtist);
                return;
            }

            if (result.plainLyrics) {
                var plainLines = _plainTextToLines(result.plainLyrics);
                if (plainLines.length > 0) {
                    _applyLyricsLines(plainLines, lyricSrc.lrclib, expectedTitle, expectedArtist);
                    return;
                }
            }

            _fallbackAfterLrclib(status.notFound, "无歌词数据", expectedTitle, expectedArtist);

        } catch (e) {
            _fallbackAfterLrclib(status.error, "解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _handleLrclibError(errMsg, expectedTitle, expectedArtist) {
        console.warn("[Lyrics] lrclib: 请求失败 — " + errMsg);
        _fallbackAfterLrclib(status.error, errMsg, expectedTitle, expectedArtist);
    }

    function _fallbackAfterLrclib(statusVal, reason, title, artist) {
        lrclibStatus = statusVal;
        console.info("[Lyrics] lrclib: " + reason + " - \"" + title + "\"");

        if (neteaseEnabled) {
            _fetchFromNetease(title, artist);
        } else {
            _setFinalNotFound(statusVal);
        }
    }

    // ============================================
    // 歌词源：网易云音乐
    // ============================================

    function _fetchFromNetease(expectedTitle, expectedArtist) {
        if (!_checkSourceEnabled("netease", neteaseEnabled, false)) {
            _setFinalNotFound(status.notFound);
            return;
        }
        if (_checkAlreadySynced("netease")) return;

        neteaseStatus = status.searching;
        console.info("[Lyrics] 网易云: 搜索 \"" + expectedTitle + "\"");

        var searchUrl = "http://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s="
                      + encodeURIComponent(expectedTitle) + "&type=1&offset=0&total=true&limit=2";

        var customHeaders = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": "http://music.163.com/"
        };

        root._cancelActiveFetch = _xhrRequest(searchUrl, "GET", 15000,
            function (responseText, httpStatus) {
                _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                _handleNeteaseError("搜索失败: " + errMsg, expectedTitle, expectedArtist);
            },
            customHeaders
        );
    }

    function _handleNeteaseSearchResponse(responseText, expectedTitle, expectedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var songs = result?.result?.songs;

            if (!songs || songs.length === 0) {
                _handleNeteaseError("未找到歌曲", expectedTitle, expectedArtist);
                return;
            }

            var matchedSong = _findBestMatch(songs, expectedTitle);
            var songId = matchedSong.id;
            var songName = matchedSong.name;
            var artistName = matchedSong.artists?.[0]?.name || "未知";

            console.info("[Lyrics] 网易云: 匹配 \"" + songName + "\" - " + artistName);

            _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, songName, artistName);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle);
        }
    }

    function _fetchNeteaseLyrics(songId, expectedTitle, expectedArtist, matchedName, matchedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var lyricUrl = "https://api.paugram.com/netease/?id=" + encodeURIComponent(songId);

        root._cancelActiveFetch = _xhrGet(lyricUrl, 15000,
            function (responseText, httpStatus) {
                _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist, matchedName, matchedArtist);
            },
            function (errMsg) {
                _handleNeteaseError("歌词请求失败: " + errMsg, expectedTitle, expectedArtist);
            }
        );
    }

    function _handleNeteaseLyricResponse(responseText, expectedTitle, expectedArtist, matchedName, matchedArtist) {
        if (!_isCurrentTrack(expectedTitle, expectedArtist)) return;

        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空搜索响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);

            if (!result.title) {
                _handleNeteaseError("无歌曲数据", expectedTitle, expectedArtist);
                return;
            }

            var lyricText = result.lyric || "";
            if (lyricText.trim() === "") {
                _handleNeteaseError("该歌曲无歌词", expectedTitle, expectedArtist);
                return;
            }

            var lines = parseLrc(lyricText);
            if (lines.length === 0) {
                _handleNeteaseError("LRC解析失败", expectedTitle, expectedArtist);
                return;
            }

            _applyLyricsLines(lines, lyricSrc.netease, expectedTitle, expectedArtist);
            console.info("[Lyrics] 网易云: 匹配 \"" + matchedName + "\" - " + matchedArtist);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _handleNeteaseError(reason, title, artist) {
        neteaseStatus = status.error;
        console.warn("[Lyrics] 网易云: " + reason + " - \"" + title + "\"");

        // 网易云失败时，回退到 lrclib
        if (lrclibEnabled) {
            console.info("[Lyrics] 网易云失败，尝试 lrclib...");
            _fetchFromLrclib(title, artist);
        } else {
            _setFinalNotFound(status.error);
        }
    }

    // ============================================
    // 歌词源：自定义 API
    // ============================================

    function _fetchFromCustomApi(expectedTitle, expectedArtist) {
        console.info("[Lyrics] 自定义API: 获取 \"" + expectedTitle + "\"");

        var url = customApiUrl
            .replace(/{title}/g, encodeURIComponent(expectedTitle))
            .replace(/{artist}/g, encodeURIComponent(expectedArtist))
            .replace(/{album}/g, encodeURIComponent(currentAlbum || ""));

        var postData = customApiMethod === "POST" ? {
            title: expectedTitle,
            artist: expectedArtist,
            album: currentAlbum || ""
        } : null;

        root._cancelActiveFetch = _xhrRequest(url, customApiMethod, 20000,
            function (responseText, httpStatus) {
                _handleCustomApiResponse(responseText, expectedTitle, expectedArtist);
            },
            function (errMsg) {
                console.warn("[Lyrics] 自定义API: 失败 - " + errMsg);
                _fetchFromCacheOrBuiltin(expectedTitle, expectedArtist);
            },
            null,
            postData
        );
    }

    function _handleCustomApiResponse(responseText, expectedTitle, expectedArtist) {
        var rawData = (responseText || "").trim();
        if (rawData.length === 0) {
            _handleNeteaseError("空歌词响应", expectedTitle, expectedArtist);
            return;
        }

        try {
            var result = JSON.parse(rawData);
            var lyricText = result.lyrics || result.lyric || result.lrc || result.content || result.data;

            if (!lyricText || lyricText.trim() === "") {
                _fallbackToBuiltin("响应中无歌词", expectedTitle, expectedArtist);
                return;
            }

            var lines = parseLrc(lyricText);
            if (lines.length === 0) {
                lines = _plainTextToLines(lyricText);
            }

            if (lines.length === 0) {
                _fallbackToBuiltin("解析失败", expectedTitle, expectedArtist);
                return;
            }

            _applyLyricsLines(lines, lyricSrc.custom, expectedTitle, expectedArtist);

        } catch (e) {
            _handleNeteaseError("解析失败: " + e, expectedTitle, expectedArtist);
        }
    }

    function _fallbackToBuiltin(reason, title, artist) {
        console.warn("[Lyrics] 自定义API: " + reason + "，回退到内置源");
        _fetchFromCacheOrBuiltin(title, artist);
    }

    function _fetchFromCacheOrBuiltin(title, artist) {
        if (cachingEnabled) {
            readFromCache(title, artist, function (cached) {
                if (cached?.lines?.length > 0) {
                    _applyCachedLyrics(cached, title, artist);
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

    // ============================================
    // 歌词处理辅助函数
    // ============================================

    function _checkSourceEnabled(name, enabled, hasFallback) {
        if (!enabled) {
            if (name === "lrclib") lrclibStatus = status.skippedConfig;
            if (name === "netease") neteaseStatus = status.skippedConfig;
            console.info("[Lyrics] " + name + ": 已禁用，跳过");
            return false;
        }
        return true;
    }

    function _checkAlreadySynced(name) {
        if (lyricStatus === lyricState.synced) {
            if (name === "lrclib") lrclibStatus = status.skippedFound;
            if (name === "netease") neteaseStatus = status.skippedFound;
            console.info("[Lyrics] " + name + ": 已跳过 (已找到歌词)");
            return true;
        }
        return false;
    }

    function _isCurrentTrack(title, artist) {
        return title === root._lastFetchedTrack && artist === root._lastFetchedArtist;
    }

    function _findBestMatch(songs, expectedTitle) {
        var lowerTitle = expectedTitle.toLowerCase();
        for (var i = 0; i < songs.length; i++) {
            if (songs[i].name.toLowerCase() === lowerTitle) {
                return songs[i];
            }
        }
        return songs[0];
    }

    function _plainTextToLines(plainText) {
        return plainText
            .split("\n")
            .map(function(line) { return { time: 0, text: line.trim() }; })
            .filter(function(l) { return l.text !== ""; });
    }

    function _applyLyricsFromSource(lrcText, source, title, artist) {
        var lines = parseLrc(lrcText);
        _applyLyricsLines(lines, source, title, artist);
    }

    function _applyLyricsLines(lines, source, title, artist) {
        root.lyricsLines = lines;
        root.lyricStatus = lyricState.synced;
        root.lyricSource = source;
        root._lastSyncedTrack = title;
        root._lastSyncedArtist = artist;
        root._cancelActiveFetch = null;

        if (source === lyricSrc.lrclib) lrclibStatus = status.found;
        if (source === lyricSrc.netease) neteaseStatus = status.found;

        var sourceName = source === lyricSrc.lrclib ? "lrclib" :
                        source === lyricSrc.netease ? "网易云" :
                        source === lyricSrc.custom ? "自定义API" : "未知";

        console.info("[Lyrics] ✓ " + sourceName + ": 已找到歌词 (" + lines.length + " 行) - \"" + title + "\"");

        if (cachingEnabled) {
            writeToCache(title, artist, lines, source);
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
        spacing: 8

        // 网易云指示器 - 带图标的圆角矩形（优先显示）
        Rectangle {
            width: 56
            height: 24
            radius: 12
            color: Theme.withAlpha(root._apiStatusColor(root.neteaseStatus), 0.25)
            border.color: root._apiStatusColor(root.neteaseStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                    name: "cloud"
                    size: 14
                    color: "#000000"
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "网易"
                    font.pixelSize: 11
                    color: "#000000"
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root.chipLabel(root.neteaseStatus)
            ToolTip.visible: neteaseMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: neteaseMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // lrclib 指示器 - 带图标的圆角矩形
        Rectangle {
            width: 56
            height: 24
            radius: 12
            color: Theme.withAlpha(root._apiStatusColor(root.lrclibStatus), 0.25)
            border.color: root._apiStatusColor(root.lrclibStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                    name: "library_music"
                    size: 14
                    color: "#000000"
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "LRC"
                    font.pixelSize: 11
                    color: "#000000"
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root.chipLabel(root.lrclibStatus)
            ToolTip.visible: lrclibMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: lrclibMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // 缓存指示器 - 带图标的圆角矩形
        Rectangle {
            width: 56
            height: 24
            radius: 12
            color: Theme.withAlpha(root._apiStatusColor(root.cacheStatus), 0.25)
            border.color: root._apiStatusColor(root.cacheStatus)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                DankIcon {
                    name: "storage"
                    size: 14
                    color: "#000000"
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "缓存"
                    font.pixelSize: 11
                    color: "#000000"
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ToolTip.text: root.chipLabel(root.cacheStatus)
            ToolTip.visible: cacheMouse.containsMouse
            ToolTip.delay: 500

            MouseArea {
                id: cacheMouse
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
                        // - 位置：卡片右上角，部分超出边界营造视觉层次感
                        // - z-index: 10，确保封面显示在歌曲信息上方
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

                                // Artist & Album - 字体跟随歌词字体设置
                                Column {
                                    width: parent.width
                                    spacing: 4
                                    visible: root.activePlayer

                                    Row {
                                        spacing: Theme.spacingS
                                        DankIcon {
                                            name: "person"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: root.currentArtist || "未知艺术家"
                                            font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeMedium + 2
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Row {
                                        spacing: Theme.spacingS
                                        visible: root.currentAlbum !== ""
                                        DankIcon {
                                            name: "album"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: root.currentAlbum
                                            font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeMedium
                                            font.weight: Font.Medium
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // API 状态指示器 - 移动到歌曲信息下方，左对齐
                                ApiStatusIndicators {
                                    visible: root.activePlayer
                                }

                                // Spacer to ensure vertical separation from cover art
                                Item {
                                    width: 1
                                    height: _coverArtContainer.visible ? 24 : 0
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

                                        // 使用 _forceUpdate 触发重新计算进度
                                        property real progress: {
                                            void root._forceUpdate; // 依赖轮询触发更新
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

                                    // Poll MPRIS position to keep progress bar and time text updated
                                    Timer {
                                        id: progressPollTimer
                                        interval: 100
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
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            color: Theme.surfaceVariantText
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
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    // Playback controls - 放大但保持原有样式
                                    Row {
                                        width: parent.width
                                        height: 48
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: Theme.spacingXL

                                        // Previous button
                                        MouseArea {
                                            width: 44
                                            height: 44
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: {
                                                if (root.activePlayer)
                                                    root.activePlayer.previous();
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "skip_previous"
                                                size: 32
                                                color: Theme.surfaceText
                                            }
                                        }

                                        // Play/Pause button
                                        MouseArea {
                                            width: 56
                                            height: 56
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
                                                radius: 28
                                                color: Theme.primary
                                                opacity: 0.1
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                                                size: 36
                                                color: Theme.primary
                                            }
                                        }

                                        // Next button
                                        MouseArea {
                                            width: 44
                                            height: 44
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: {
                                                if (root.activePlayer)
                                                    root.activePlayer.next();
                                            }

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "skip_next"
                                                size: 32
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
                return "#FF5252";      // 鲜艳红色
            case status.searching:
                return "#FFD740";      // 鲜艳琥珀色
            case status.found:
            case status.cacheHit:
                return "#69F0AE";      // 鲜艳绿色
            case status.none:
            case status.skippedConfig:
            default:
                return "#9E9E9E";      // 中灰色
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

    popoutWidth: 420
    popoutHeight: 300

    Component.onCompleted: {
        console.info("[Lyrics] 插件已加载");
    }
}
