return _chip(val).icon;
    }
    function chipLabel(val) {
        return _chip(val).label;
    }

    // -------------------------------------------------------------------------
    // UI
    // -------------------------------------------------------------------------

    PluginPopout {
        id: popout
        implicitWidth: 420
        implicitHeight: 420

        // 主内容列
        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingL

            // 顶部：专辑封面 + 歌曲信息
            Row {
                id: topRow
                width: parent.width
                spacing: Theme.spacingL

                // 专辑封面（增大到130x130）
                AlbumCover {
                    id: albumCover
                    width: 130
                    height: 130
                    radius: Theme.cornerRadius
                    imageSource: activePlayer?.artUrl ?? ""
                    fallbackColor: Theme.surfaceContainerHigh
                    fallbackIcon: "album"
                    fallbackIconSize: 56
                    fallbackIconColor: Theme.surfaceVariantText
                }

                // 歌曲信息列
                Column {
                    id: songInfoColumn
                    width: parent.width - albumCover.width - parent.spacing
                    height: albumCover.height
                    spacing: Theme.spacingS

                    // Song title
                    StyledText {
                        text: root.currentTitle || I18n.tr("未知歌曲")
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    // Artist
                    StyledText {
                        text: root.currentArtist || I18n.tr("未知艺术家")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    // Album
                    StyledText {
                        text: root.currentAlbum || ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                    }

                    // 占位符
                    Item { height: Theme.spacingS; width: 1 }

                    // 歌词源状态指示器
                    Row {
                        spacing: Theme.spacingS
                        visible: lyricSource !== lyricSrc.none || lrclibStatus !== status.none || neteaseStatus !== status.none

                        Repeater {
                            model: [
                                { id: "lrclib", label: "lrclib", status: lrclibStatus },
                                { id: "netease", label: "网易云", status: neteaseStatus },
                                { id: "cache", label: "缓存", status: cacheStatus }
                            ]

                            delegate: StyledRect {
                                visible: modelData.status !== status.none && modelData.status !== status.skippedConfig && modelData.status !== status.skippedFound
                                radius: Theme.cornerRadius
                                color: chipColor(modelData.status)
                                height: chipRow.implicitHeight + Theme.spacingS * 2
                                width: chipRow.implicitWidth + Theme.spacingM * 2

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: chipIcon(modelData.status)
                                        size: Theme.iconSizeSmall
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: chipLabel(modelData.status)
                                        font.pixelSize: Theme.fontSizeTiny
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 歌词显示区域
            StyledRect {
                width: parent.width
                height: parent.height - topRow.height - controlsRow.height - parent.spacing * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingS

                    // 当前歌词行（大号）
                    StyledText {
                        text: {
                            if (lyricsLines.length > 0 && currentLineIndex >= 0 && lyricsLines[currentLineIndex].text) {
                                return lyricsLines[currentLineIndex].text;
                            }
                            return currentTitle || I18n.tr("暂无歌词");
                        }
                        font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // 下一句歌词（小号）
                    StyledText {
                        text: {
                            if (lyricsLines.length > 0 && currentLineIndex + 1 < lyricsLines.length) {
                                return lyricsLines[currentLineIndex + 1].text;
                            }
                            return "";
                        }
                        font.pixelSize: (pluginData.lyricsFontSize || Theme.fontSizeLarge) - 4
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: text !== ""
                    }
                }
            }

            // 音乐控件（增大尺寸）
            Row {
                id: controlsRow
                width: parent.width
                height: 64
                spacing: Theme.spacingL
                anchors.horizontalCenter: parent.horizontalCenter

                // 上一首（增大到52x52）
                MouseArea {
                    id: prevButton
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter

                    onClicked: activePlayer?.previous()

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: prevButton.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        DankIcon {
                            anchors.centerIn: parent
                            name: "skip_previous"
                            size: 32
                            color: Theme.surfaceText
                        }
                    }
                }

                // 播放/暂停（增大到64x64）
                MouseArea {
                    id: playPauseButton
                    width: 64
                    height: 64
                    anchors.verticalCenter: parent.verticalCenter

                    onClicked: activePlayer?.playPause()

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: playPauseButton.pressed ? Theme.primaryContainer : Theme.primary

                        DankIcon {
                            anchors.centerIn: parent
                            name: activePlayer?.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                            size: 40
                            color: Theme.onPrimary
                        }
                    }
                }

                // 下一首（增大到52x52）
                MouseArea {
                    id: nextButton
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter

                    onClicked: activePlayer?.next()

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: nextButton.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        DankIcon {
                            anchors.centerIn: parent
                            name: "skip_next"
                            size: 32
                            color: Theme.surfaceText
                        }
                    }
                }
            }

            // 进度条和时间（对齐，时间文本加粗）
            Row {
                id: progressRow
                width: parent.width
                spacing: Theme.spacingS

                // 当前时间（加粗）
                StyledText {
                    text: _formatTime(activePlayer?.position || 0)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    width: 45
                    horizontalAlignment: Text.AlignRight
                }

                // 进度条
                Slider {
                    id: progressSlider
                    width: parent.width - 90 - parent.spacing * 2
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter

                    from: 0
                    to: activePlayer?.length || 0
                    value: activePlayer?.position || 0

                    onMoved: {
                        if (activePlayer) {
                            activePlayer.position = value;
                        }
                    }
                }

                // 总时长（加粗）
                StyledText {
                    text: _formatTime(activePlayer?.length || 0)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    width: 45
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }
    }

    // 状态栏显示
    Row {
        anchors.fill: parent
        spacing: Theme.spacingS

        // 专辑封面（增大到40x40）
        AlbumCover {
            id: statusBarCover
            width: 40
            height: 40
            radius: Theme.cornerRadius
            imageSource: activePlayer?.artUrl ?? ""
            fallbackColor: Theme.surfaceContainerHigh
            fallbackIcon: "album"
            fallbackIconSize: 24
            fallbackIconColor: Theme.surfaceVariantText
        }

        // 歌词显示（加粗，歌曲名条件显示）
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            width: Math.min(implicitWidth, 500)

            // 歌词 - 加粗显示
            StyledText {
                text: {
                    if (root.lyricsLines.length > 0 && root.currentLineIndex >= 0 && root.lyricsLines[root.currentLineIndex].text) {
                        return root.lyricsLines[root.currentLineIndex].text;
                    }
                    return "";
                }
                font.pixelSize: pluginData.lyricsFontSize || Theme.fontSizeMedium
                color: Theme.surfaceText
                font.weight: Font.Bold
                maximumLineCount: 1
                elide: Text.ElideRight
                visible: text !== ""
            }

            // 歌曲名 - 仅在没有歌词或纯音乐时显示
            StyledText {
                text: {
                    // 没有歌词或纯音乐时显示歌曲名
                    if (root.lyricsLines.length === 0 || 
                        (root.currentLineIndex >= 0 && root.lyricsLines[root.currentLineIndex] && 
                         _isInstrumentalMarker(root.lyricsLines[root.currentLineIndex].text))) {
                        return root.currentTitle || I18n.tr("暂无歌词");
                    }
                    return "";
                }
                font.pixelSize: (pluginData.lyricsFontSize || Theme.fontSizeMedium) + 2
                color: Theme.surfaceVariantText
                maximumLineCount: 1
                elide: Text.ElideRight
                visible: text !== ""
            }
        }
    }

    // 时间格式化辅助函数
    function _formatTime(seconds) {
        if (!seconds || seconds < 0) return "0:00";
        var mins = Math.floor(seconds / 60);
        var secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }
}