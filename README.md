# Lyrics Plugin for DankMaterialShell

![Version](https://img.shields.io/badge/version-1.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![DMS](https://img.shields.io/badge/DankMaterialShell-1.4+-purple)

一个还在开发中的的音乐歌词插件，为 [DankMaterialShell](https://danklinux.com/) 提供实时同步歌词显示。

## 功能特性

- 🎵 **多源歌词获取** - 支持从 lrclib.net、网易云音乐等多个来源获取歌词
- 🔄 **实时同步** - 根据 MPRIS 播放进度自动高亮当前歌词行
- 💾 **本地缓存** - 自动缓存下载的歌词，加快后续加载速度
- 🎨 **精美 UI** - macOS风格进度条，圆形专辑封面，现代化设计
- 🎛️ **播放控制** - 支持上一首/播放/暂停/下一首控制
- 📱 **双栏适配** - 完美适配横向和纵向 DankBar
- 🔍 **智能匹配** - 自动匹配歌曲信息，支持模糊搜索

## 截图

![Plugin Screenshot](./screenshots.png)

## 安装

### 手动安装

1. 克隆仓库到 DMS 插件目录：

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/xubuyuan18/dms-plugin-Lyrics.git musicLyrics
```

2. 重启 DankMaterialShell 或热重载插件后将组件添加到bar上：
```bash
dms ipc call plugins reload musicLyrics
```

## 配置

在 DMS 设置中，你可以配置：

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| 本地缓存 | 将下载的歌词保存在本地 | 开启 |

缓存位置：`~/.cache/musicLyrics/`

## 使用

### Bar 显示

- **横向 Bar**：显示当前播放歌曲的圆形专辑封面（36px）和歌词/歌曲名
- **纵向 Bar**：显示歌词图标和音符指示器

### 弹出面板

点击 Bar 上的插件图标打开弹出面板，包含：

- 🎵 **当前播放** - 歌曲名、艺术家、专辑信息
- 🖼️ **专辑封面** - 大尺寸圆形封面
- 🎮 **播放控制** - 上一首/播放/暂停/下一首按钮

### 歌词同步

- 自动根据 MPRIS 播放进度同步歌词
- 每 200ms 更新一次当前歌词行
- 支持 LRC 格式时间标签解析

## 歌词获取流程

插件按以下优先级获取歌词：

1. **自定义 API**（如果启用）- 优先使用用户配置的自定义 API
2. **本地缓存** - 如果已缓存直接加载（缓存命中）
3. **lrclib.net** - 开源歌词库，支持同步歌词
4. **网易云音乐** - 通过搜索 API + paugram API 获取歌词

### 自定义 API

你可以在设置中启用自定义歌词 API。当启用后，插件会优先尝试从自定义 API 获取歌词，失败时自动回退到内置源。

**配置项：**
- **启用自定义 API** - 开关自定义 API 功能
- **API 地址** - 自定义 API 的 URL，支持以下变量：
  - `{title}` - 歌曲标题
  - `{artist}` - 艺术家
  - `{album}` - 专辑名

**示例 API 地址：**
```
https://api.example.com/lyrics?title={title}&artist={artist}
https://lyrics.example.com/search?q={title}+{artist}
```

**API 响应格式：**
自定义 API 应返回 JSON 格式，支持以下字段（按优先级）：
- `lyrics` - LRC 格式歌词
- `lyric` - LRC 格式歌词
- `lrc` - LRC 格式歌词
- `content` - LRC 格式歌词
- `data` - LRC 格式歌词

如果返回的歌词不是 LRC 格式，插件会将其作为纯文本处理（所有行时间设为 0）。

## 技术细节

### 依赖

- DankMaterialShell >= 1.4.0
- QtQuick
- Quickshell.Services.Mpris

### 文件结构

```
musicLyrics/
├── Lyrics.qml               # 主组件（歌词获取、解析、UI 渲染）
├── LyricsSettings.qml       # 设置界面
├── plugin.json              # 插件配置（id, name, version, permissions 等）
├── README.md                # 本文件
└── LICENSE                  # MIT 许可证
```

### 核心功能模块

| 模块 | 功能 | 关键函数/组件 |
|------|------|---------------|
| **歌词获取** | 从多个源获取歌词 | `_fetchFromLrclib()`, `_fetchFromNetease()` |
| **LRC 解析** | 解析 LRC 格式歌词 | `parseLrc()` |
| **缓存管理** | 读写本地缓存 | `readFromCache()`, `writeToCache()`, `_cacheKey()` |
| **进度同步** | 同步歌词高亮 | `positionTimer` |
| **UI 渲染** | Bar 和弹出面板 | `horizontalBarPill`, `verticalBarPill`, `popoutContent` |
| **状态管理** | 歌词源状态显示 | `lrclibStatus`, `neteaseStatus`, `cacheStatus`, `_chipMeta` |

### 状态枚举

- `lyricState`: idle(0), loading(1), synced(2), notFound(3)
- `lyricSrc`: none(0), lrclib(1), cache(2), netease(3)
- `status`: none(0), searching(1), found(2), notFound(3), error(4), skippedConfig(5), skippedFound(6), skippedPlain(7), cacheHit(8), cacheMiss(9), cacheDisabled(10)
## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[MIT](./LICENSE)

## 致谢

- [DankMaterialShell](https://danklinux.com/) - 优秀的 Wayland 桌面 Shell
- [lrclib.net](https://lrclib.net/) - 开源歌词库
- [网易云音乐](https://music.163.com/) - 歌词数据源
- [paugram API](https://api.paugram.com/) - 网易云歌词 API

---

**作者：** xubuyuan18  
**项目地址：** https://github.com/xubuyuan18/dms-plugin-Lyrics