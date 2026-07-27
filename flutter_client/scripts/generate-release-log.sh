#!/usr/bin/env bash
# generate-release-log.sh
#
# Generates categorized release notes from git history for the m3u-tv app.
# Unlike `gh release create --generate-notes` (used previously in
# .github/workflows/release.yml), this lists ALL commits in range - not just
# merged PRs - grouped by conventional-commit type and sorted chronologically.
#
# Versioning here is tag-based (vX.Y.Z), matching PREV_TAG/HEAD_REF resolution
# already in .github/workflows/release.yml.
#
# Usage:
#   ./scripts/generate-release-log.sh                # preview: unreleased changes since latest tag
#   ./scripts/generate-release-log.sh v1.0.7          # reproduce: what shipped in v1.0.7
#   ./scripts/generate-release-log.sh v1.0.6 v1.0.7   # explicit range
#
# Run from anywhere inside the m3u-tv repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

latest_tag() {
    git tag --sort=-version:refname | grep -E "$TAG_RE" | head -1
}

prev_tag_of() {
    # Tag immediately older than $1 in version order.
    git tag --sort=-version:refname | grep -E "$TAG_RE" | grep -A1 -Fx "$1" | tail -1
}

# ---------- Resolve PREV_REF / HEAD_REF ----------

if [[ $# -eq 2 ]]; then
    PREV_REF="$1"
    HEAD_REF="$2"
elif [[ $# -eq 1 ]]; then
    HEAD_REF="$1"
    PREV_REF="$(prev_tag_of "$HEAD_REF")"
    if [[ -z "$PREV_REF" || "$PREV_REF" == "$HEAD_REF" ]]; then
        PREV_REF="$(git rev-list --max-parents=0 HEAD)"
    fi
elif [[ $# -eq 0 ]]; then
    HEAD_REF="HEAD"
    PREV_REF="$(latest_tag)"
    if [[ -z "$PREV_REF" ]]; then
        PREV_REF="$(git rev-list --max-parents=0 HEAD)"
    fi
else
    echo "Usage: $0 [from-tag] [to-tag]" >&2
    exit 1
fi

git rev-parse --verify "$PREV_REF" > /dev/null 2>&1 || { echo "Error: unknown ref '$PREV_REF'" >&2; exit 1; }
git rev-parse --verify "$HEAD_REF" > /dev/null 2>&1 || { echo "Error: unknown ref '$HEAD_REF'" >&2; exit 1; }

echo "Range : ${PREV_REF} -> ${HEAD_REF}" >&2
echo "" >&2

# ---------- Collect and categorize commits ----------

features="" fixes="" perf="" refactor="" docs="" chores="" tests="" reverts="" other=""

while IFS='|' read -r hash subject; do
    [[ -z "$subject" ]] && continue
    [[ "$subject" =~ ^[Vv]ersion\ bump ]] && continue

    type="$(echo "$subject" | grep -oE '^(feat|fix|perf|docs|chore|refactor|test|revert|ci|build|style)(\([^)]+\))?!?' | head -1 || true)"
    prefix="$(echo "$type" | grep -oE '^[a-z]+' || true)"

    if [[ -n "$prefix" ]]; then
        display="$(echo "$subject" | sed -E 's/^[a-z]+(\([^)]+\))?!?: *//')"
    else
        display="$subject"
    fi

    line="- ${display} (\`${hash}\`)"

    case "$prefix" in
        feat)            features+="${line}"$'\n' ;;
        fix)              fixes+="${line}"$'\n' ;;
        perf)             perf+="${line}"$'\n' ;;
        refactor)         refactor+="${line}"$'\n' ;;
        docs)             docs+="${line}"$'\n' ;;
        chore)            chores+="${line}"$'\n' ;;
        test)             tests+="${line}"$'\n' ;;
        revert)           reverts+="${line}"$'\n' ;;
        ci|build|style)   ;; # noise, skip
        *)                other+="${line}"$'\n' ;;
    esac
# --reverse => chronological (oldest first) within each category
done < <(git log --reverse --no-merges --pretty=tformat:"%h|%s" "${PREV_REF}..${HEAD_REF}")

# ---------- Output ----------

echo "## What's Changed"
echo ""

if [[ -n "$features" ]]; then echo "### Features";       echo -n "$features";  echo ""; fi
if [[ -n "$fixes"    ]]; then echo "### Bug Fixes";      echo -n "$fixes";     echo ""; fi
if [[ -n "$perf"     ]]; then echo "### Performance";    echo -n "$perf";      echo ""; fi
if [[ -n "$refactor" ]]; then echo "### Refactoring";    echo -n "$refactor";  echo ""; fi
if [[ -n "$reverts"  ]]; then echo "### Reverts";        echo -n "$reverts";   echo ""; fi
if [[ -n "$docs"     ]]; then echo "### Documentation";  echo -n "$docs";      echo ""; fi
if [[ -n "$tests"    ]]; then echo "### Tests";          echo -n "$tests";     echo ""; fi
if [[ -n "$chores"   ]]; then echo "### Maintenance";    echo -n "$chores";    echo ""; fi
if [[ -n "$other"    ]]; then echo "### Other Changes";  echo -n "$other";     echo ""; fi

if [[ -z "$features$fixes$perf$refactor$reverts$docs$tests$chores$other" ]]; then
    echo "_No changes found in range ${PREV_REF}..${HEAD_REF}_"
    echo ""
fi

# GitHub's --generate-notes appends this footer automatically; replicate it
# here since --notes-file bypasses that. Only emit it when both ends of the
# range are real tags (a compare link against a bare commit/HEAD isn't useful).
if [[ "$PREV_REF" =~ $TAG_RE && "$HEAD_REF" =~ $TAG_RE ]]; then
    REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
    SLUG="$(echo "$REMOTE_URL" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"
    if [[ -n "$SLUG" ]]; then
        echo "**Full Changelog**: https://github.com/${SLUG}/compare/${PREV_REF}...${HEAD_REF}"
    fi
fi
