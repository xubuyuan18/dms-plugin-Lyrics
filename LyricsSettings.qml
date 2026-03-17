import Quickshell
import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "musicLyrics"

    StyledText {
        width: parent.width
        text: "Lyrics 设置"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "配置歌词行为和缓存"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: durationsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: durationsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "缓存"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "cachingEnabled"
                label: "本地缓存"
                description: "将下载的歌词保存在本地，加快加载速度并减少网络请求。歌词文件将存储在 ~/.cache/musicLyrics 目录下。"
                defaultValue: true
            }
        }
    }

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
                text: "自定义 API"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "customApiEnabled"
                label: "启用自定义 API"
                description: "优先使用自定义 API 获取歌词，失败时回退到内置源。"
                defaultValue: false
            }

            TextSetting {
                settingKey: "customApiUrl"
                label: "API 地址"
                description: "自定义歌词 API 的 URL。支持变量: {title}, {artist}, {album}。例如: https://api.example.com/lyrics?title={title}&artist={artist}"
                defaultValue: ""
                placeholderText: "https://api.example.com/lyrics?title={title}&artist={artist}"
                enabled: pluginData.customApiEnabled ?? false
            }
        }
    }
}