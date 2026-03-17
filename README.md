# Music Lyrics Plugin for DankMaterialShell

![Version](https://img.shields.io/badge/version-1.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![DMS](https://img.shields.io/badge/DankMaterialShell-1.4+-purple)

一个功能强大的音乐歌词插件，为 [DankMaterialShell](https://danklinux.com/) 提供实时同步歌词显示。

## 功能特性

- 🎵 **多源歌词获取** - 支持从 lrclib.net、网易云音乐等多个来源获取歌词
- 🔄 **实时同步** - 根据播放进度自动高亮当前歌词行
- 💾 **本地缓存** - 自动缓存下载的歌词，加快加载速度
- 🎨 **精美 UI** - macOS 风格进度条，圆形专辑封面，现代化设计
- 🎛️ **播放控制** - 支持上一首/播放/暂停/下一首控制
- 📱 **双栏支持** - 完美适配横向和纵向 DankBar
- 🔍 **智能匹配** - 自动匹配歌曲信息，支持模糊搜索

## 截图

![Plugin Screenshot](./screenshots.png)

## 安装

### 方法 1：手动安装

1. 克隆仓库到 DMS 插件目录：

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/xubuyuan18/dms-plugin-Lyrics.git musicLyrics
```

2. 重启 DankMaterialShell 或热重载插件：

```bash
dms ipc call plugins reload musicLyrics
```

### 方法 2：通过 DMS 设置

1. 打开 DankMaterialShell 设置
2. 进入 Plugins → Scan for Plugins
3. 找到 "Music Lyrics" 并启用
4. 将插件添加到 DankBar

## 配置

在 DMS 设置中，你可以配置：

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| 本地缓存 | 将下载的歌词保存在本地 | 开启 |

缓存位置：`~/.cache/musicLyrics/`

## 使用

### Bar 显示

- **横向 Bar**：显示当前播放歌曲的圆形专辑封面和歌词/歌曲名
- **纵向 Bar**：显示歌词图标和音符指示器

### 弹出面板

点击 Bar 上的插件图标打开弹出面板，包含：

- 🎵 **当前播放** - 歌曲名、艺术家、专辑信息
- 🖼️ **专辑封面** - 大尺寸圆形封面（200x200px）
- 📊 **进度条** - macOS 风格进度条，带当前时间显示
- 🎮 **播放控制** - 上一首/播放/暂停/下一首按钮

### 歌词同步

- 自动根据 MPRIS 播放进度同步歌词
- 每 200ms 更新一次当前歌词行
- 支持 LRC 格式时间标签

## 歌词来源

插件按以下优先级获取歌词：

1. **本地缓存** - 如果已缓存直接加载
2. **lrclib.net** - 开源歌词库，支持同步歌词
3. **网易云音乐** - 通过 API 搜索和获取歌词

## 技术细节

### 依赖

- DankMaterialShell >= 1.4.0
- QtQuick
- Quickshell.Services.Mpris

### 文件结构

```
musicLyrics/
├── MusicLyrics.qml          # 主组件
├── MusicLyricsSettings.qml  # 设置界面
├── plugin.json              # 插件配置
└── README.md                # 本文件
```

### 主要功能模块

- **歌词获取** (`_fetchFromLrclib`, `_fetchFromNetease`)
- **LRC 解析** (`parseLrc`)
- **缓存管理** (`readFromCache`, `writeToCache`)
- **进度同步** (`positionTimer`)
- **UI 组件** (`horizontalBarPill`, `verticalBarPill`, `popoutContent`)

## 更新日志

### v1.5.0
- ✨ 新增 macOS 风格进度条
- ✨ 增大专辑封面尺寸（Bar 36px，弹出面板 200px）
- ✨ 优化中文字体显示
- ✨ 添加播放控制按钮
- 🐛 修复歌词同步精度问题

### v1.4.0
- ✨ 添加网易云音乐歌词源
- ✨ 实现本地缓存功能
- ✨ 添加歌词来源状态显示

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[MIT](./LICENSE)

## 致谢

- [DankMaterialShell](https://danklinux.com/) - 优秀的 Wayland 桌面 Shell
- [lrclib.net](https://lrclib.net/) - 开源歌词库
- [网易云音乐](https://music.163.com/) - 歌词数据源

---

**作者：** gasiyu  
**项目地址：** https://github.com/xubuyuan18/dms-plugin-Lyrics