#!/usr/bin/env bash
# Required check: every pull request must reference at least one GitHub issue via a closing/linking
# keyword, so a closed issue always traces back to the PR that delivered it (owner requirement
# 2026-10-04, Wadman-IT/Primodel#260 — #235 stayed open because the get-started PR that delivered it
# never referenced it).
#
# WHAT COUNTS. A line of the PR description — after stripping a leading "- "/"* " list marker and
# surrounding whitespace — that is EXACTLY:
#     <keyword> <ref>
# keyword:  Fixes | Closes | Resolves | Refs      (case-insensitive)
# ref:      #<n>   or   <owner>/<repo>#<n>
#
# Nothing else may share that line. A keyword mentioned in running prose ("this follows up #12") is not
# a reference line and does not count towards the requirement. A line carrying more than one reference —
# two keywords, a comma list, or "and" — is REJECTED rather than silently read as the first one, because
# GitHub only closes the issue directly after the keyword: a list closes the first and links nothing for
# the rest.
#
# Each accepted reference is verified to exist via `gh api repos/<owner>/<repo>/issues/<n>` and to be an
# issue, not a pull request (a PR has a `.pull_request` key on that same endpoint).
#
# Usage:
#   check-issue-reference.sh --self-test
#   check-issue-reference.sh                      # reads PR_BODY / PR_AUTHOR / config from the environment
#
# Env:
#   PR_BODY           the pull request description
#   PR_AUTHOR         the pull request author's login (exempt logins skip the check entirely)
#   OWN_REPO          owner/repo this check runs in, e.g. Wadman-IT/Primodel
#   ALLOW_BARE_HASH   "true" if a bare #n resolves to OWN_REPO; "false" if issues live elsewhere and a
#                     bare #n must be rejected with a hint to use the full owner/repo#n form
#   ISSUES_REPO       the owner/repo a bare #n should be written as instead, when ALLOW_BARE_HASH=false
#   BOT_AUTHORS_1 / BOT_AUTHORS_2   exempt author logins (defaults: github-actions[bot], dependabot[bot])
set -euo pipefail

BOT_AUTHORS=("${BOT_AUTHORS_1:-github-actions[bot]}" "${BOT_AUTHORS_2:-dependabot[bot]}")

REF_FULL='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)$'
REF_BARE='^#([0-9]+)$'
KEYWORD_LINE='^(fixes|closes|resolves|refs)[[:space:]]+(.+)$'

# Strips a leading "- "/"* " list marker, a trailing \r, and surrounding whitespace.
strip_marker() {
  printf '%s' "$1" | sed -E 's/\r$//; s/^[[:space:]]*[-*][[:space:]]+//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

# repos/<owner>/<repo>/issues/<n> exists and is NOT a pull request. Overridden wholesale by the self-test.
issue_exists() {
  local owner_repo="$1" number="$2" json
  json="$(gh api "repos/${owner_repo}/issues/${number}" 2>/dev/null)" || return 1
  ! printf '%s' "$json" | jq -e 'has("pull_request")' >/dev/null 2>&1
}

is_bot_author() {
  local login="$1" bot
  for bot in "${BOT_AUTHORS[@]}"; do
    [ "$login" = "$bot" ] && return 0
  done
  return 1
}

# Validates $1 (the PR body) against own-repo $2 / bare-hash policy $3 / issues-repo hint $4.
# Prints ::error:: diagnostics on stderr and returns 1 on any problem; prints the accepted references
# and returns 0 otherwise.
validate() {
  local body="$1" own_repo="$2" allow_bare="$3" issues_repo="$4"
  local -a refs=()
  local fail=0 line stripped rest lower_stripped

  while IFS= read -r line || [ -n "$line" ]; do
    stripped="$(strip_marker "$line")"
    [ -z "$stripped" ] && continue
    lower_stripped="$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$lower_stripped" =~ $KEYWORD_LINE ]]; then
      continue   # no keyword at the start of the line: prose, not a reference line
    fi
    rest="${stripped#* }"
    rest="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//')"
    if [[ "$rest" =~ $REF_FULL ]]; then
      refs+=("${BASH_REMATCH[1]} ${BASH_REMATCH[2]}")
    elif [[ "$rest" =~ $REF_BARE ]]; then
      if [ "$allow_bare" = "true" ]; then
        refs+=("${own_repo} ${BASH_REMATCH[1]}")
      else
        echo "::error::\"${stripped}\" uses a bare #${BASH_REMATCH[1]}, but issues for this repository live in ${issues_repo}. Write ${issues_repo}#${BASH_REMATCH[1]}." >&2
        fail=1
      fi
    else
      echo "::error::\"${stripped}\" is not a single issue reference. Put each issue reference on its own line (e.g. 'Fixes #1' newline 'Fixes #2'). GitHub only closes the issue directly after a keyword." >&2
      fail=1
    fi
  done <<< "$body"

  if [ "$fail" -ne 0 ]; then
    return 1
  fi

  if [ "${#refs[@]}" -eq 0 ]; then
    echo "::error::No issue reference found. Add a line such as 'Fixes #123' or 'Refs ${issues_repo}#123' (one keyword, one issue, on its own line)." >&2
    return 1
  fi

  local ref owner_repo number
  for ref in "${refs[@]}"; do
    owner_repo="${ref% *}"
    number="${ref##* }"
    if ! issue_exists "$owner_repo" "$number"; then
      echo "::error::${owner_repo}#${number} does not exist, or is a pull request rather than an issue." >&2
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] || return 1

  for ref in "${refs[@]}"; do
    owner_repo="${ref% *}"
    number="${ref##* }"
    echo "Referenced: ${owner_repo}#${number}"
  done
  return 0
}

