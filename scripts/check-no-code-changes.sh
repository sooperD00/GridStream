#!/usr/bin/env bash
# check-no-code-changes.sh — verify pending changes touch only comments/docs.
#
# Run before deploy when you believe a change is docs-only and want to skip
# re-test. Compares the working tree against a ref (default: main) and reports
# per-file whether each change is comments/docstrings/metadata only or whether
# it includes executable code.
#
# Exit 0: no executable code changed (safe to skip re-test).
# Exit 1: code changes detected (re-test required).
# Exit 2: usage or environment error.
#
# To allowlist a specific value-change as metadata-only, add it to ALLOWLIST
# below in the form "path/to/file:dotted.key.path". Currently allowlisted:
# Chart.yaml's `home:` field (Helm metadata, never affects rendered manifests).

set -euo pipefail

# ---------- defaults ----------
REF="main"
VERBOSE=0

# ---------- allowlist ----------
# Format: "path/to/file:dotted.key.path"
# A change to one of these keys is treated as metadata, not code.
ALLOWLIST=(
  "charts/standard-service/Chart.yaml:home"
)

# ---------- arg parsing ----------
usage() {
  cat <<EOF
Usage: $0 [--ref REF] [--verbose] [--help]

Verify pending changes (working tree vs REF) touch only comments, docstrings,
and allowlisted metadata fields. If clean, deploy can skip re-test.

Options:
  --ref REF      Git ref to compare against (default: main)
  --verbose, -v  Print diffs for files that fail the check
  --help, -h     This message

Exit codes:
  0  Docs/comments only — safe to skip re-test.
  1  Executable code changed — re-test required.
  2  Usage or environment error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------- environment checks ----------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not a git repository" >&2
  exit 2
fi
if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
  echo "error: ref '$REF' does not exist" >&2
  exit 2
fi

# Run from repo root so paths from `git diff` resolve correctly.
cd "$(git rev-parse --show-toplevel)"

# Color output only when stdout is a TTY (CI logs stay clean).
if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  GREEN=''; RED=''; DIM=''; RESET=''
fi

# ---------- python helpers ----------
# Heredoc-style scripts kept inline (single consumer; no extraction yet).

# Strip docstrings; comments are absent from AST so dropped for free.
PY_STRIP_DOCSTRINGS='
import ast, sys
try:
    tree = ast.parse(sys.stdin.read())
except SyntaxError as e:
    sys.stderr.write(f"parse error: {e}\n")
    sys.exit(3)
for node in ast.walk(tree):
    if hasattr(node, "body") and node.body:
        first = node.body[0]
        if (isinstance(first, ast.Expr)
            and isinstance(first.value, ast.Constant)
            and isinstance(first.value.value, str)):
            node.body = node.body[1:] or [ast.Pass()]
print(ast.unparse(tree))
'

# Parse YAML/JSON/TOML, mask allowlisted keys, emit canonical JSON.
PY_CANONICALIZE='
import sys, json

fmt = sys.argv[1]
allowlist = sys.argv[2:]
data_str = sys.stdin.read()

if not data_str.strip():
    print("")
    sys.exit(0)

if fmt == "yaml":
    import yaml
    data = yaml.safe_load(data_str)
elif fmt == "json":
    data = json.loads(data_str)
elif fmt == "toml":
    import tomllib
    data = tomllib.loads(data_str)
else:
    sys.stderr.write(f"unknown format: {fmt}\n")
    sys.exit(3)

def mask(obj, parts):
    if not parts or obj is None:
        return
    head, *rest = parts
    if isinstance(obj, dict) and head in obj:
        if rest:
            mask(obj[head], rest)
        else:
            obj[head] = "<ALLOWLISTED>"

for keypath in allowlist:
    mask(data, keypath.split("."))

print(json.dumps(data, sort_keys=True, indent=2, default=str))
'

# ---------- output helpers ----------
status_pass() { printf "  ${GREEN}✓${RESET} %-18s %s\n" "$1" "$2"; }
status_fail() { printf "  ${RED}✗${RESET} %-18s %s\n" "$1" "$2"; }

# ---------- file content helpers ----------
content_at_ref() {
  git show "$REF:$1" 2>/dev/null || true
}

strip_hash_comments() {
  # Conservative: strips full-line `#` comments and blank lines. Inline
  # comments not handled (rare in our shell/Makefile/Dockerfile, and if
  # present would conservatively flag — that's the right tradeoff).
  grep -Ev '^[[:space:]]*(#|$)' || true
}

allowlist_keys_for() {
  local path="$1"
  for entry in "${ALLOWLIST[@]}"; do
    if [[ "${entry%%:*}" == "$path" ]]; then
      echo "${entry#*:}"
    fi
  done
}

# ---------- per-file checks ----------
# Each sets LAST_DIFF and returns 0 (clean) / nonzero (changed).
LAST_DIFF=""

check_python() {
  local f="$1" before after
  before=$(content_at_ref "$f" | python3 -c "$PY_STRIP_DOCSTRINGS" 2>&1) || true
  after=$(python3 -c "$PY_STRIP_DOCSTRINGS" < "$f" 2>&1) || true
  LAST_DIFF=$(diff <(echo "$before") <(echo "$after") || true)
  [[ -z "$LAST_DIFF" ]]
}

check_structured() {
  local f="$1" fmt="$2" before after
  local keys=()
  while IFS= read -r k; do [[ -n "$k" ]] && keys+=("$k"); done < <(allowlist_keys_for "$f")

  before=$(content_at_ref "$f" | python3 -c "$PY_CANONICALIZE" "$fmt" "${keys[@]+"${keys[@]}"}" 2>&1) || true
  after=$(python3 -c "$PY_CANONICALIZE" "$fmt" "${keys[@]+"${keys[@]}"}" < "$f" 2>&1) || true
  LAST_DIFF=$(diff <(echo "$before") <(echo "$after") || true)
  [[ -z "$LAST_DIFF" ]]
}

check_hash_comments() {
  local f="$1" before after
  before=$(content_at_ref "$f" | strip_hash_comments)
  after=$(strip_hash_comments < "$f")
  LAST_DIFF=$(diff <(echo "$before") <(echo "$after") || true)
  [[ -z "$LAST_DIFF" ]]
}

# ---------- dispatch ----------
categorize() {
  case "$1" in
    *.md)                                       echo "docs" ;;
    *.py)                                       echo "python" ;;
    *.yaml|*.yml)                               echo "yaml" ;;
    *.json)                                     echo "json" ;;
    *.toml)                                     echo "toml" ;;
    *.sh)                                       echo "shell" ;;
    Makefile|*/Makefile)                        echo "make" ;;
    Dockerfile|Dockerfile.*|*/Dockerfile|*/Dockerfile.*) echo "docker" ;;
    .gitignore|*/.gitignore)                    echo "shell" ;;
    LICENSE|*/LICENSE)                          echo "docs" ;;
    *)                                          echo "unknown" ;;
  esac
}

