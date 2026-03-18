import Quickshell
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lyrics"

    StyledText {
        width: parent.width
        text: I18n.tr("Lyrics 设置")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.tr("配置歌词行为和歌词源")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // 缓存设置
    StyledRect {
        width: parent.width
        height: cacheColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: cacheColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: I18n.tr("缓存")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "cachingEnabled"
                label: I18n.tr("本地缓存")
                description: I18n.tr("将下载的歌词保存在本地，加快加载速度并减少网络请求。歌词文件将存储在 ~/.cache/Lyrics 目录下。")
                defaultValue: true
            }

            // 刷新缓存按钮
            Row {
                spacing: Theme.spacingS
                anchors.left: parent.left
                anchors.right: parent.right

                // 清除缓存按钮
                MouseArea {
                    id: clearCacheButton
                    width: clearCacheRow.implicitWidth + Theme.spacingM * 2
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter

                    onClicked: clearCacheDialog.open()

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: clearCacheButton.pressed ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        Row {
                            id: clearCacheRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: I18n.tr("刷新缓存")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                StyledText {
                    id: cacheStatusText
                    text: ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                }
            }
        }
    }

    // 清除缓存确认对话框
    Dialog {
        id: clearCacheDialog
        title: I18n.tr("确认清除缓存")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: StyledText {
            text: I18n.tr("确定要清除所有歌词缓存吗？此操作不可恢复。")
            wrapMode: Text.WordWrap
            width: parent.width
        }

        onAccepted: {
            clearCacheProcess.running = true;
        }
    }

    // 清除缓存进程
    Process {
        id: clearCacheProcess
        command: ["rm", "-rf", (Quickshell.env("HOME") || "") + "/.cache/Lyrics"]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                cacheStatusText.text = I18n.tr("缓存已清除");
                cacheStatusText.color = Theme.primary;
                console.info("[Lyrics] 缓存已清除");
            } else {
                cacheStatusText.text = I18n.tr("清除失败");
                cacheStatusText.color = Theme.error;
                console.warn("[Lyrics] 缓存清除失败");
            }
            // 3秒后清除状态文本
            clearStatusTimer.start();
        }
    }

    Timer {
        id: clearStatusTimer
        interval: 3000
        onTriggered: {
            cacheStatusText.text = "";
        }
    }

    // 内置 API 设置
    StyledRect {
        width: parent.width
        height: builtinColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: builtinColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: I18n.tr("内置歌词源")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "neteaseEnabled"
                label: I18n.tr("网易云音乐")
                description: I18n.tr("优先使用，对中文歌曲支持更好")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "lrclibEnabled"
                label: I18n.tr("lrclib.net")
                description: I18n.tr("开源歌词库，作为网易云的后备源")
                defaultValue: true
            }
        }
    }

    // 自定义 API 设置
    StyledRect {
        width: parent.width
        height: customApiColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: customApiColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: I18n.tr("自定义 API")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "customApiEnabled"
                label: "启用自定义 API"
                description: "使用自定义 API 获取歌词，失败时回退到启用的内置源"
                defaultValue: false
            }

            StringSetting {
                settingKey: "customApiUrl"
                label: "API 地址"
                description: "自定义歌词 API 的 URL。支持变量: {title}, {artist}, {album}"
                placeholder: "https://api.example.com/lyrics?title={title}&artist={artist}"
                defaultValue: ""
            }

            SelectionSetting {
                settingKey: "customApiMethod"
                label: "请求方式"
                description: "选择 API 请求方法"
                options: [
                    { label: "GET", value: "GET" },
                    { label: "POST", value: "POST" }
                ]
                defaultValue: "GET"
            }
        }
    }
}