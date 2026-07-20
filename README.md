# model-prompts-sync

Tooling for keeping AI assistant instruction files consistent across multiple machines.

## The problem

When you use AI assistants (Claude, Codex, etc.) across multiple machines, each machine has its own global instruction file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`). Rules you add on one machine don't automatically appear on others. Over time they drift.

## How it works

You paste a consolidation prompt into your AI assistant. The assistant drives the entire process:

1. Gathers the live instruction files from all your configured machines
2. Reads any existing canonical files in this repo
3. Classifies every rule — what belongs in global instructions, what's project-specific, what's machine-specific config
4. Surfaces conflicts for you to resolve before writing anything
5. Writes updated canonical `CLAUDE.md` / `AGENTS.md` files in this repo once you approve
6. Deploys them to all machines and verifies

During consolidation the assistant runs the sync script (`scripts/instruction-sync.sh`) for you — you don't need to invoke it. You can also run it directly for routine tasks like deploying or checking drift (see "Deploying and verifying" below).

**For Claude:** open this repo in Claude Code, then paste the contents of `consolidate-by-claude.md` into the conversation.

**For Codex:** open this repo in Codex, then paste the contents of `consolidate-by-codex.md` into the conversation.

## Setup

1. Clone this repo
2. Copy the example config: `cp config/instruction-sync-machines.tsv.example config/instruction-sync-machines.tsv`
3. Edit `config/instruction-sync-machines.tsv` with your machine details (see below)
4. Copy the example config for the assistant you use:
   - `cp config/consolidation-claude.example.md config/consolidation-claude.md`
   - `cp config/consolidation-codex.example.md config/consolidation-codex.md`
5. Edit the config file — add your project paths, any legacy instruction files, and your preferred output section order
6. Paste the consolidation prompt into your assistant and follow the conversation

The assistant will create `CLAUDE.md` and/or `AGENTS.md` in this repo from what it finds on your machines. You commit and push after approving the output, and the assistant then deploys to your machines and verifies.

## Deploying and verifying

The full consolidation conversation ends with the assistant deploying and verifying for you. But once your canonical `CLAUDE.md` / `AGENTS.md` exist in this repo, you can also run the sync script directly at any time — for example after a small hand-edit to a canonical file, or after adding a new machine to the config:

```bash
# Snapshot the live instruction files from every configured machine
bash scripts/instruction-sync.sh gather

# Show what differs between the live machine files and the canonical files
bash scripts/instruction-sync.sh diff

# Copy the canonical files to every configured machine
bash scripts/instruction-sync.sh deploy

# Confirm every machine's deployed files match the canonical files
bash scripts/instruction-sync.sh verify
```

Deployment targets are taken from `config/instruction-sync-machines.tsv`: `AGENTS.md` is copied to each machine's `codex_path`, `CLAUDE.md` to each machine's `claude_path`.

Note: `deploy` and `verify` always operate on both canonical files, so both `AGENTS.md` and `CLAUDE.md` must exist in the repo before running them — even if you only use one assistant.

## Configuration

`config/instruction-sync-machines.tsv` lists your machines. Format:

```
id|ssh_host|codex_path|claude_path
```

- `id` — label for the machine (used in snapshot directory names)
- `ssh_host` — SSH hostname, or `local` for the machine running the script
- `codex_path` — path to the Codex instruction file on that machine
- `claude_path` — path to the Claude instruction file on that machine

SSH hosts must be resolvable by your SSH config. Tailscale hostnames work well for cross-network machines.
