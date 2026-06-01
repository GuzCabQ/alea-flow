# Claude Code — platform tools adapter

Implements the [platform-adapter contract](README.md) for Claude Code (and Claude Agent SDK CLIs). The pipeline prompts are agnostic; this file is the only Claude-Code-specific piece.

## Command invocation

- A `/command DEV-1234 --flag` is invoked by the user (or `/aflow-pipeline`) as a slash command. The markdown file `core/commands/<command>.md` IS the prompt.
- `$ARGUMENTS` = everything after the command name (`DEV-1234 --flag`). The prompt parses the ticket id from the first token and detects flags itself (see each command's "Parse arguments" step).

## Shell execution

- Use the **Bash** tool. It returns stdout, and the exit code is observable (a non-zero exit surfaces as an error). Capture both.
- Exit-code contract the prompts depend on: `0` pass · `1` gate fail · `2` config/parse error · `64` usage error. When a step says "treat non-zero as a hard stop", check the Bash result's exit status — do not infer success from stdout text.
- stderr carries warnings (e.g. `aflow graph --ensure-fresh` prints `graph fresh … — skipped rebuild`); it is informational unless the exit code is non-zero.

## File read/write

- Read with the **Read** tool; create/overwrite with the **Write** tool; patch in place with **Edit**.
- Project-relative paths resolve against the consumer project root (the working directory where `/aflow-pipeline` runs).

## Command distribution (installation)

- Claude Code discovers slash-commands from `.claude/commands/*.md` (project) or `~/.claude/commands/` (user). The command name is the filename (`aflow-pipeline.md` → `/aflow-pipeline`).
- Install: copy every command `*.md` from `aflow commands-path` (excluding `INSTALL.md` and `references/`) into the project's `.claude/commands/`. The agent-driven [`../INSTALL.md`](../INSTALL.md) does exactly this.

## Notes

- No subagent dispatch is required by the pipeline. If a future command needs it, extend the contract first, then this adapter.
