# Issues

Work orders for coding agents, managed by [forge](https://github.com/Lightblues/forge). One Markdown file per issue.
This README is ignored by forge; regenerate it with `forge init --force`.

## Layout

```
.ea/issues/<status>/<id>.md      status: todo | in_progress | review | blocked | done
```

- id: `nexus-<NNN>`, equal to the file name; next number = highest existing + 1 (`forge ls`).
- The directory and the `status` field always agree. Change both with `forge mv <id> <status>`, not a plain `mv`.
- `review`: finished by an agent, waiting for a person. Used when `review: true`; otherwise agents finish into `done`.
  Say "done" / "完成" to the agent that ran it: it ticks what you confirmed, moves the issue to `done`, and applies `delivery`.
- Repository defaults (`prefix`, `delivery`, `review`, `unattended`, `provider`, `mode`, `host`) live in `.ea/forge.yaml`; issue fields override them.

## File

Frontmatter (YAML), schema v1:

| Field | Required | Meaning |
|---|---|---|
| `schema_version` | yes | `1`. Tools refuse other values |
| `id`, `title`, `status` | yes | Title is imperative, under 80 characters |
| `priority`, `estimate` | no | `low`..`urgent`; `S` (<15 min), `M` (15-60 min), `L` (1-4 h) |
| `labels`, `blocked_by` | no | Free-form list; issue ids |
| `host`, `cwd`, `provider`, `mode` | no | Where and how to run. `host` is a forge alias (default `local`). `cwd` defaults to the checkout `forge link` recorded for that host |
| `delivery`, `review` | no | On reaching `done`: `none`, `commit` (current branch), or `push`; `true` finishes into `review/` first |
| `unattended` | no | `true` (default): the agent starts with Auto Accept. `false`: permission prompts wait for you |
| `workspace_id`, `agent_id`, `dispatched_at` | no | Written by `forge run`, or by `forge attach` for a session already open. Do not edit |

Unknown fields are preserved. Body sections: `## Objective`, `## Context` (verified paths), `## Tasks`
(`- [ ]`, one change each), `## Acceptance` (observable checks), `## Boundaries` (`Always:` / `Never:` / `Ask:`),
and `## Outcome`, appended by the agent that executed it. Build and test commands live in CLAUDE.md / AGENTS.md.

## Workflow

```
forge ls                         list issues
forge check <id>                 validate one file
forge run <id> [--host <alias>]  dispatch to an agent; moves it to in_progress/
forge attach <id>               record the current Paseo session, when the issue has no agent yet
forge open <id>                 open that agent in the Paseo App
forge status <id>                agent state and latest output
```

The executing agent appends `## Outcome` and moves the file to `done/` (`review/` when review is on),
or back to `todo/` if it stopped early. To continue with that agent, run `forge open <id>` or `forge send <id> "..."`.

## Nexus conventions

Repository-specific rules layered on top of the generic workflow above.

- **Id prefix:** `nexus`, from `prefix` in `.ea/forge.yaml`. Ids are `nexus-<NNN>` and always equal the file name.
- **Next id:** highest existing number under `.ea/issues/` plus one. Read the current maximum with
  `forge ls` (or `ls .ea/issues/*/`); the legacy `nexus-001`..`nexus-011` records were archived to
  `.ea/spec/legacy-electron-issues.md` and their numbers are free to reuse.
- **Delivery:** `delivery: none` is the repository default in `.ea/forge.yaml`. Nexus requires human
  review before any commit (see `CLAUDE.md`: "NEVER use `git commit` directly"), so an issue that
  reaches `done` must not commit or push on its own — a person commits after review.
- **Issue language:** write the issue body in English, consistent with `.ea/spec/`.
- **Execution:** follow the `forge-run` agent skill, installed by `forge setup` at
  `~/.claude/skills/forge-run/SKILL.md`.
- **Closing:** follow the `forge-close` agent skill, installed by `forge setup` at
  `~/.claude/skills/forge-close/SKILL.md`.
