# 更新与发布

从 v1.4.0 起使用 Sparkle 2.10.0。默认每天检查更新，自动下载并在退出时安装；Pomolet 菜单提供手动检查、自动检查与自动下载安装开关。旧版没有更新器，需要手动安装一次 v1.4.0 或更高版本。Sparkle 对话框使用系统语言；Pomolet 菜单遵循应用语言设置。

## 构建与发布

1. 更新 Info.plist 的短版本与递增 build 号。
2. 运行 `./test.sh`、`./build.sh`。构建脚本下载固定版本 Sparkle 并核对 SHA-256，嵌入其框架与许可证。
3. 运行 `python3 Tools/package-release.py`，导出 `dist/Pomolet-macOS.zip` 和 `dist/appcast.xml`，并验证二者的 EdDSA 签名。
4. 将两个文件一起上传到对应 GitHub Release，并将 Release 设为 Latest。应用固定读取 `https://github.com/Davied-H/Pomolet/releases/latest/download/appcast.xml`。
5. 下载线上文件核对、验证签名并检查手动更新对话框。

私钥保存在本机 macOS 登录钥匙串的 Sparkle `Pomolet` account 中，不进入仓库。后续发布需使用同一密钥；在另一台机器发布前，应通过 Sparkle 官方密钥导出/导入工具安全迁移密钥。公钥位于 Info.plist。更新包在解压前验证签名，更新源也必须签名。

应用当前仍为 ad-hoc 签名，未做 Developer ID 公证。自动更新使用独立的 EdDSA 签名验证来源，不等同于 Apple 公证。
