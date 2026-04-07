# CodeSwitch

<p align="center">
  <img src="./Copool.png" alt="CodeSwitch Icon" width="160" />
</p>

CodeSwitch is a macOS SwiftUI menu-bar app for managing and switching between multiple AI coding assistant configurations — **Codex** (ChatGPT accounts + API Key profiles) and **Claude Code** (API Key profiles).

CodeSwitch 是一个 macOS SwiftUI 菜单栏应用，用于管理和切换多个 AI 编程助手的配置——**Codex**（ChatGPT 账号 + API Key 配置）和 **Claude Code**（API Key 配置）。

## Features / 功能

### Product Tabs / 产品标签

- **Codex tab**: Manage ChatGPT login accounts and API Key profiles for OpenAI Codex
- **Codex 标签**: 管理 OpenAI Codex 的 ChatGPT 登录账号和 API Key 配置
- **Claude tab**: Manage API Key profiles for Anthropic Claude Code
- **Claude 标签**: 管理 Anthropic Claude Code 的 API Key 配置

### Codex — Auth Mode Switching / 认证模式切换

- Switch between ChatGPT login mode and API Key mode in a single click
- 一键切换 ChatGPT 登录模式与 API Key 模式
- Manage multiple API Key profiles with custom provider, base URL, model, wire API, and reasoning effort
- 管理多组 API Key 配置，支持自定义供应商、Base URL、模型、Wire API 和推理强度
- Thread visibility repair on every switch — all Codex conversations stay visible regardless of auth mode
- 每次切换时自动修复线程可见性——无论认证模式如何切换，所有 Codex 会话始终可见
- Automatic backup of `auth.json` and `config.toml` before each switch
- 每次切换前自动备份 `auth.json` 和 `config.toml`

### Claude Code — API Key Management / API Key 管理

- Manage multiple Anthropic API Key profiles with base URL configuration
- 管理多组 Anthropic API Key 配置，支持 Base URL 自定义
- One-click switching writes directly to `~/.claude/settings.json`
- 一键切换直接写入 `~/.claude/settings.json`
- Support for third-party API providers (relay services, custom endpoints)
- 支持第三方 API 供应商（中继服务、自定义端点）

### Account Management / 账号管理

- ChatGPT OAuth import with multi-account support
- ChatGPT OAuth 导入，支持多账号
- Smart switch based on remaining quota score
- 基于剩余额度评分的智能切换
- iCloud-backed account sync and current-selection sync
- 基于 iCloud 的账号同步与当前账号选择同步
- Editor restart / Codex launch integration on account switch
- 切换账号时的编辑器重启 / Codex 拉起集成

### Architecture / 架构

- Native SwiftUI with layered design (`App`, `Features`, `UI`, `Behavior`, `Infrastructure`, `Domain`, `Layout`)
- 纯 SwiftUI 分层架构
- Menu bar integration (MenuBarExtra)
- 菜单栏集成

## Requirements / 环境要求

- macOS 14+
- Xcode 17+
- Swift 6 toolchain

## Build & Run / 构建与运行

```bash
xcodebuild -project Copool.xcodeproj -scheme Copool -configuration Debug -destination 'platform=macOS' build
```

Open `Copool.xcodeproj` in Xcode and run the `Copool` scheme.

使用 Xcode 打开 `Copool.xcodeproj`，运行 `Copool` scheme 即可。

## How It Works / 工作原理

### Codex Config Files / Codex 配置文件

- `~/.codex/config.toml` — model provider, API endpoint, wire API settings
- `~/.codex/auth.json` — authentication credentials
- `~/.codex/state_5.sqlite` — thread visibility normalization on switch

### Claude Code Config Files / Claude Code 配置文件

- `~/.claude/settings.json` — `env.ANTHROPIC_AUTH_TOKEN` and `env.ANTHROPIC_BASE_URL`

### Thread Visibility / 线程可见性

Codex desktop only shows threads whose `model_provider` matches the current active provider. CodeSwitch automatically normalizes all unarchived threads to the target provider/model pair on every switch, keeping all conversations visible.

Codex 桌面端仅显示 `model_provider` 与当前活跃供应商匹配的线程。CodeSwitch 在每次切换时自动将所有未归档线程的 provider/model 统一到目标值，确保所有会话始终可见。

## Reference Projects / 参考项目

- [AlickH/Copool](https://github.com/AlickH/Copool) — original Copool project
- [170-carry/codex-tools](https://github.com/170-carry/codex-tools) — original Tauri-based implementation
- [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) — Windows auth switching reference
- [farion1231/cc-switch](https://github.com/farion1231/cc-switch) — cross-platform AI CLI tool manager (design reference)

## Acknowledgements / 致谢

- Thanks to [AlickH/Copool](https://github.com/AlickH/Copool) for the original project and SwiftUI architecture.
- 感谢 [AlickH/Copool](https://github.com/AlickH/Copool) 提供的原始项目和 SwiftUI 架构设计。
- Thanks to the original authors and contributors of [170-carry/codex-tools](https://github.com/170-carry/codex-tools).
- 感谢 [170-carry/codex-tools](https://github.com/170-carry/codex-tools) 的原作者与贡献者。
- Thanks to [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) for the auth switching design reference.
- 感谢 [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) 提供的认证切换设计参考。
- Thanks to [farion1231/cc-switch](https://github.com/farion1231/cc-switch) for the multi-tool management design inspiration.
- 感谢 [farion1231/cc-switch](https://github.com/farion1231/cc-switch) 提供的多工具管理设计灵感。

## License / 许可证

Please follow the upstream license and your organization's compliance requirements when reusing code from referenced projects.

复用参考项目代码时，请遵循上游许可证与所在组织的合规要求。
