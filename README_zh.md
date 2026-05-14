# copyWorld

[English](README.md)

macOS 菜单栏剪贴板历史管理工具。轻量、无 Dock 图标、常驻菜单栏，支持纯文本、富文本（RTF）和图片，中英文双语界面。

## 功能

- 菜单栏常驻，监听剪贴板变化（文本 / RTF / PNG/TIFF 图片）
- 本地保存最近 100 条记录（SwiftData 持久化），置顶项不受限制
- 搜索剪贴板历史（仅文本/RTF，图片不参与搜索）
- 一键复制回系统剪贴板，保留原始格式
- 类型感知预览：等宽文本、富文本渲染、棋盘格背景图片
- 中英文双语界面
- 开机自启
- 单条删除或清空全部历史

## 技术栈

- Swift 6 + SwiftUI + AppKit
- `@Observable`（macOS 14+）数据流
- SwiftData 持久化（`~/Library/Application Support/copyWorld/Clipboard.sqlite`）
- 隐私清单（`PrivacyInfo.xcprivacy`）
- Xcode macOS 应用目标（macOS 14.0+）

## 构建与运行

```bash
# 在 Xcode 中打开
open copyWorld.xcodeproj

# 命令行构建（Debug）
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" build

# 运行测试（70 个测试用例，含 18 个压力测试）
xcodebuild -project copyWorld.xcodeproj -scheme copyWorld -configuration Debug -destination "platform=macOS,arch=arm64" test

# 构建 Release .app → dist/
./scripts/build_app.sh

# 构建 DMG → dist/
./scripts/build_dmg.sh

# 运行打包后的应用
./scripts/run_app.sh

# 添加/移除文件后重新生成 Xcode 项目
ruby scripts/generate_xcodeproj.rb
```

## 备注

- 应用未签名 — 首次打开需右键 → 打开（或执行 `xattr -cr copyWorld.app`）
- 无沙盒、无公证、无 Sparkle 更新框架
- 需要辅助功能权限以访问剪贴板

## Roadmap

### 未完成

- [ ] **全局快捷键** — 添加类似 Windows Win+V 的快捷键（推荐 ⌃⌥V）呼出剪贴板历史面板，需实现全局热键监听并在 Settings 中提供配置入口
- [ ] **Pin 按钮位置优化** — 将 pin（置顶）功能从当前 UI 按钮移到右键上下文菜单中，减少 UI 空间占用
- [ ] **无障碍支持（Accessibility）** — ClipboardRow VoiceOver 标签、搜索框 accessibilityLabel、复制成功 VoiceOver 通知、状态栏图标 accessibilityDescription 改进
- [ ] **代码签名 & 公证** — 需要 Apple Developer 账号，启用 Hardened Runtime + Developer ID 签名 + Notarization
- [ ] **剪贴板内容加密** — 当前内容明文存储，需设计加密方案和密钥管理

### 已完成

- Swift 6 现代化 + 严格并发检查
- SwiftData 持久化替代文件系统存储
- 隐私清单（PrivacyInfo.xcprivacy）
- 从 UserDefaults / 文件系统的自动迁移
- 压力测试（大内容、高频操作、Codable 性能）
