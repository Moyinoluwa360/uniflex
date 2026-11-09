#!/usr/bin/env python3
"""UI Polish diff review.

Prints every REMOVED line (in lib/**.dart, from `git diff <base>`) that looks
like logic: callbacks, state reads, awaits, conditions, route/navigation,
string literals. For each one it says whether the same text (whitespace
squeezed) still appears among the ADDED lines of the same file, i.e. whether
the logic was moved/re-wrapped rather than dropped.

    python3 tool/diff_review.py            # working tree vs HEAD
    python3 tool/diff_review.py HEAD~1     # a commit vs its parent

Lines marked MISSING need a look (or a sentence in the report).
"""
import re
import subprocess
import sys

base = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
args = ["git", "diff", "-U0", base] if base == "HEAD" else ["git", "diff", "-U0", base, base.replace("~1", "")]
if base.endswith("~1"):
    args = ["git", "diff", "-U0", base, base[:-2]]
diff = subprocess.run(args, capture_output=True, text=True).stdout

LOGIC = re.compile(
    r"onPressed|onTap|onChanged|onSubmitted|onRefresh|ref\.(read|watch|listen|invalidate)|"
    r"\bawait\b|\bif \(|\? .* : |Navigator|MaterialPageRoute|=> |'[^']{3,}'|\"[^\"]{3,}\""
)
COMMENT = re.compile(r"^\s*(//|\*|/\*)")


def squeeze(s):
    return re.sub(r"\s+", "", s)


file = None
removed, added = {}, {}
for line in diff.splitlines():
    if line.startswith("+++ b/"):
        file = line[6:]
    elif line.startswith("--- "):
        continue
    elif file and file.endswith(".dart") and file.startswith("lib/"):
        if line.startswith("-") and not line.startswith("---"):
            removed.setdefault(file, []).append(line[1:])
        elif line.startswith("+") and not line.startswith("+++"):
            added.setdefault(file, []).append(line[1:])

total = missing = 0
for f, lines in sorted(removed.items()):
    add_blob = squeeze("\n".join(added.get(f, [])))
    out = []
    for l in lines:
        if COMMENT.match(l) or not l.strip() or not LOGIC.search(l):
            continue
        total += 1
        kept = squeeze(l) in add_blob
        if not kept:
            missing += 1
        out.append(("  kept    " if kept else "  MISSING ") + l.strip()[:150])
    if out:
        print(f"\n== {f}")
        print("\n".join(out))
print(f"\n{total} logic-looking removed lines, {missing} not found verbatim among added lines.")