self_test() {
  local failures=0

  # Stub the network call: 404 = no such issue, 600 = exists but is a pull request. Everything else
  # "exists" as an issue.
  issue_exists() {
    local number="$2"
    case "$number" in
      404) return 1 ;;
      600) return 1 ;;
      *) return 0 ;;
    esac
  }

  check() {
    local want="$1" label="$2" body="$3" author="${4:-SomeDev}" own_repo="${5:-Wadman-IT/Primodel}" \
          allow_bare="${6:-true}" issues_repo="${7:-Wadman-IT/Primodel}" got
    if is_bot_author "$author"; then
      got=pass
    elif validate "$body" "$own_repo" "$allow_bare" "$issues_repo" >/dev/null 2>&1; then
      got=pass
    else
      got=fail
    fi
    if [ "$got" != "$want" ]; then
      echo "  SELF-TEST FAILED: expected $want, got $got — $label"
      failures=$((failures + 1))
    else
      echo "  ok ($got): $label"
    fi
  }

  echo "Accepted:"
  check pass "single Fixes line"                 $'Fixes #1'
  check pass "one reference per line (two lines)" $'Some context.\n\nFixes #1\nRefs #2\n'
  check pass "cross-repo full form, different repo" $'Refs Wadman-IT/Primodel-SDK#3'
  check pass "bot author skips the body entirely"  '' "dependabot[bot]"
  check pass "bare hash allowed in own repo"       $'Closes #7'
  check pass "bare hash disallowed, full form used" $'Fixes Wadman-IT/Primodel#7' SomeDev \
        Wadman-IT/Primodel-SDK false Wadman-IT/Primodel
  check pass "list marker stripped before matching" $'- Fixes #1'

  echo "Rejected:"
  check fail "two keywords on one line"          $'Fixes #1, Fixes #2'
  check fail "keyword then an 'and' list"        $'Fixes #1 and #2'
  check fail "keyword then a comma list"         $'Fixes #1, #2'
  check fail "reference only in running prose, no keyword line" \
        $'This follows up on #12 and will land separately.'
  check fail "bare hash rejected outside own repo" $'Fixes #7' SomeDev \
        Wadman-IT/Primodel-SDK false Wadman-IT/Primodel
  check fail "nonexistent issue"                 $'Fixes #404'
  check fail "reference resolves to a pull request" $'Fixes #600'
  check fail "no reference at all"               $'Just a description, nothing else.'

  if [ "$failures" -ne 0 ]; then
    echo "::error::$failures self-test case(s) failed. The issue-reference check does not behave as documented, so its verdict on a real PR means nothing."
    return 1
  fi
  echo "Self-test passed: every accepted form accepted, every rejected form rejected."
}

main() {
  local author="${PR_AUTHOR:-}"
  if is_bot_author "$author"; then
    echo "Opened by ${author}: issue reference not required."
    return 0
  fi
  validate "${PR_BODY:-}" "${OWN_REPO:?OWN_REPO is required}" "${ALLOW_BARE_HASH:-true}" "${ISSUES_REPO:-${OWN_REPO:-}}"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

main
