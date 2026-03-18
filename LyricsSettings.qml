import Quickshell
import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lyrics"

    StyledText {
        width: parent.width
        text: "Lyrics 设置"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "配置歌词行为和歌词源"
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
                text: "缓存"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "cachingEnabled"
                label: "本地缓存"
                description: "将下载的歌词保存在本地，加快加载速度并减少网络请求。歌词文件将存储在 ~/.cache/Lyrics 目录下。"
                defaultValue: true
            }
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
                text: "内置歌词源"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "neteaseEnabled"
                label: "网易云音乐"
                description: "优先使用，对中文歌曲支持更好"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "lrclibEnabled"
                label: "lrclib.net"
                description: "开源歌词库，作为网易云的后备源"
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
                text: "自定义 API"
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