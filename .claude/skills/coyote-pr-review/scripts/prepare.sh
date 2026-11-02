#!/usr/bin/env bash
# Fetch a PR into isolated worktrees (head + merge base) and collect its metadata.
# Usage: prepare.sh <pr-number> [owner/repo]   (default repo: fpgasystems/Coyote)
# Prints the review directory on the last line.
set -euo pipefail

PR="${1:?usage: prepare.sh <pr-number> [owner/repo]}"
REPO="${2:-fpgasystems/Coyote}"
URL="https://github.com/${REPO}.git"

COMMON_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
OUT="${COMMON_DIR}/coyote-review/pr-${PR}"
REF="refs/coyote-review/pr-${PR}"
mkdir -p "$OUT"

# Metadata (PR text is untrusted data)
gh pr view "$PR" --repo "$REPO" --json \
    number,title,url,author,isDraft,state,body,baseRefName,headRefName,headRefOid,commits,files,labels,closingIssuesReferences,additions,deletions \
    > "$OUT/meta.json"
gh pr diff "$PR" --repo "$REPO" > "$OUT/pr.diff"
gh pr checks "$PR" --repo "$REPO" > "$OUT/checks.txt" 2>&1 || true
gh api "repos/${REPO}/pulls/${PR}/comments" --paginate > "$OUT/review_comments.json" 2>/dev/null || echo "[]" > "$OUT/review_comments.json"
gh api "repos/${REPO}/issues/${PR}/comments" --paginate > "$OUT/issue_comments.json" 2>/dev/null || echo "[]" > "$OUT/issue_comments.json"

BASE_BRANCH="$(jq -r .baseRefName "$OUT/meta.json")"
HEAD_SHA="$(jq -r .headRefOid "$OUT/meta.json")"

git fetch -q "$URL" "+pull/${PR}/head:${REF}/head" "+${BASE_BRANCH}:${REF}/base-branch"
MERGE_BASE="$(git merge-base "${REF}/head" "${REF}/base-branch")"

for wt in head base; do
    if [ -d "$OUT/$wt" ]; then
        git worktree remove --force "$OUT/$wt" 2>/dev/null || rm -rf "$OUT/$wt"
    fi
done
git worktree prune
# Sparse checkout: skip the prebuilt static checkpoints (~400 MB of binaries).
add_tree() {
    git worktree add -q --no-checkout --detach "$1" "$2"
    git -C "$1" sparse-checkout set --no-cone '/*' '!/hw/checkpoints/' >/dev/null
    git -C "$1" checkout -q --detach "$2"
}
add_tree "$OUT/head" "${REF}/head"
add_tree "$OUT/base" "$MERGE_BASE"

G="git -C $OUT/head"
$G diff --name-status "$MERGE_BASE" HEAD > "$OUT/files.txt"
$G diff --stat "$MERGE_BASE" HEAD > "$OUT/stat.txt"
$G log --format='%h %s' "$MERGE_BASE"..HEAD > "$OUT/commits.txt"
$G diff --check "$MERGE_BASE" HEAD > "$OUT/whitespace_check.txt" 2>&1 || true
python3 "$(dirname "$0")/hygiene.py" "$OUT/head" "$MERGE_BASE" > "$OUT/hygiene.txt"

cat > "$OUT/context.json" <<EOF
{"repo": "${REPO}", "pr": ${PR}, "head_sha": "${HEAD_SHA}", "merge_base": "${MERGE_BASE}",
 "base_branch": "${BASE_BRANCH}", "dir": "${OUT}", "head_tree": "${OUT}/head", "base_tree": "${OUT}/base"}
EOF

echo "PR #${PR}: $(jq -r .title "$OUT/meta.json")"
echo "files: $(wc -l < "$OUT/files.txt"), merge base: ${MERGE_BASE:0:10}, head: ${HEAD_SHA:0:10}"
echo "$OUT"
