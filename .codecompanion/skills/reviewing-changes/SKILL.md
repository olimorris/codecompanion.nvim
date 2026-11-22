---
name: reviewing-changes
description: Reviewing CodeCompanion.nvim changes against STYLE.md before reporting work as done. Use after changing anything in `lua/` or `tests/`
---

# Reviewing Changes

Review the finished diff, not the plan. Names, tests and patterns drift during a long change, and a refactor late in a session introduces names nothing else checks. Work through every step, fixing what you find as you go. [STYLE.md](../../../STYLE.md) holds the rules; this skill is the order to apply them in.

## 1. Gather the Change

The change is everything on the branch since it left `main`, committed or not. Run `git diff $(git merge-base main HEAD)` for the committed and uncommitted changes together, and `git status --short` for untracked files, then read each untracked file whole.

Done when you hold a list of every new and modified file on the branch.

## 2. Read Every Name at Its Call Site

List every public name the change adds or renames: module functions, methods, class fields, chat fields and the local name each `require` is bound to. For each one, find a real call site with `rg` and read it as callers see it, with the module or object in front: `subagents.patch(...)`, `connection.subagents:is_known(...)`, `chat.acp_permissions.respond`.

The call site has to say what happens:

- `module.func` reads as one phrase about this module. `subagents.patch` claims to patch subagents, so a function that applies any upsert belongs elsewhere under a name like `acp.apply_upsert`.
- The verb matches the effect. A function that only marks tool calls as cancelled is `mark_cancelled`, never `cancel`, especially beside a real `cancel`.
- A field reads as data and a method as an action. A stored function named `respond` reads like a method; `respond_to_agent` says what it holds.
- A name says what makes it different from its neighbours. `is_known` on a subagents object reads as "is a known subagent", so `is_known_session` for one that also accepts the parent session.

Then apply STYLE.md §3 to the locals in each hunk.

Done when every name on the list has had its call site read, and every rename has been applied to the code, the tests and the annotations.

## 3. Map Behaviour to Tests

A behaviour is an outcome a user or caller would notice: what the chat shows, what reaches the agent, what state a caller reads back. A branch in the code is not a behaviour by itself, so a guard clause, a nil check or a type check gets no case of its own. Follow STYLE.md §5 and the Testing section of AGENTS.md: a new module gets a test file mirroring its path, and a case goes in the file of the module whose behaviour it tests.

For each behaviour the change adds or alters, name the case that pins it down. Write the case for any behaviour that has none. Then read every case the change added and cut any whose outcome is plain from the line of code it tests:

- a conditional that returns early
- a value that passes through unchanged
- a setting read straight back. `advertises the capability when ENABLED` and `DOES NOT advertise the capability when DISABLED` only prove that an `if` on a config flag works

Ask whether the case could fail without someone deliberately breaking that line. If it couldn't, cut it.

Done when every behaviour maps to a case that would fail without the change, and every case the change added pins a behaviour.

## 4. Cut What the Change Doesn't Need

Aim for the smallest diff that does the job. Go through each hunk and delete:

- a guard or fallback for a condition no caller can produce (STYLE.md §6)
- a parameter, field or return value nothing reads
- a helper with one caller that only renames the call it wraps
- logic that repeats another hunk, keeping one copy
- code left behind by an approach the change later dropped

Done when deleting any remaining line would change what a user or caller sees.

## 5. Apply the Patterns

Walk STYLE.md §2, §4 and §8 hunk by hunk: comments, opts tables, returned tables, one-line descriptions, function length and scope.

Done when every rule has been applied to every hunk.

## 6. Prove It

Run `make format`, then `make test`.

Done when the full suite passes. Report the case count, the renames, cuts and fixes this review made, and any name you kept although it reads awkwardly, with the reason.
