# Lyrics Plugin for DankMaterialShell

![Version](https://img.shields.io/badge/version-1.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![DMS](https://img.shields.io/badge/DankMaterialShell-1.4+-purple)

# 一个正在开发中的二改dms　歌词插件

# 原作者的项目仓库　https://github.com/gasiyu/dms-plugin-musiclyrics



## 界面

- **状态栏** - 专辑封面 + 当前歌词
- **弹出面板** - 黑胶唱片封面、歌曲信息、播放控制、歌词源状态
- <img width="635" height="580" alt="Lyrics Plugin" src="https://github.com/user-attachments/assets/811cd9b1-0f10-4e56-8f76-28d63bbfc733" />


## 功能

- **多源歌词** - 自定义 API、本地缓存、lrclib.net、网易云音乐
- **专辑匹配** - 智能匹配歌曲版本，提升准确性
- **实时同步** - 基于 MPRIS 播放进度自动滚动
- **本地缓存** - 自动缓存至 `~/.cache/Lyrics/`
- **播放控制** - 集成上一首/播放/暂停/下一首

## 安装

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/xubuyuan18/dms-plugin-Lyrics.git Lyrics
dms ipc call plugins reload Lyrics
```

## 项目结构

```
Lyrics/
├── Lyrics.qml          # 主组件：歌词获取、UI、播放控制
├── LyricsSettings.qml  # 设置界面
├── plugin.json         # 插件配置
├── README.md
└── LICENSE
```

## 配置

| 类别 | 选项 | 说明 |
|------|------|------|
| 缓存 | 本地缓存 | 启用磁盘缓存，加速加载 |
| 内置源 | 网易云音乐 | 中文歌曲优先 |
| 内置源 | lrclib.net | 开源歌词库，后备源 |
| 自定义 API | 地址/方法 | 支持变量 `{title}`, `{artist}`, `{album}` |

**获取优先级**: 自定义 API → 本地缓存 → 网易云音乐 → lrclib.net

### 自定义 API 配置

**URL 格式**:
```
https://api.example.com/lyrics?title={title}&artist={artist}&album={album}
```

**请求方式**: GET 或 POST

**变量说明**:
- `{title}` - 歌曲名（自动 URL 编码）
- `{artist}` - 艺术家（自动 URL 编码）
- `{album}` - 专辑名（自动 URL 编码）

**响应格式**:
```json
{
  "lyrics": "[00:00.00]歌词内容...",
  "lyric": "...",
  "lrc": "...",
  "content": "...",
  "data": "..."
}
```

**示例**:
- URL: `https://lrclib.net/api/get?track_name={title}&artist_name={artist}`
- 方法: `GET`

## 功能实现

### 歌词获取流程
1. 检测歌曲切换（MPRIS 事件）
2. 优先级获取：自定义 API → 缓存 → 网易云 → lrclib
3. 解析 LRC 格式，建立时间索引
4. 定时轮询播放位置，匹配当前歌词行

### 专辑匹配算法
```
1. 歌曲名完全匹配 + 专辑匹配
2. 歌曲名完全匹配（忽略大小写/空格）
3. 歌曲名模糊匹配 + 专辑匹配
4. 歌曲名模糊匹配（包含关系）
5. 默认返回第一首
```

### 缓存机制
- 缓存路径: `~/.cache/Lyrics/`
- 文件名: `fnv1a32(title + "\0" + artist).json`
- 内容: `{lines, source, cachedAt}`

### 纯音乐检测
自动过滤包含以下标记的歌词行：
- 纯音乐，请欣赏
- Instrumental
- 无歌词 / 暂无歌词

## 许可证

[MIT](./LICENSE)