# ---------- main ----------
main() {
  echo "Checking pending changes against ${REF}..."
  echo

  local changed_files
  changed_files=$(git diff --name-status "$REF" -- 2>/dev/null || true)
  if [[ -z "$changed_files" ]]; then
    echo "No changes vs ${REF}. Nothing to check."
    exit 0
  fi

  # Lazy dependency check: only require modules we'll actually use.
  local needs_yaml=0 needs_toml=0
  while IFS=$'\t' read -r _ path _; do
    case "$path" in
      *.yaml|*.yml) needs_yaml=1 ;;
      *.toml)       needs_toml=1 ;;
    esac
  done <<< "$changed_files"

  if [[ "$needs_yaml" -eq 1 ]] && ! python3 -c 'import yaml' 2>/dev/null; then
    echo "error: PyYAML required for YAML checks but not installed" >&2
    echo "  pip install pyyaml  (or: uv pip install pyyaml)" >&2
    exit 2
  fi
  if [[ "$needs_toml" -eq 1 ]] && ! python3 -c 'import tomllib' 2>/dev/null; then
    echo "error: tomllib required for TOML checks (Python 3.11+ needed)" >&2
    exit 2
  fi

  local fail_count=0
  local fail_files=() fail_diffs=()

  while IFS=$'\t' read -r status path rest; do
    [[ -z "${status:-}" ]] && continue

    # Structural changes (add/delete/rename/typechange/copy) need manual
    # review for anything that isn't pure docs.
    case "$status" in
      A|D|R*|T*|C*)
        if [[ "$path" == *.md ]]; then
          status_pass "docs ($status)" "$path"
          continue
        fi
        status_fail "structural" "$path ($status)"
        fail_count=$((fail_count+1))
        fail_files+=("$path")
        fail_diffs+=("(file $status: structural change, not a content diff — manual review)")
        continue
        ;;
    esac

    local category note=""
    category=$(categorize "$path")
    case "$category" in
      docs)
        status_pass "docs-only" "$path"
        ;;
      python)
        if check_python "$path"; then
          status_pass "comments" "$path"
        else
          status_fail "CODE" "$path"
          fail_count=$((fail_count+1))
          fail_files+=("$path"); fail_diffs+=("$LAST_DIFF")
        fi
        ;;
      yaml|json|toml)
        if check_structured "$path" "$category"; then
          note="$category"
          # Note when the allowlist applied (informational).
          while IFS= read -r k; do
            [[ -n "$k" ]] && note="$category (allowlisted: $k)"
          done < <(allowlist_keys_for "$path")
          status_pass "$note" "$path"
        else
          status_fail "CODE" "$path"
          fail_count=$((fail_count+1))
          fail_files+=("$path"); fail_diffs+=("$LAST_DIFF")
        fi
        ;;
      shell|make|docker)
        if check_hash_comments "$path"; then
          status_pass "comments" "$path"
        else
          status_fail "CODE" "$path"
          fail_count=$((fail_count+1))
          fail_files+=("$path"); fail_diffs+=("$LAST_DIFF")
        fi
        ;;
      unknown)
        status_fail "unknown type" "$path"
        fail_count=$((fail_count+1))
        fail_files+=("$path")
        fail_diffs+=("(unknown file extension — failing closed; add to categorize() in $0 if appropriate)")
        ;;
    esac
  done <<< "$changed_files"

  echo
  if [[ "$fail_count" -eq 0 ]]; then
    echo "${GREEN}✓ no executable changes detected — safe to skip re-test${RESET}"
    exit 0
  fi

  echo "${RED}✗ ${fail_count} file(s) have executable changes:${RESET}"
  for f in "${fail_files[@]}"; do echo "    $f"; done

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo
    echo "${DIM}--- diffs ---${RESET}"
    local i=0
    for f in "${fail_files[@]}"; do
      echo
      echo "=== $f ==="
      echo "${fail_diffs[$i]}"
      i=$((i+1))
    done
  else
    echo
    echo "${DIM}Run with --verbose to see diffs.${RESET}"
  fi
  exit 1
}

main "$@"
