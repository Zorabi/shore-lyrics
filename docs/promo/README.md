# 宣传素材

| 文件 | 尺寸 | 用途 |
| --- | --- | --- |
| `shore-lyrics-hero.png` | 2400 × 1600 | README 主视觉，包含设置窗口和 Dock 融合对比 |
| `shore-lyrics-square.png` | 1600 × 1600 | 方形分享图，展示 Dock 的两种状态 |
| `shore-lyrics-features.png` | 2400 × 2400 | 四个设置页面的功能总览 |

素材使用实际应用窗口和 Dock 截图，未包含鼠标定位标记。Dock 的歌词文字来自应用内置预览；原始 Dock 单独拍摄。普通状态用于说明歌词让位后可访问的图标区域，不是对鼠标悬停过程的连续录屏。

窗口截图裁去了系统录制栏，本地目录及文件路径已遮盖。截图中的播放器名称和在线开关反映当时的运行状态，不代表专用适配或默认设置。

## 横版主视觉

用于项目首页，展示产品定位、设置窗口与 Dock 实机对比。

![岸词横版主视觉](shore-lyrics-hero.png)

## Dock 体验

方形版展示歌词融合与图标显示两种状态。

![岸词 Dock 体验](shore-lyrics-square.png)

## 功能总览

四个设置页面的整体布局，完整截图可在[界面截图](../screenshots/README.md)中查看。

![岸词四个设置页面](shore-lyrics-features.png)

## 重新生成

在项目根目录运行：

```sh
swift Tools/Promo.swift "$PWD"
```

脚本优先使用本机 `build/captures/*-native.png` 原始截图；源码副本没有原始截图时复用已处理的公开截图。原始截图和本地签名材料不应发布。

项目自有设计随项目采用 AGPL-3.0-only；第三方商标、歌曲和歌词不包含在此授权中。
