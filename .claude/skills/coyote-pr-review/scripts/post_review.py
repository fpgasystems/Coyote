#!/usr/bin/env python3
"""Post an approved review draft to GitHub as ONE review (event COMMENT by default).

Usage: post_review.py <review-dir>/draft_review.json [--yes]
Without --yes it only prints what would be posted.

Draft format:
{"repo": "owner/name", "pr": 123, "commit_id": "<head sha>", "event": "COMMENT",
 "body": "summary text",
 "comments": [{"path": "hw/hdl/x.sv", "line": 42, "start_line": 40 (optional), "body": "..."}]}

Comments whose line is not inside a diff hunk (RIGHT side) cannot be inline;
they are posted as file-level comments, or folded into the review body if the
file is not part of the PR.
"""
import json
import re
import subprocess
import sys


def gh(args, payload=None):
    r = subprocess.run(["gh", *args], input=json.dumps(payload) if payload else None,
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"gh {' '.join(args)} failed:\n{r.stderr}")
    return json.loads(r.stdout) if r.stdout.strip() else None


def commentable_lines(repo, pr):
    files = gh(["api", f"repos/{repo}/pulls/{pr}/files", "--paginate"])
    lines = {}
    for f in files:
        ok = set()
        new = 0
        for row in (f.get("patch") or "").splitlines():
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", row)
            if m:
                new = int(m.group(1))
                continue
            if row.startswith(("-", "\\")):
                continue
            ok.add(new)
            new += 1
        lines[f["filename"]] = ok
    return lines


def main():
    draft = json.load(open(sys.argv[1]))
    post = "--yes" in sys.argv
    repo, pr, sha = draft["repo"], draft["pr"], draft["commit_id"]
    event = draft.get("event", "COMMENT")
    if event not in ("COMMENT", "REQUEST_CHANGES", "APPROVE"):
        sys.exit(f"bad event {event}")

    current = gh(["pr", "view", str(pr), "--repo", repo, "--json", "headRefOid"])["headRefOid"]
    if current != sha:
        sys.exit(f"PR head moved ({sha[:10]} -> {current[:10]}); re-run the review before posting.")

    valid = commentable_lines(repo, pr)
    inline, file_level, folded = [], [], []
    for c in draft["comments"]:
        path, line = c["path"], c.get("line")
        if path in valid and line in valid[path] and (c.get("start_line") is None or c["start_line"] in valid[path]):
            item = {"path": path, "line": line, "side": "RIGHT", "body": c["body"]}
            if c.get("start_line") and c["start_line"] < line:
                item.update(start_line=c["start_line"], start_side="RIGHT")
            inline.append(item)
        elif path in valid:
            file_level.append(c)
        else:
            folded.append(c)

    body = draft["body"]
    if folded:
        body += "\n\n" + "\n\n".join(f"**`{c['path']}`{':' + str(c['line']) if c.get('line') else ''}**: {c['body']}" for c in folded)

    print(f"Review on {repo}#{pr} @ {sha[:10]} event={event}")
    print(f"  inline comments: {len(inline)}, file-level: {len(file_level)}, folded into body: {len(folded)}")
    for c in inline:
        print(f"  - {c['path']}:{c['line']}")
    for c in file_level:
        print(f"  - {c['path']} (file-level; line {c.get('line')} not in diff)")
    if not post:
        print("\nDry run. Re-run with --yes to post.")
        return

    gh(["api", "-X", "POST", f"repos/{repo}/pulls/{pr}/reviews", "--input", "-"],
       {"commit_id": sha, "event": event, "body": body, "comments": inline})
    for c in file_level:
        gh(["api", "-X", "POST", f"repos/{repo}/pulls/{pr}/comments", "--input", "-"],
           {"commit_id": sha, "path": c["path"], "subject_type": "file", "body": c["body"]})
    print("Posted.")


if __name__ == "__main__":
    main()
