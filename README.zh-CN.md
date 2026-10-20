# Pomolet · macOS 原生版

根据原始 HTML 原型重建的 SwiftUI / AppKit 应用，人物由 AVFoundation 播放，图表与水滴效果使用原生 Canvas。界面没有嵌入浏览器或 WebView，运行时无需启动 HTML 服务。

## 展示视频

[![Pomolet 展示：专注模式与原生转场](docs/media/pomolet-preview.gif)](https://github.com/Davied-H/Pomolet/blob/main/docs/media/pomolet-demo.mp4)

[观看完整 54 秒展示视频](https://github.com/Davied-H/Pomolet/blob/main/docs/media/pomolet-demo.mp4) · [下载 MP4](https://github.com/Davied-H/Pomolet/releases/download/v1.0.1/pomolet-demo.mp4)

原生 macOS 应用实录，60fps，展示专注、休息、数据统计、设置菜单和黑白主题。统计使用独立样例数据，不影响正式记录。

## 运行

双击 `dist/Pomolet.app`。支持 macOS 14 或更新版本，包含 Apple Silicon 和 Intel 两种架构。

界面实际尺寸为 390 × 420pt；窗口额外保留四周 28pt 透明空间，用于人物溢出和阴影。拖动背景可移动窗口。关闭窗口后计时继续，点击 Dock 图标可重新显示；完全退出使用 ⌘Q。

## 已移植的交互

- 模式背景滑块、模式键盘导航、开始 / 暂停 / 重置及任务输入。
- 开始后顶栏、提示、任务输入和底栏错落退场，人物放大 20%，人物与数字转为上下居中；暂停反向恢复。
- 重置按钮仅在开始后显示，使用原生 Canvas 的高斯模糊 / Alpha 矩阵 / 原图 atop 合成与临界阻尼弹簧，实现水滴连接和分离。
- 设置页从齿轮位置圆形展开，完整覆盖窗口；最多五个模式，单行编辑、灰底聚焦反馈、图标入口和紧凑三项菜单。
- 自定义菜单保持选中勾、上下定位、展开收起、滚动 / 点击外部关闭及键盘选择。
- 名称、分钟、动画类型、增删模式及提示音编辑即保存；无效输入保留上次有效设置。修改名称或提示音不重置计时。
- 四张数据卡片和一次性 Canvas 折线 / 柱形绘制；近七天与本周统计，真实专注记录及空状态。
- 顶部滑入通知、纯黑白暗色主题、原版三音提示音。
- 六段透明 60fps 人物片段，原始比例与位置、按模式随机动作、可变呼吸间隔与休息动作避免连续重复。
- 后台与遮挡时停止人物播放；倒计时按真实截止时间校准，支持休眠唤醒、退出后恢复。尊重系统“减少动态效果”。

## 快捷键

- 空格：主界面开始 / 暂停；编辑文字时正常输入空格。
- ⌘Return：开始 / 暂停；⌘R：重置。
- ⌘1：番茄钟；⌘2：数据统计；⌘,：设置；⌘D：切换深浅色。
- 方向键 / Home / End：模式按钮获得焦点时切换模式。
- Escape：先收起菜单，再返回主界面。菜单支持上下、Home、End、Return、空格及 Tab。
- ⌘M：最小化；⌘0：显示主窗口；⌘W：关闭窗口；⌘Q：退出。

## 源码与构建

原生源码位于 `Sources/`：

- `Core.swift`：计时、模式、自动保存、历史记录和统计。
- `RootView.swift`：主界面、沉浸转场、页面转场和顶部通知。
- `SettingsView.swift`：单行模式编辑、即时保存和自定义菜单。
- `StatisticsView.swift`：四卡片、原生 Canvas 图表及历史记录。
- `Components.swift`：矢量图标、原生文字输入、水滴按钮和遮罩。
- `Motion.swift`：CSS 曲线采样、页面分组时序、可中断转场和 JS 同构弹簧。
- `LiquidRenderer.swift` / `ParityVisuals.swift`：完整液体滤镜、盒模型、字体和通知。
- `Media.swift`：透明播放器、随机动作调度、深色视频合成和提示音。
- `App.swift`：窗口、应用菜单、快捷键及生命周期。

只需 Command Line Tools 即可构建完整应用，无外部 Swift 依赖：

```sh
./build.sh
./test.sh
```

也可在 Xcode 中打开 `Package.swift` 编辑和调试；正式 `.app` 通过 `build.sh` 打包。构建脚本生成双架构可执行文件并进行本地 ad-hoc 签名。

当前构建未使用 Developer ID 签名或公证。本机可直接运行；正式对外分发需另行使用开发者证书和公证流程。

## 资源

`Resources/Videos/` 包含由现有 VP9 Alpha 视频转换的 HEVC-with-Alpha MOV，均为 540 × 720、60fps，慢动作已烘焙，原生以 1 倍速播放。未重新生成收费视频。`Icons/` 中的 PDF 来自当前 demo 的 SVG 路径，保留矢量轮廓。

重新转换资源时，先编译 `Tools/EncodeAlpha.swift` 为 `.build/native/encode-alpha`，再以安装有 reportlab、Pillow、numpy 的 Python 运行 `Tools/prepare-assets.py`。需要 FFmpeg 及 HTML demo 的原素材。

## 本地数据

应用状态位于 `~/Library/Application Support/FocusNative/state.json`，使用原子写入。包含模式、主题、声音、任务、记录及截止时间；不连接网络。原生版与 HTML demo 的浏览器 localStorage 独立，现有网页记录不会自动迁移。

## 验证

`test.sh` 覆盖 45 个原生功能断言，包括计时、暂停 / 重置、自动保存、五模式上限、四轮长休息、历史、退出恢复、统计和损坏数据。另有50项保真检查覆盖 CSS 时序、分组进退场、快速反向、弹簧积分、SVG 滤镜、图表曲线和 sRGB/Alpha 的保真断言，结果位于 `docs/parity-validation.json`。AVFoundation 解码验证覆盖六段视频的帧率、尺寸与透明通道，结果位于 `docs/media-validation.json`。

另有实际原生应用的主界面、沉浸状态、设置、菜单、统计和主题操作检查；检查记录位于 `docs/VALIDATION.md`。Intel 架构已编译，运行检查在本机 Apple Silicon 上完成。
