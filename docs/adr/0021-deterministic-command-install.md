# ADR-0021 — Deterministic command install: `aflow install-commands`

- **Status:** Accepted
- **Date:** 2026-06-01
- **Phase:** post-11 (command distribution)

## Context

The pipeline commands (`aflow-analyze-ticket.md`, `aflow-pipeline.md`, …) ship
under `core/commands/` and must be installed into an AI agent platform before
they can be invoked. Until now, that install was **agent-driven only**: the user
ran `aflow commands-path`, opened the bundled `INSTALL.md`, and pasted its
contents into their agent, which read the prompts and placed them where the host
platform discovers commands.

This approach has two drawbacks:

1. **Requires an agent session to bootstrap.** A user who wants to set up ALEA
   before opening their agent cannot complete the install without one.
2. **Reliability is platform-dependent.** The agent must interpret INSTALL.md
   correctly, handle cross-platform path differences, and write files in the
   right location and format. Mis-installs are silent — the command simply
   doesn't appear.

## Decision

Add `aflow install-commands`, a CLI command that deterministically installs the
bundled prompts into supported AI agent platforms.

### Design — port / adapter

The implementation follows the same hexagonal pattern as the rest of the codebase:

- **Contract (`PlatformCommandAdapter`)** — `lib/src/contracts/platform_command_adapter.dart`.
  Defines `platformId`, `displayName`, `argumentsToken`,
  `targetPath(commandId, {required String projectRoot})` (returns the absolute
  destination path), and `render(CommandPrompt prompt)` (returns the
  platform-formatted file content; the adapter applies the argument-token
  rewrite inside `render`).
- **Concrete adapters** — one per platform under
  `lib/src/adapters/platform_commands/{claude,gemini,codex,cursor}/adapter.dart`.
- **Factory** — `lib/src/adapters/platform_commands/factory.dart` maps string
  ids → adapter instances.
- **Pure installer** — `lib/src/cli/install/installer.dart`. Stateless: takes a
  list of adapters + a prompt loader, writes files (or dry-runs), returns a
  result per prompt per platform.
- **Prompt loader** — `lib/src/cli/install/prompt_loader.dart`. Locates
  `core/commands/` relative to the resolved package root (works from both a
  pub-cache install and a path-activated clone).
- **CLI command** — `lib/src/cli/commands/install_commands_command.dart`.
  Registered in `AleaCliRunner._wire()` as `install-commands`.

### Four platforms in v1

Each adapter was verified against official platform documentation:

| Platform | Destination | Format | Arg token |
|---|---|---|---|
| Claude Code | `.claude/commands/<id>.md` | Markdown + YAML frontmatter (`description`) | `$ARGUMENTS` (native) |
| Gemini CLI | `.gemini/commands/<id>.toml` | TOML (`description` + `prompt = """..."""`) | `{{args}}` |
| Codex | `$CODEX_HOME/prompts/<id>.md` (default `~/.codex/prompts/`) | Markdown + frontmatter (`description`, `argument-hint`) | `$ARGUMENTS` (supported placeholder) |
| Cursor | `.cursor/commands/<id>.md` | Markdown + YAML frontmatter (`name`, `description`) | `$ARGUMENTS` (kept as-is) |

Claude Code, Gemini CLI, and Cursor destinations are **project-local** (relative
to `--project-root`, default `.`). **Codex** is different: it installs to a
**global** directory (`$CODEX_HOME/prompts/`, default `~/.codex/prompts/`) —
one install covers all projects on the machine.

### Argument-token normalisation

Each source prompt uses `$ARGUMENTS` as the argument placeholder. Adapters that
require a different token (`{{args}}` for Gemini CLI) rewrite it inside
`render(CommandPrompt)`. Platforms that support `$ARGUMENTS` natively pass the content
through unchanged.

### `description:` frontmatter on source prompts

All 18 pipeline prompt files gained a `description:` YAML frontmatter line.
Adapters read this field to populate each platform's equivalent
(`description` in Claude Code / Gemini / Cursor frontmatter; `argument-hint` is
filled with a generic hint for Codex).

### `aflow init` integration

When `--platform <id>` (or `--platform all`) is passed to `aflow init`, the
command runs the shared install routine at the end of the onboarding sequence
(after `.alea.yaml` is written). This means a single `aflow init --template
config --platform claude` bootstraps the config AND installs the commands.

### CLI behaviour

| Mode | Trigger |
|---|---|
| Interactive multi-select | TTY detected, no `--platform` flag |
| Non-interactive | `--platform claude,gemini,codex,cursor` or `--platform all` |

Flags: `--project-root` (default `.`), `--dry-run` (prints plan, writes
nothing). Exit codes: `0` success, `2` locate/parse/IO failure, `64` usage
error (unknown platform or non-TTY without `--platform`).

### INSTALL.md retained as fallback

`core/commands/INSTALL.md` remains the agent-driven path for platforms not yet
covered by a deterministic adapter. The `references/README.md` contract
documents both paths.

## Consequences

**Positive:**

- Install is reproducible, auditable, and scriptable — no agent session required.
- Adding a fifth platform = one new adapter class + one line in the factory.
  No changes to the installer, prompt loader, or existing adapters.
- `aflow init --platform` collapses bootstrap to a single command.
- Source prompts now carry `description:` metadata that is also useful for
  humans reading them directly.

**Negative / caveats:**

- **Codex global install**: Codex prompts land in `~/.codex/prompts/` (or
  `$CODEX_HOME/prompts/`), not in the project tree. This is the correct Codex
  behaviour, but it differs from every other platform and may surprise users who
  expect a project-local install.
- **Codex deprecation**: Codex custom prompts are deprecated upstream in favour
  of "skills". The `codex` adapter targets the still-functional `prompts/`
  mechanism; a future `codex-skills` adapter may supersede it when the skills
  API stabilises.
- **CLI surface growth**: `AleaCliRunner._wire()` registers the new
  `install-commands` subcommand alongside the existing ones. The extension
  mechanism from ADR-0010 ("one new file + one line") handled this without
  architectural change.

## References

- `lib/src/contracts/platform_command_adapter.dart`
- `lib/src/adapters/platform_commands/{claude,gemini,codex,cursor}/adapter.dart`
- `lib/src/adapters/platform_commands/factory.dart`
- `lib/src/cli/install/{installer,prompt_loader}.dart`
- `lib/src/cli/commands/install_commands_command.dart`
- `core/commands/INSTALL.md` (agent-driven fallback)
- `core/commands/references/README.md` (platform contract)
- `test/cli/install_commands_command_test.dart`
