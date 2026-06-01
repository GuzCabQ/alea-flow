# Gemini CLI — platform tools adapter

Implements the [platform-adapter contract](README.md) for Gemini CLI. The pipeline prompts are agnostic; this file is the only Gemini-CLI-specific piece.

## Command invocation

- A command is invoked by providing the markdown file `core/commands/<command>.md` as the prompt context, along with the necessary arguments.
- `$ARGUMENTS` = The tokens provided after the command intent (e.g., `DEV-1234 --flag`). The prompt parses the ticket id from the first token and detects flags itself (see each command's "Parse arguments" step).
- In multi-turn sessions, the agent maintains the state of `$ARGUMENTS` across steps.

## Shell execution

- Use the `run_shell_command` tool.
- It returns the combined stdout and stderr in the `Output` field.
- The `Exit Code` is explicitly returned if it is non-zero. If omitted, the exit code is `0`.
- Exit-code contract: `0` pass · `1` gate fail · `2` config/parse error · `64` usage error.
- Use the `is_background` parameter for long-running processes (not typically used by the pipeline).

## File read/write

- **Read**: Use the `read_file` tool to retrieve file contents. Use `start_line` and `end_line` for efficiency on large files.
- **Write/Create**: Use the `write_file` tool to create or overwrite files (e.g., writing artifacts to `.pipeline/runs/`).
- **Patch/Edit**: Use the `replace` tool for targeted updates to existing files.
- Project-relative paths resolve against the workspace root.

## Command distribution (installation)

- Gemini CLI discovers custom commands from TOML files under `.gemini/commands/` (project) or `~/.gemini/commands/`, and reads `GEMINI.md` for context. The exact mapping of a markdown prompt to a Gemini custom command should be verified against the current Gemini CLI docs.
- Install: take every command `*.md` from `aflow commands-path` (excluding `INSTALL.md` and `references/`) and register each as a custom command in Gemini's mechanism. The agent-driven [`../INSTALL.md`](../INSTALL.md) delegates this to the agent, which knows its own platform's current conventions.

## Notes

- Gemini CLI supports subagent dispatch via `invoke_agent`, which can be used for complex sub-tasks, though the v1 pipeline contract focuses on direct tool use.
