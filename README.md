# CodeXPool

<p align="center">
  <img src="./Copool.png" alt="CodeXPool Icon" width="160" />
</p>

**Your AI coding assistants, one pool to switch them all.**

CodeXPool is a macOS menu bar utility that lets you manage and instantly switch between multiple accounts and API Key configurations for **Codex** and **Claude Code** — no manual file editing, no terminal juggling, just one click.

CodeXPool 是一个 macOS 菜单栏工具，让你在 **Codex** 和 **Claude Code** 的多个账号与 API Key 配置之间一键切换——无需手动编辑文件，无需在终端来回操作。

---

## Why CodeXPool?

AI coding assistants like Codex and Claude Code are incredibly powerful, but managing multiple identities is painful:

- **Codex** stores credentials in `auth.json` / `config.toml` — switching between ChatGPT login accounts and API Key providers means overwriting files every time.
- **Claude Code** reads its API key from `~/.claude/settings.json` — there's no built-in way to maintain multiple profiles.
- Switching auth modes in Codex can **hide all your conversation threads** due to `model_provider` mismatches.

CodeXPool solves all of this with a clean, native SwiftUI interface.

---

## Features

### Codex — Account & API Key Switching

| Mode | What you can do |
|------|----------------|
| **ChatGPT Accounts** | Import multiple ChatGPT OAuth logins, view 5h / weekly usage, one-click switch |
| **API Key Profiles** | Configure provider, base URL, model, wire API, reasoning effort per profile |
| **Smart Switch** | Auto-pick the account with the most remaining quota |
| **Thread Repair** | All Codex conversations stay visible regardless of which auth mode you're in |

### Claude Code — API Key Switching

| Feature | Detail |
|---------|--------|
| **Multi-profile** | Maintain multiple Anthropic API keys with different base URLs |
| **One-click switch** | Writes `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` to `~/.claude/settings.json` instantly |
| **Third-party support** | Works with relay services and custom API endpoints |

### General

- Native macOS 14+ menu bar app — no Dock icon, minimal footprint
- Two-tab navigation: **Codex** (terminal icon) and **Claude** (sparkles icon), plus **Settings**
- iCloud account sync across devices
- Auto-backup of `auth.json` and `config.toml` before every switch
- Editor restart integration (Cursor, VS Code, etc.) on account switch
- 11-language localization (EN, 简中, 繁中, 日, 韩, 法, 德, 意, 西, 俄, 荷)

---

## Install

### Requirements

- macOS 14+ (Sonoma)
- Xcode 17+ / Swift 6 (for building from source)

### Download

Grab the latest `.dmg` from [GitHub Releases](https://github.com/CottonChou/CodeXPool/releases).

### Build from source

```bash
git clone https://github.com/CottonChou/CodeXPool.git
cd CodeXPool
xcodebuild -project CodeXPool.xcodeproj -scheme CodeXPool -configuration Release -destination 'platform=macOS' build
```

---

## How It Works

```
┌─────────────────────────────────────────────────┐
│                  CodeXPool                      │
│  ┌───────────┐  ┌───────────┐  ┌────────────┐  │
│  │  Codex    │  │  Claude   │  │  Settings   │  │
│  │ (terminal)│  │ (sparkles)│  │ (gear)      │  │
│  └─────┬─────┘  └─────┬─────┘  └────────────┘  │
│        │              │                         │
│  ┌─────┴──────┐  ┌────┴──────┐                  │
│  │ ChatGPT    │  │ API Key   │                  │
│  │ Accounts   │  │ Profiles  │                  │
│  ├────────────┤  └───────────┘                  │
│  │ API Key    │                                 │
│  │ Profiles   │        writes to                │
│  └────────────┘   ~/.claude/settings.json       │
│        │                                        │
│   writes to                                     │
│   ~/.codex/auth.json                            │
│   ~/.codex/config.toml                          │
│   ~/.codex/state_5.sqlite                       │
└─────────────────────────────────────────────────┘
```

### Config Files Managed

| Tool | File | What CodeXPool writes |
|------|------|-----------------------|
| Codex | `~/.codex/auth.json` | OAuth credentials (ChatGPT mode) |
| Codex | `~/.codex/config.toml` | Model, provider, base URL, wire API (API Key mode) |
| Codex | `~/.codex/state_5.sqlite` | Thread `model_provider` normalization |
| Claude | `~/.claude/settings.json` | `env.ANTHROPIC_AUTH_TOKEN`, `env.ANTHROPIC_BASE_URL` |

### Thread Visibility Repair

Codex desktop only displays threads whose `model_provider` matches the currently active provider. When you switch between ChatGPT login and API Key mode, threads created under the other mode become invisible. CodeXPool automatically normalizes all unarchived threads to the target provider on every switch, so **nothing disappears**.

---

## Architecture

```
Sources/CodeXPool/
├── App/              # AppContainer, RootScene, entry point
├── Domain/           # Models, protocols, business rules
├── Behavior/         # AccountsCoordinator (central state machine)
├── Features/
│   ├── Accounts/     # ChatGPT account views + API Key profile views
│   ├── Claude/       # Claude API Key profile views
│   └── Settings/     # Preferences UI
├── Infrastructure/   # File I/O, config services, iCloud sync
├── UI/               # Shared components, layout rules
└── Resources/        # Localized strings (11 languages)
```

---

## Reference Projects

- [AlickH/Copool](https://github.com/AlickH/Copool) — original CodeXPool project and SwiftUI architecture
- [steipete/CodexBar](https://github.com/steipete/CodexBar) — macOS menu bar usage tracker for Codex, Claude, and more (UI/icon inspiration)
- [170-carry/codex-tools](https://github.com/170-carry/codex-tools) — original Tauri-based Codex tools
- [letdanceintherain/Codex-Auth-Switcher](https://github.com/letdanceintherain/Codex-Auth-Switcher) — Windows auth switching reference
- [farion1231/cc-switch](https://github.com/farion1231/cc-switch) — cross-platform AI CLI tool manager (multi-tool design inspiration)

## License

Please follow the upstream license and your organization's compliance requirements when reusing code from referenced projects.

复用参考项目代码时，请遵循上游许可证与所在组织的合规要求。
