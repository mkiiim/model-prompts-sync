# Consolidate Claude Global Instructions

This prompt reconciles live Claude instruction files across machines and
projects, then updates the canonical deployable `CLAUDE.md` in this repo.

Run it from any machine on the network. Do not assume the current machine has the
latest instruction rules.

`CLAUDE.md` is the source file that should be deployed directly to
`~/.claude/CLAUDE.md` on every machine.

---

## Step 1 - Confirm Scope

Before doing anything, ask the user to confirm or modify the following defaults.

**Machines to include:**
- Use `config/instruction-sync-machines.tsv` as the default target list
- Confirm any requested additions, removals, renames, or path changes before
  editing that config

**Personal config:**
- Read `config/consolidation-claude.md` — it defines your project paths to scan,
  any legacy reference files, and the output section order for Step 6

**Canonical output:**
- `CLAUDE.md` in the current directory

**Cross-assistant reference:**
- `AGENTS.md` in the current directory, if present, only for rules that should be
  shared across assistants

Wait for confirmation or changes before proceeding.

---

## Step 2 - Gather Live Machine Files

Run:

```bash
bash scripts/instruction-sync.sh gather
bash scripts/instruction-sync.sh diff
```

This snapshots live machine files before editing so rules added on another
machine are not silently lost.

If SSH or remote reads fail due to sandbox or network restrictions, rerun with
the required approval rather than treating the sandbox failure as the answer.

Do not print secrets, tokens, auth payloads, or sensitive local-only values.

---

## Step 3 - Gather Project-Level Claude Files

For each confirmed project pattern:

1. Expand `~` and globs from the machine where the prompt is running.
2. Verify which paths exist.
3. Find all `CLAUDE.md` files, checking both the repo root and
   `.claude/CLAUDE.md`.
4. Prefer `rg --files` over slow recursive `find` in large repositories.
5. Ignore worktree copies under `.claude/worktrees/`.
6. Note duplicate paths, symlinks, aliases, or case variants that resolve to the
   same checkout.

---

## Step 4 - Classify Rules

Classify each discovered rule and any new user-provided rule as one of:

- **General assistant behavior:** add to `CLAUDE.md` and tell the user the same
  rule should also be added to `AGENTS.md`.
- **Claude-specific behavior:** add only to `CLAUDE.md`.
- **Codex-specific behavior:** do not add to `CLAUDE.md`.
- **Project-specific behavior:** keep in the relevant project-local instruction
  file, not this repo's global files.
- **Machine-specific config:** exclude permissions, trust lists, auth, caches,
  logs, histories, host paths, model defaults, and hardware-specific settings.
- **Conflict:** surface the conflicting wording, recommend a resolution, and ask
  the user to choose before writing.

Keep:
- General working style and communication preferences
- Git safety rules
- Commit proposal and commit-message conventions
- Verification defaults
- Debugging discipline
- Documentation edit safety
- Secret-handling rules
- Rules about checking actual repo state before making claims

Discard or rewrite:
- Project-specific tech stacks, services, endpoints, deploy steps, architecture,
  data models, roadmaps, or status
- Local file paths unless needed as examples in the prompt itself
- Codex-, OpenAI-, or other assistant-specific mechanics
- Memory or violation mechanics that Claude cannot actually enforce
- Generated cache content, auth payloads, logs, history, and app state

---

## Step 5 - Resolve Conflicts

Present findings as three lists:

1. Rules consistent across sources - will be included directly
2. Rules present in some sources but not others - recommend whether to include
   them and where
3. Rules that directly conflict - show the specific wording from each source,
   recommend a resolution, and ask for approval

Do not write `CLAUDE.md` until conflicts and ambiguous classifications are
resolved. Handle one conflict at a time.

---

## Step 6 - Update CLAUDE.md

Once conflicts are resolved, update `CLAUDE.md` in the current directory.

Preserve useful existing structure and wording where it still matches the
resolved rules. Remove stale, duplicated, or rejected material deliberately.

The file should:
- Be Claude-facing
- Be directly deployable to `~/.claude/CLAUDE.md`
- Avoid project-specific content unless the user explicitly wants it
- Avoid Codex/OpenAI-specific language
- Avoid memory or violation mechanics that Claude cannot enforce
- Be concise enough to serve as durable global instructions

Use the section order defined in `config/consolidation-claude.md`, omitting any
section if there is nothing to put in it.

---

## Step 7 - Verify Output

After writing `CLAUDE.md`:

1. Read the written file back.
2. Search for unwanted terms and flag any found:

   ```text
   Co-Authored-By|Generated with|self-beratement|violation|memory system|Codex|OpenAI
   ```

3. Search for project-specific names from input sources unless the user
   explicitly asked to keep them.
4. Run `git diff -- CLAUDE.md` and report the changed rule groups.
5. Do not deploy, commit, or push unless the user explicitly approves.

---

## Step 8 - Deploy After Approval

After the repo change is approved, committed, and pushed, deploy with:

```bash
bash scripts/instruction-sync.sh deploy
bash scripts/instruction-sync.sh verify
```

Report any machine that could not be reached or did not verify.
