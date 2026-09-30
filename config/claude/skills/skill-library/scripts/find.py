#!/usr/bin/env python3
"""Search the lazy skill library (~/.claude/skill-repos) for skills, agents and commands.

Usage: find.py <keyword> [keyword ...]   -> top matches with path
       find.py --list [skill|agent|command] -> every entry (name + short description)
"""
import os, re, sys

ROOT = os.path.expanduser("~/.claude/skill-repos")
SKIP = {".git", "node_modules", ".cursor", "scaffolds", "legacy-command-shims", "docs", "examples", "tests", "test"}


def frontmatter(path):
    try:
        text = open(path, encoding="utf-8", errors="ignore").read(6000)
    except OSError:
        return {}
    m = re.match(r"---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    meta, key = {}, None
    for line in m.group(1).splitlines():
        kv = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if kv:
            key, val = kv.group(1), kv.group(2).strip()
            meta[key] = "" if val in (">", "|", ">-", "|-") else val.strip("'\"")
        elif key and line.startswith((" ", "\t")):
            meta[key] = (meta[key] + " " + line.strip()).strip()
    return meta


def entries():
    for dirpath, dirs, files in os.walk(ROOT, followlinks=False):
        dirs[:] = [d for d in dirs if d not in SKIP and not d.startswith(".")]
        rel = os.path.relpath(dirpath, ROOT).split(os.sep)
        for f in files:
            p = os.path.join(dirpath, f)
            if f == "SKILL.md":
                kind, default = "skill", os.path.basename(dirpath)
            elif f.endswith(".md") and rel[-1] in ("agents", "commands") and len(rel) == 2:
                kind, default = rel[-1][:-1], f[:-3]
            else:
                continue
            meta = frontmatter(p)
            desc = meta.get("description", "")
            if kind == "skill" and not desc:
                continue
            yield kind, rel[0], meta.get("name") or default, desc, p


def main(argv):
    if not argv:
        print(__doc__); return
    # repos ship copies for other harnesses; keep the shortest path per (repo, kind, name)
    best = {}
    for e in entries():
        k = e[:3]
        if k not in best or len(e[4]) < len(best[k][4]):
            best[k] = e
    items = list(best.values())
    if argv[0] == "--list":
        want = argv[1] if len(argv) > 1 else None
        for kind, repo, name, desc, _ in sorted(items):
            if not want or kind == want:
                print(f"{kind:7} {repo}:{name} - {desc[:110]}")
        return
    words = [w.lower() for w in argv]
    scored = []
    for kind, repo, name, desc, p in items:
        n, d = name.lower(), desc.lower()
        s = sum(3 * (w in n) + (w in d) for w in words)
        if s:
            scored.append((-s, kind != "skill", name, kind, repo, desc, p))
    for _, _, name, kind, repo, desc, p in sorted(scored)[:12]:
        print(f"[{kind}] {repo}:{name}\n  {desc[:220]}\n  {p}")
    if not scored:
        print("No match. Try other English keywords, or --list.")


main(sys.argv[1:])
