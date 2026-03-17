# Lyrics Plugin for DankMaterialShell

![Version](https://img.shields.io/badge/version-1.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![DMS](https://img.shields.io/badge/DankMaterialShell-1.4+-purple)

一个还在开发中的的音乐歌词插件，为 [DankMaterialShell](https://danklinux.com/) 提供实时同步歌词显示。

## 功能特性

- 🎵 **多源歌词** - 自定义 API、本地缓存、lrclib.net、网易云音乐
- 🔄 **实时同步** - 根据 MPRIS 播放进度自动高亮歌词
- 💾 **本地缓存** - 自动缓存歌词到 `~/.cache/Lyrics/`
- 🎨 **现代 UI** - 圆形专辑封面，支持横向/纵向 Bar
- 🎛️ **播放控制** - 上一首/播放/暂停/下一首

## 截图
<img width="656" height="498" alt="Screenshot from 2026-03-18 00-06-22" src="https://github.com/user-attachments/assets/327ea1a2-5aab-469a-983f-b59f4f13118e" />




## 安装

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/xubuyuan18/dms-plugin-Lyrics.git Lyrics
dms ipc call plugins reload Lyrics
```

## 设置

| 类别 | 选项 | 说明 |
|------|------|------|
| 缓存 | 本地缓存 | 加速加载，减少网络请求 |
| 内置源 | 网易云音乐 | 中文歌曲优先 |
| 内置源 | lrclib.net | 开源歌词库，后备源 |
| 自定义 API | 启用/地址/请求方式 | 支持变量: `{title}`, `{artist}`, `{album}` |

**歌词获取优先级**: 自定义 API → 本地缓存 → 网易云音乐 → lrclib.net

**自定义 API 响应格式**:
```json
{
  "lyrics": "[00:00.00]歌词内容...",
  "lyric": "...",
  "lrc": "...",
  "content": "...",
  "data": "..."
}
```

## 使用

- **横向 Bar**: 显示圆形专辑封面 + 当前歌词/歌曲名
- **纵向 Bar**: 显示歌词图标
- **弹出面板**: 专辑封面、歌曲信息、播放控制、歌词源状态

## 文件结构

```
musicLyrics/
├── Lyrics.qml          # 主组件
├── LyricsSettings.qml  # 设置界面
├── plugin.json         # 插件配置
├── README.md
└── LICENSE
```

## 许可证

[MIT](./LICENSE)

---

**作者:** xubuyuan18  
**项目地址:** https://github.com/xubuyuan18/dms-plugin-Lyrics
