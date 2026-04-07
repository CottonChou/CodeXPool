# Copool

<p align="center">
  <img src="./Copool.png" alt="Copool Icon" width="160" />
</p>

Copool is a macOS SwiftUI app that manages Codex/ChatGPT auth accounts, API Key profiles, usage-based smart switching, and seamless auth mode switching between ChatGPT login and API Key workflows.

Copool 是一个 macOS SwiftUI 应用，用于管理 Codex/ChatGPT 授权账号与 API Key 配置、按用量智能切换，以及 ChatGPT 登录与 API Key 两种认证模式的无缝切换。

## Features / 功能

### Auth Mode Switching / 认证模式切换

- Switch between ChatGPT login mode and API Key mode in a single click
- 一键切换 ChatGPT 登录模式与 API Key 模式
- Manage multiple API Key profiles with custom provider, base URL, model, wire API, and reasoning effort
- 管理多组 API Key 配置，支持自定义供应商、Base URL、模型、Wire API 和推理强度
- Thread visibility repair on every switch — all Codex conversations stay visible regardless of auth mode
- 每次切换时自动修复线程可见性——无论认证模式如何切换，所有 Codex 会话始终可见
- Automatic backup of `auth.json` and `config.toml` before each switch
- 每次切换前自动备份 `auth.json` 和 `config.toml`
- Generates correct Codex `config.toml` with `[model_providers.*]` sections and top-level keys
- 生成符合 Codex 规范的 `config.toml`，包含 `[model_providers.*]` 段落和顶层配置键

### Account Management / 账号管理

- ChatGPT OAuth import with multi-account support
- ChatGPT OAuth 导入，支持多账号
- Account switch/delete and usage refresh (5h / 1week)
- 账号切换/删除与用量刷新（5h / 1week）
- Smart switch based on remaining quota score
- 基于剩余额度评分的智能切换
- iCloud-backed account sync and current-selection sync
- 基于 iCloud 的账号同步与当前账号选择同步
- Editor restart / Codex launch integration on account switch
- 切换账号时的编辑器重启 / Codex 拉起集成

### Architecture / 架构

- Native SwiftUI with layered design (`App`, `Features`, `UI`, `Behavior`, `Infrastructure`, `Domain`, `Layout`)
- 纯 SwiftUI 分层架构（`App`、`Features`、`UI`、`Behavior`、`Infrastructure`、`Domain`、`Layout`）
- Menu bar integration (MenuBarExtra)
- 菜单栏集成（MenuBarExtra）

## Requirements / 环境要求

- macOS 14+
- Xcode 17+
- Swift 6 toolchain

## Build & Run / 构建与运行

```bash
cd Copool
xcodebuild test -project Copool.xcodeproj -scheme Copool -destination 'platform=macOS'
xcodebuild -project Copool.xcodeproj -scheme Copool -configuration Debug -destination 'platform=macOS' build
```

Open `Copool.xcodeproj` in Xcode and run the `Copool` scheme.

使用 Xcode 打开 `Copool.xcodeproj`，运行 `Copool` scheme 即可。

## Release Channels / 发布渠道

- macOS release artifacts are published through GitHub Releases.
- macOS 发布产物通过 GitHub Releases 分发。
- See [`docs/release-macos.md`](docs/release-macos.md) for the Developer ID signing and notarization flow.
- macOS 的 Developer ID 签名与公证流程见 `docs/release-macos.md`。

## Project Structure / 项目结构

- `Sources/Copool/App`: scene composition and app bootstrap
- `Sources/Copool/Features`: page-level composition and bindings
- `Sources/Copool/UI`: reusable visual primitives
- `Sources/Copool/Behavior`: coordinators and behavior modules
- `Sources/Copool/Infrastructure`: IO/network/process integrations
- `Sources/Copool/Domain`: models and protocols (single source of truth)
- `Sources/Copool/Layout`: centralized layout rules

## How Auth Switching Works / 认证切换原理

### What it changes / 会修改的内容

- `~/.codex/config.toml`
- `~/.codex/auth.json`
- `~/.codex/state_5.sqlite` (thread `model_provider`/`model` normalization)
- `~/Library/Application Support/Codex/backups/current/thread_state.json`
- Session JSONL metadata (`session_meta`, `turn_context`)

### What it does not touch / 不会修改的内容

- `~/.codex/sessions/` (session content files are preserved)
- `~/.codex/archived_sessions/`

### Thread visibility / 线程可见性

Codex desktop only shows threads whose `model_provider` matches the current active provider. When switching between ChatGPT (`openai`) and API Key (custom provider), threads from the previous mode would become invisible. Copool automatically normalizes all unarchived threads to the target provider/model pair on every switch, keeping all conversations visible. A timestamped backup is created before each repair.

Codex 桌面端仅显示 `model_provider` 与当前活跃供应商匹配的线程。在 ChatGPT（`openai`）和 API Key（自定义供应商）之间切换时，上一模式的线程会变得不可见。Copool 在每次切换时自动将所有未归档线程的 provider/model 统一到目标值，确保所有会话始终可见。修复前会创建带时间戳的备份。

## Reference Projects / 参考项目

- [AlickH/Copool](https://github.com/AlickH/Copool) — original Copool project
- [170-carry/codex-tools](https://github.com/170-carry/codex-tools) — original Tauri-based implementation
- [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) — Windows auth switching reference

This project is forked from [AlickH/Copool](https://github.com/AlickH/Copool), with auth mode switching (ChatGPT login ↔ API Key) and thread visibility repair added on top. The auth switching design is referenced from Codex-Auth-Switcher.

本项目 fork 自 [AlickH/Copool](https://github.com/AlickH/Copool)，在此基础上新增了认证模式切换（ChatGPT 登录 ↔ API Key）和线程可见性修复功能。认证切换功能参考了 Codex-Auth-Switcher 的设计思路。

## Acknowledgements / 致谢

- Thanks to [AlickH/Copool](https://github.com/AlickH/Copool) for the original project and SwiftUI architecture.
- 感谢 [AlickH/Copool](https://github.com/AlickH/Copool) 提供的原始项目和 SwiftUI 架构设计。
- Thanks to the original authors and contributors of [170-carry/codex-tools](https://github.com/170-carry/codex-tools).
- 感谢 [170-carry/codex-tools](https://github.com/170-carry/codex-tools) 的原作者与贡献者。
- Thanks to [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) for the auth switching design reference.
- 感谢 [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) 提供的认证切换设计参考。
- Thanks to all users who provided migration feedback and UI/UX suggestions.
- 感谢所有提供迁移反馈与界面建议的用户。

## License / 许可证

Please follow the upstream license and your organization’s compliance requirements when reusing code from referenced projects.

复用参考项目代码时，请遵循上游许可证与所在组织的合规要求。
