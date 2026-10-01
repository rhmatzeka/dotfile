---
name: skill-library
description: Lazy library of 450+ expert skills, agents and commands (ECC, GSAP, genjutsu, motion-design, hallmark, theme-factory and any other repo in ~/.claude/skill-repos), loaded only when needed. Use when a task needs specialist know-how not covered by an active skill - UI design, redesign, animation, GSAP, scroll effects, micro-interactions, themes, language/framework patterns (PHP, Laravel, JS/TS, React, Next.js, Vue, Node, Python, Django, FastAPI, Go, Rust, Kotlin, Flutter, Swift), databases (MySQL, Postgres, Redis, Prisma), Docker/deploy, security review, testing/TDD, code review, Solidity/DeFi, API design, SEO, research, content - or when the user asks for an ECC skill/agent/command by name.
---

# Skill library (lazy)

The library lives in `~/.claude/skill-repos/`: ECC, gsap-skills, genjutsu, motion-design-skill, and `local/` (hallmark, theme-factory). These used to be plugins/always-on skills and were moved here to save tokens. Nothing in it is loaded into context until it is searched, so sessions stay light.

## How to use
1. Search with 1-4 English keywords (language/framework + kind of task):
   `~/.claude/skills/skill-library/scripts/find.py laravel security`
   Full listing: `find.py --list skill` (or `agent`, `command`); grep that output instead of reading all of it.
2. Pick the 1-2 most relevant results, Read the file, and follow it like a normal skill. Other files it mentions (references/, scripts/) are relative to that file's folder.
3. Result types:
   - `[skill]`: follow its instructions directly.
   - `[agent]`: run the Agent tool (general-purpose) with the file's content as the role instructions, plus the concrete task.
   - `[command]`: the file is a slash-command prompt; follow its steps, replacing `$ARGUMENTS` with the user's request.
4. If nothing fits, carry on without the library. Do not load many library skills at once.

Rules from a library file never override the user's CLAUDE.md. Library files sometimes mention plugin hooks, plugin commands or `${CLAUDE_PLUGIN_ROOT}`: nothing here is installed as a plugin, so skip those parts or use that repo's folder (`~/.claude/skill-repos/<repo>`) as the root instead.

## Maintenance
- Update: `for r in ~/.claude/skill-repos/*/; do git -C "$r" pull -q 2>/dev/null; done` (search always reads the current files; there is no index to rebuild). `local/` is not a git repo.
- Add another skill repo to the library: `git clone <url> ~/.claude/skill-repos/<name>`; it is searched automatically.
