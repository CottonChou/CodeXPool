# CodeXPool

<p align="center">
  <img src="./Copool.png" alt="CodeXPool 图标" width="160" />
</p>

<p align="center">
  <a href="./README.md">English</a> | <strong>中文</strong>
</p>

**多个 AI 编程助手账号，一池统管，一键切换。**

CodeXPool 是一个 macOS 菜单栏工具，让你在 **Codex** 和 **Claude Code** 的多个账号与 API Key 配置之间一键切换——无需手动编辑文件，无需在终端来回操作。

---

## 为什么需要 CodeXPool？

Codex、Claude Code 这类 AI 编程助手非常强大，但多账号管理却很痛苦：

- **Codex** 将凭证存储在 `auth.json` / `config.toml` 中——要在 ChatGPT 登录账号与 API Key 供应商之间切换，意味着每次都要覆盖文件。
- **Claude Code** 从 `~/.claude/settings.json` 读取 API Key——没有内置的多配置管理机制。
- 在 Codex 中切换认证模式可能会因为 `model_provider` 不匹配而**导致所有对话记录消失**。

CodeXPool 通过原生 SwiftUI 界面一站式解决以上所有问题。

---

## 功能特性

### Codex — 账号与 API Key 切换

| 模式 | 功能说明 |
|------|----------|
| **ChatGPT 账号** | 导入多个 ChatGPT OAuth 登录，查看 5 小时 / 每周用量，一键切换 |
| **API Key 配置** | 为每个配置单独设置供应商、Base URL、模型、Wire API、推理强度 |
| **智能切换** | 自动选择剩余额度最多的账号 |
| **对话修复** | 无论当前使用哪种认证模式，所有 Codex 对话始终可见 |

### Claude Code — API Key 切换

| 功能 | 说明 |
|------|------|
| **多配置管理** | 维护多个 Anthropic API Key，支持不同的 Base URL |
| **一键切换** | 即时写入 `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_BASE_URL` 到 `~/.claude/settings.json` |
| **第三方支持** | 兼容中转服务和自定义 API 端点 |

### 通用功能

- 原生 macOS 14+ 菜单栏应用——无 Dock 图标，极低资源占用
- 双标签页导航：**Codex**（终端图标）和 **Claude**（星光图标），外加**设置**
- iCloud 账号跨设备同步
- 每次切换前自动备份 `auth.json` 和 `config.toml`
- 账号切换时集成编辑器重启（Cursor、VS Code 等）
- 支持 11 种语言本地化（英、简中、繁中、日、韩、法、德、意、西、俄、荷）

---

## 安装

### 系统要求

- macOS 14+（Sonoma）
- Xcode 17+ / Swift 6（从源码构建时需要）

### 下载

从 [GitHub Releases](https://github.com/CottonChou/CodeXPool/releases) 获取最新 `.dmg` 安装包。

### 从源码构建

```bash
git clone https://github.com/CottonChou/CodeXPool.git
cd CodeXPool
xcodebuild -project CodeXPool.xcodeproj -scheme CodeXPool -configuration Release -destination 'platform=macOS' build
```

---

## 工作原理

```
┌─────────────────────────────────────────────────┐
│                  CodeXPool                      │
│  ┌───────────┐  ┌───────────┐  ┌────────────┐  │
│  │  Codex    │  │  Claude   │  │   设置      │  │
│  │ (终端)    │  │ (星光)    │  │  (齿轮)     │  │
│  └─────┬─────┘  └─────┬─────┘  └────────────┘  │
│        │              │                         │
│  ┌─────┴──────┐  ┌────┴──────┐                  │
│  │ ChatGPT    │  │ API Key   │                  │
│  │ 账号管理   │  │ 配置管理  │                  │
│  ├────────────┤  └───────────┘                  │
│  │ API Key    │                                 │
│  │ 配置管理   │        写入                     │
│  └────────────┘   ~/.claude/settings.json       │
│        │                                        │
│      写入                                       │
│   ~/.codex/auth.json                            │
│   ~/.codex/config.toml                          │
│   ~/.codex/state_5.sqlite                       │
└─────────────────────────────────────────────────┘
```

### 管理的配置文件

| 工具 | 文件 | CodeXPool 写入内容 |
|------|------|--------------------|
| Codex | `~/.codex/auth.json` | OAuth 凭证（ChatGPT 模式） |
| Codex | `~/.codex/config.toml` | 模型、供应商、Base URL、Wire API（API Key 模式） |
| Codex | `~/.codex/state_5.sqlite` | 对话记录 `model_provider` 标准化 |
| Claude | `~/.claude/settings.json` | `env.ANTHROPIC_AUTH_TOKEN`、`env.ANTHROPIC_BASE_URL` |

### 对话可见性修复

Codex 桌面端只显示 `model_provider` 与当前活跃供应商匹配的对话。当你在 ChatGPT 登录模式和 API Key 模式之间切换时，另一种模式下创建的对话会变得不可见。CodeXPool 在每次切换时自动将所有未归档对话的 provider 标准化为目标供应商，**确保对话不会消失**。

---

## 项目架构

```
Sources/CodeXPool/
├── App/              # AppContainer、RootScene、入口点
├── Domain/           # 模型、协议、业务规则
├── Behavior/         # AccountsCoordinator（中心状态机）
├── Features/
│   ├── Accounts/     # ChatGPT 账号视图 + API Key 配置视图
│   ├── Claude/       # Claude API Key 配置视图
│   └── Settings/     # 偏好设置 UI
├── Infrastructure/   # 文件 I/O、配置服务、iCloud 同步
├── UI/               # 共享组件、布局规则
└── Resources/        # 本地化字符串（11 种语言）
```

---

## 参考项目

- [AlickH/Copool](https://github.com/AlickH/Copool) — 原始 CodeXPool 项目及 SwiftUI 架构
- [steipete/CodexBar](https://github.com/steipete/CodexBar) — Codex、Claude 等的 macOS 菜单栏用量追踪器（UI/图标灵感来源）
- [170-carry/codex-tools](https://github.com/170-carry/codex-tools) — 基于 Tauri 的 Codex 工具（原始版本）
- [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) — Windows 端认证切换参考
- [farion1231/cc-switch](https://github.com/farion1231/cc-switch) — 跨平台 AI CLI 工具管理器（多工具设计灵感）

## 许可证

复用参考项目代码时，请遵循上游许可证与所在组织的合规要求。
