---
description: Create or refresh the repository's status file, docs/ai/status.md — the one source of truth for what is done, in progress and deployed, which every parallel session reads and the follow-through Stop gate keeps current. Use when a project has no status file yet, when importing an existing plan/«Ревизия» artifact into the repo, when the user asks what is done or what is deployed where, or when the status file disagrees with the code.
---

# Status file

`docs/ai/status.md` is the plan's state, in the repository, versioned. Every session of the repository
reads it (siblings' `doing` rows reach you through follow-through's awareness block), and the Stop gate
refuses a commit, merge, push or deploy that did not update it. A «Ревизия» artifact, when there is one,
is a **mirror** of this file — rebuilt from it, never edited on its own.

## Shape

```markdown
---
mirror: https://claude.ai/artifact/<id>      # optional — the plan page republished from this file
environments:                                # optional — how to tell what is deployed where
  staging:
    branch: origin/staging                   # CD deploys this branch
    version_url: https://api-staging.example.com/version   # returns the deployed commit, if the app has it
    deploy_cmd: deploy\.sh staging           # a regex for the command that deploys it
  production:
    branch: origin/production
---
# Status — <project>

## <Phase or block>

| ID | Item | Status | Lane | Proof | Updated |
|---|---|---|---|---|---|
| P1 | <the item, in the plan's own words> | todo · doing · done · blocked · dropped | <branch or worktree> | <commit / PR / test / deploy> | YYYY-MM-DD |
```

Rules:

- **Status is one word** from the list. `done` needs a proof cell; `dropped` needs the reason in the item
  and when the user agreed.
- **Lane** is the branch or worktree that owns a `doing` row, so a sibling session knows whom to message.
- **Updated in the same turn** as the change that moved it — never batched for later.
- Rows keep their IDs forever; new work is appended, finished work stays (with its proof).

## Steps

1. **Read what exists.** If the user names a plan artifact (a «Ревизия»), read it with the Artifact tool
   (`action: read`) — every phase, item and mark. Otherwise read the spec(s), the groundwork checkpoint
   (`.claude/groundwork/task-state.md`) and `git log` of the integration branch.
2. **Verify before you mark.** An item is `done` only when its proof exists in the integration branch
   (the commit is reachable from `origin/development` or the configured base) — check with `git branch
   -r --contains <sha>` or by reading the code. What the artifact claimed but the code does not show is
   written as `doing` or `todo`, and you tell the user which rows changed and why.
3. **Environments.** For each environment the project deploys to, fill `branch` from the CD config
   (`.github/workflows/*`, deploy scripts), `deploy_cmd` from the deploy script's invocation, and
   `version_url` only if the app exposes one. Then report, per environment: deployed commit, and how far
   it is behind the integration branch (`git rev-list --count <env-branch>..<base>`). If a `version_url`
   exists, read it — that is the live answer; the branch is only what CD was asked to deploy.
4. **Write the file**, commit it on the current lane (it merges like any file), and if there is a
   mirror, republish the artifact from the file in the same turn: render it with
   `python3 "${CLAUDE_SKILL_DIR}/../../hooks/render_status.py" <repo> <scratchpad>/status.html`, then
   publish that file with the Artifact tool and `url` = the `mirror:` value. A new mirror is a first
   publish of the rendered file; put its URL into `mirror:` and republish once more. Never edit the
   mirror page by hand — it is rebuilt from the file every time.
5. **Answer «на сервере всё актуально?»** from this file plus `version_url` — one line per environment,
   no investigation the file already answers.
