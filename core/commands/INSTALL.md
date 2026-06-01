# Install the alea-flow pipeline commands into your AI agent

> **How to use:** paste this file's contents to your AI coding agent (Claude Code,
> Gemini CLI, Cursor, Codex, Windsurf, …) and ask it to follow the steps. The
> agent installs the commands the way *your* platform expects — alea-flow does not
> hard-code any single platform.

---

You are an AI coding agent. Install the **alea-flow** pipeline commands into this
project so the user can invoke them (`/aflow-analyze-ticket`, `/aflow-complete-config`,
`/aflow-pipeline`, `/aflow-review-feature`, …) on this platform.

## Steps

1. **Find the commands.** Run `aflow commands-path` in a shell. It prints the
   absolute path to a directory of platform-agnostic prompt files (`.md`). If the
   command fails, `aflow` is not installed/on PATH — tell the user to install
   alea-flow first and stop.

2. **Identify the commands.** Each `*.md` directly in that directory is ONE
   command; its filename is the command name (`aflow-pipeline.md` → `/aflow-pipeline`,
   `aflow-complete-config.md` → `/aflow-complete-config`). **Exclude** `INSTALL.md` (this
   file) and the `references/` subfolder — `references/` is the platform-adapter
   contract, not a command.

3. **Install them where this platform discovers commands**, in its expected
   location and format:
   - **Claude Code** → copy each command `.md` into `.claude/commands/` in the
     project (filename = command name).
   - **Other platforms** (Gemini CLI, Cursor, Codex, Windsurf, …) → use your
     platform's custom-command / prompt-file mechanism. If you are unsure of the
     exact location or format, consult your platform's documentation for "custom
     commands" or "slash commands" and adapt accordingly.

4. **Read the adapter contract.** Read `references/README.md` and, if it exists,
   `references/<your-platform>-tools.md`. These map the abstract operations the
   prompts rely on — **shell execution with readable exit codes**, file
   read/write, command invocation — to your platform's tools.
   - ⚠️ The pipeline depends on running `aflow …` in a shell and reading its
     **exit code** (`0` pass · `1` gate fail · `2` config/parse · `64` usage). If
     your platform cannot execute shell commands and read their exit codes, it
     **cannot run this pipeline** — tell the user and stop.

5. **Confirm.** Report to the user which commands you installed, where, and how to
   invoke them on this platform.

## Notes

- **Do not edit the command prompts** — they are platform-agnostic by design. Only
  place them where your platform finds commands.
- **Re-run this** after upgrading alea-flow to pick up new or changed commands.
- First command to run after install: **`/aflow-complete-config`** — it grounds your
  `.alea.yaml` against the code graph.
