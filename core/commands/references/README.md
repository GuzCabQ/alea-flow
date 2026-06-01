# `references/` — Platform adapter contract

The prompts in `core/commands/` are **platform-agnostic** (the port). A real AI-driven CLI must map a small set of abstract operations to its own tools. Each platform gets one adapter file here (`<platform>-tools.md`), exactly like the code has one `CodeGenAdapter` contract and N concrete adapters (`bloc/`, `riverpod_manual/`).

The agnostic part is the prompts + this contract; a `<platform>-tools.md` is the only place platform specifics live. Adding a platform = filling this template, never editing a prompt.

## The contract — operations every platform MUST map

| Operation | What the prompts rely on |
|---|---|
| **Command invocation** | How the host dispatches a `/command` (e.g. `/aflow-analyze-ticket DEV-1`) and how the command receives `$ARGUMENTS` (the tokens after the command name). |
| **Shell execution** | Run a shell command and capture **stdout, stderr, and the exit code** separately. The whole "code disposes" model depends on exit codes (`0` pass, `1` fail, `2` config/parse, `64` usage) — a platform that cannot read exit codes cannot run this pipeline. |
| **File read/write** | Read a file's contents; create/overwrite a file at a project-relative path (the prompts write `.pipeline/runs/<id>/*.json`, `.pipeline/graph.json`, `.alea.yaml`). |
| **Command distribution** | How the commands get *installed* so the host can discover them. The CLI provides the platform-agnostic "where" — `aflow commands-path` prints the absolute path to these prompts; the adapter documents the platform-specific "where they go". **`aflow install-commands` automates installation deterministically for Claude Code, Gemini CLI, Codex, and Cursor** (verified locations + formats, v1 — see [ADR-0021](../../../docs/adr/0021-deterministic-command-install.md)). [`../INSTALL.md`](../INSTALL.md) remains the agent-driven fallback for platforms not yet covered by a deterministic adapter. |

That is the complete v1 contract. The pipeline prompts do **not** require subagent dispatch, parallel execution, or network primitives — do not add them to an adapter (YAGNI). "Dispatch to the adapter" in `implement-*.md` refers to **code-gen** adapters, not platform tools.

## Adapters present

| Platform | File |
|---|---|
| Claude Code | [`claude-code-tools.md`](claude-code-tools.md) |

To add another platform: copy the three-operation table and document how that host performs each.
