* 🚀 [Humanize2](https://github.com/humanfia/humanize2) is under active developments and we are looking for your feedbacks! 
* ✨ Now humanize has a [cool homepage](https://humanfia.ai/)!

# Humanize

**Current Version: 1.16.0**

> Derived from the [GAAC (GitHub-as-a-Context)](https://github.com/SihaoLiu/gaac) project.

An iterative development workflow with independent AI review. Humanize supports
both Claude-primary/Codex-reviewer and Codex-primary/Claude-reviewer setups.

## What is RLCR?

**RLCR** stands for **Ralph-Loop with Codex Review**, inspired by the official ralph-loop plugin and enhanced with independent Codex review. The name also reads as **Reinforcement Learning with Code Review** -- reflecting the iterative cycle where AI-generated code is continuously refined through external review feedback.

## Core Concepts

- **Iteration over Perfection** -- Instead of expecting perfect output in one shot, Humanize leverages continuous feedback loops where issues are caught early and refined incrementally.
- **One Build + One Review** -- One AI implements while another independently reviews. No blind spots.
- **Ralph Loop with Swarm Mode** -- Iterative refinement continues until all acceptance criteria are met. Optionally parallelize with Agent Teams.
- **Begin with the End in Mind** -- Before the loop starts, Humanize verifies that *you* understand the plan you are about to execute. The human must remain the architect. ([Details](docs/usage.md#begin-with-the-end-in-mind))

## How It Works

<p align="center">
  <img src="docs/images/rlcr-workflow.svg" alt="RLCR Workflow" width="680"/>
</p>

The loop has two phases: **Implementation** and **Code Review**. Role assignment
depends on the installation mode: Claude can implement with Codex reviewing, or
Codex can implement with Claude reviewing. Issues feed back into implementation
until resolved.


## Install

### Claude primary, Codex reviewer

```bash
# Add PolyArch marketplace
/plugin marketplace add PolyArch/humanize
# If you want to use development branch for experimental features
/plugin marketplace add PolyArch/humanize#dev
# Then install humanize plugin
/plugin install humanize@PolyArch
```

Requires [Codex CLI](https://github.com/openai/codex) for review. See the full
[Claude-primary installation guide](docs/install-for-claude.md) for prerequisites
and alternative setup options.

### Codex primary, Claude reviewer

From the Humanize repository root, run:

```bash
./scripts/install-codex-primary-claude-reviewer.sh
```

This fixes the primary agent to `gpt-5.6-sol:xhigh`, fixes the independent
reviewer to `claude-opus-5:max`, installs the Codex skills and native Stop hook,
and verifies both CLI authentications and the installed configuration.

Optional commands:

```bash
# Preview without writing
./scripts/install-codex-primary-claude-reviewer.sh --dry-run

# Include one real Claude reviewer call in post-install verification
./scripts/install-codex-primary-claude-reviewer.sh --smoke-test
```

Codex CLI and Claude Code must already be installed and authenticated. Restart
running Codex sessions after installation. See the full
[Codex-primary installation guide](docs/install-for-codex.md) for prerequisites,
custom paths, and troubleshooting.

## Quick Start

1. **Generate an idea draft** from a loose thought (optional — skip if you already have a draft):
   ```bash
   /humanize:gen-idea "add undo/redo to the editor"
   ```
   Output goes to `.humanize/ideas/<slug>-<timestamp>.md` by default. Pass a `.md` path to expand existing rough notes. `--n` controls how many parallel directions explore the idea (default 6).

2. **Generate a plan** from your draft:
   ```bash
   /humanize:gen-plan --input draft.md --output docs/plan.md
   ```

3. **Refine an annotated plan** before implementation when reviewers add comments (`CMT:` ... `ENDCMT`, `<cmt>` ... `</cmt>`, or `<comment>` ... `</comment>`):
   ```bash
   /humanize:refine-plan --input docs/plan.md
   ```

4. **Run the loop**:
   ```bash
   /humanize:start-rlcr-loop docs/plan.md
   ```

5. **Consult Gemini** for deep web research (requires Gemini CLI):
   ```bash
   /humanize:ask-gemini What are the latest best practices for X?
   ```

6. **Monitor progress (in another terminal, not inside Claude Code)**:
   ```bash
   source <path/to/humanize>/scripts/humanize.sh # Or just add it into your .bashec or .zshrc
   humanize monitor rlcr       # RLCR loop
   humanize monitor skill      # All skill invocations (codex + gemini)
   humanize monitor codex      # Codex invocations only
   humanize monitor gemini     # Gemini invocations only
   ```

## Monitor Dashboard

<p align="center">
  <img src="docs/images/monitor.png" alt="Humanize Monitor" width="680"/>
</p>

## Documentation

- [Usage Guide](docs/usage.md) -- Commands, options, environment variables
- [Install for Claude Code](docs/install-for-claude.md) -- Full installation instructions
- [Install for Codex](docs/install-for-codex.md) -- Codex skill runtime setup
- [Install for Kimi](docs/install-for-kimi.md) -- Kimi CLI skill setup
- [Configuration](docs/usage.md#configuration) -- Shared config hierarchy and override rules
- [Bitter Lesson Workflow](docs/bitlesson.md) -- Project memory, selector routing, and delta validation

## License

MIT
