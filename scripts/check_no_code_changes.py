#!/usr/bin/env python3
"""check_no_code_changes.py — verify pending changes touch only comments/docs.

Run before deploy when you believe a change is docs-only and want to skip
re-test. Compares the working tree against a ref (default: main) and reports
per-file whether each change is comments/docstrings/metadata only or whether
it includes executable code.

Exit 0: no executable code changed (safe to skip re-test).
Exit 1: code changes detected (re-test required).
Exit 2: usage or environment error.

To allowlist a specific value-change as metadata-only, add it to ALLOWLIST
below in the form "path/to/file:dotted.key.path". Currently allowlisted:
Chart.yaml's `home:` field (Helm metadata, never affects rendered manifests).

This script replaces an earlier bash version (scripts/check-no-code-changes.sh)
that was unusable on Windows due to subprocess overhead and shebang/PATH
quirks. Single Python process, ~10x faster, no platform-specific shimming.
"""

from __future__ import annotations

import argparse
import ast
import difflib
import io
import json
import os
import subprocess
import sys
from pathlib import PurePosixPath

# ---------- allowlist ----------
# Format: "path/to/file:dotted.key.path"
# A change to one of these keys is treated as metadata, not code.
ALLOWLIST: list[str] = [
    "charts/standard-service/Chart.yaml:home",
]


# ---------- output ----------
def _colors() -> tuple[str, str, str, str]:
    if sys.stdout.isatty():
        return "\033[32m", "\033[31m", "\033[2m", "\033[0m"
    return "", "", "", ""


GREEN, RED, DIM, RESET = _colors()


def status_pass(label: str, path: str) -> None:
    print(f"  {GREEN}\u2713{RESET} {label:<18} {path}")


def status_fail(label: str, path: str) -> None:
    print(f"  {RED}\u2717{RESET} {label:<18} {path}")


# ---------- git helpers ----------
def run_git(*args: str) -> str:
    """Run git with args; return stdout. Raises on nonzero exit.

    encoding/errors pinned: git emits raw UTF-8 bytes regardless of host
    OS. Without encoding="utf-8", subprocess on Windows decodes as cp1252,
    which mojibakes anything outside ASCII (em-dashes, accented chars) or
    crashes the reader thread on bytes that have no cp1252 mapping.
    errors="replace" keeps us tolerant of genuinely-binary checked-in
    content rather than crashing — a binary file would correctly flag as
    a code change rather than silently passing.
    """
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=True,
        encoding="utf-8",
        errors="replace",
    ).stdout


def git_show(ref: str, path: str) -> str:
    """Return file content at ref. Empty string if file doesn't exist there."""
    try:
        return subprocess.run(
            ["git", "show", f"{ref}:{path}"],
            capture_output=True,
            text=True,
            check=True,
            encoding="utf-8",
            errors="replace",
        ).stdout
    except subprocess.CalledProcessError:
        return ""


def git_in_repo() -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            capture_output=True,
            check=True,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def git_ref_exists(ref: str) -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--verify", ref],
            capture_output=True,
            check=True,
        )
        return True
    except subprocess.CalledProcessError:
        return False


# ---------- analyzers ----------
def strip_docstrings(source: str) -> str:
    """Parse Python; return source with docstrings removed.

    Comments are absent from the AST so they're dropped for free. On
    SyntaxError, returns a marker — comparing two markers for the same
    error is still meaningful.
    """
    if not source.strip():
        return ""
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        return f"<PARSE_ERROR: {e}>"
    # Only these four node types can carry a docstring as the first body
    # element. ast.walk would otherwise visit Call/Lambda/comprehension
    # nodes whose `.body` attributes are expressions, not statement lists.
    docstring_parents = (
        ast.Module,
        ast.ClassDef,
        ast.FunctionDef,
        ast.AsyncFunctionDef,
    )
    for node in ast.walk(tree):
        if isinstance(node, docstring_parents) and node.body:
            first = node.body[0]
            if (
                isinstance(first, ast.Expr)
                and isinstance(first.value, ast.Constant)
                and isinstance(first.value.value, str)
            ):
                node.body = node.body[1:] or [ast.Pass()]
    return ast.unparse(tree)


def canonicalize_structured(
    fmt: str,
    source: str,
    allowlisted_keys: list[str],
) -> str:
    """Parse YAML/JSON/TOML; mask allowlisted keys; return canonical JSON."""
    if not source.strip():
        return ""
    if fmt == "yaml":
        import yaml

        data = yaml.safe_load(source)
    elif fmt == "json":
        data = json.loads(source)
    elif fmt == "toml":
        import tomllib

        data = tomllib.loads(source)
    else:
        raise ValueError(f"unknown format: {fmt}")

    def mask(obj: object, parts: list[str]) -> None:
        if not parts or obj is None:
            return
        head, *rest = parts
        if isinstance(obj, dict) and head in obj:
            if rest:
                mask(obj[head], rest)
            else:
                obj[head] = "<ALLOWLISTED>"

    for keypath in allowlisted_keys:
        mask(data, keypath.split("."))

    # Stringify all dict keys before dumping. Required because YAML 1.1
    # boolean coercion ('on:' → True, 'no:' → False) leaves dicts with
    # mixed-type keys, which json.dumps(sort_keys=True) cannot sort.
    # GitHub Actions workflow files are the canonical case (`on:` for
    # triggers).
    def stringify_keys(obj: object) -> object:
        if isinstance(obj, dict):
            return {str(k): stringify_keys(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [stringify_keys(x) for x in obj]
        return obj

    return json.dumps(stringify_keys(data), sort_keys=True, indent=2, default=str)


def strip_hash_comments(source: str) -> str:
    """Strip full-line `#` comments and blank lines.

    Conservative: inline comments not handled. If they're present and
    differ across versions, the file conservatively flags as code — which
    is the right tradeoff for shell/Makefile/Dockerfile.
    """
    return "\n".join(
        line for line in source.splitlines() if line.strip() and not line.lstrip().startswith("#")
    )


def diff_text(before: str, after: str, path: str) -> str:
    """Return unified diff; empty string if identical."""
    if before == after:
        return ""
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=f"{path} (before)",
            tofile=f"{path} (after)",
        )
    )


# ---------- dispatch ----------
def categorize(path: str) -> str:
    """Map a path to a check category."""
    p = PurePosixPath(path)
    suffix, name = p.suffix, p.name
    if suffix == ".md":
        return "docs"
    if suffix == ".py":
        return "python"
    if suffix in (".yaml", ".yml"):
        return "yaml"
    if suffix == ".json":
        return "json"
    if suffix == ".toml":
        return "toml"
    if suffix == ".sh":
        return "shell"
    if name == "Makefile":
        return "make"
    if name == "Dockerfile" or name.startswith("Dockerfile."):
        return "docker"
    if name == ".gitignore":
        return "shell"
    if name == "LICENSE":
        return "docs"
    if name == "CODEOWNERS":
        return "shell"  # # comments, like Makefile/Dockerfile
    if name == "uv.lock":
        return "toml"  # any lockfile change is a real dep change
    return "unknown"


def allowlist_keys_for(path: str) -> list[str]:
    keys = []
    for entry in ALLOWLIST:
        file_part, _, key_part = entry.partition(":")
        if file_part == path and key_part:
            keys.append(key_part)
    return keys


# ---------- per-file check ----------
def check_file(ref: str, status: str, path: str) -> tuple[bool, str, str]:
    """Check one file. Returns (clean, label, diff_or_note)."""
    # Structural changes need manual review for non-docs.
    if status[0] in ("A", "D", "R", "T", "C"):
        if path.endswith(".md"):
            return True, f"docs ({status})", ""
        return (
            False,
            "structural",
            f"(file {status}: structural change, not a content diff " f"\u2014 manual review)",
        )

    category = categorize(path)
    before = git_show(ref, path)
    try:
        with open(path, encoding="utf-8") as f:
            after = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return False, "read error", str(e)

    if category == "docs":
        return True, "docs-only", ""

    if category == "python":
        b = strip_docstrings(before)
        a = strip_docstrings(after)
        if a == b:
            return True, "comments", ""
        return False, "CODE", diff_text(b, a, path)

    if category in ("yaml", "json", "toml"):
        keys = allowlist_keys_for(path)
        try:
            b = canonicalize_structured(category, before, keys)
            a = canonicalize_structured(category, after, keys)
        except Exception as e:
            return False, "parse error", str(e)
        if a == b:
            label = category
            if keys:
                label = f"{category} (allowlisted: {','.join(keys)})"
            return True, label, ""
        return False, "CODE", diff_text(b, a, path)

    if category in ("shell", "make", "docker"):
        b = strip_hash_comments(before)
        a = strip_hash_comments(after)
        if a == b:
            return True, "comments", ""
        return False, "CODE", diff_text(b, a, path)

    return (
        False,
        "unknown type",
        f"(unknown file extension \u2014 failing closed; add to "
        f"categorize() in {sys.argv[0]} if appropriate)",
    )


# ---------- main ----------
def main() -> int:
    # Force UTF-8 for stdout/stderr. Default cp1252 on Windows cannot
    # encode the ✓/✗/— characters used in status lines, raising
    # UnicodeEncodeError on the first failure-path print. isinstance
    # narrowing (rather than `# type: ignore`) keeps the script honest
    # about edge cases: if someone redirects stdout to a StringIO in a
    # test harness, the reconfigure silently skips rather than crashing.
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding="utf-8")
    if isinstance(sys.stderr, io.TextIOWrapper):
        sys.stderr.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(
        description=(
            "Verify pending changes (working tree vs REF) touch only "
            "comments, docstrings, and allowlisted metadata fields. If "
            "clean, deploy can skip re-test."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Exit codes:\n"
            "  0  Docs/comments only \u2014 safe to skip re-test.\n"
            "  1  Executable code changed \u2014 re-test required.\n"
            "  2  Usage or environment error."
        ),
    )
    parser.add_argument(
        "--ref",
        default="main",
        help="Git ref to compare against (default: main)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Print diffs for files that fail the check",
    )
    args = parser.parse_args()

    if not git_in_repo():
        print("error: not a git repository", file=sys.stderr)
        return 2
    if not git_ref_exists(args.ref):
        print(f"error: ref '{args.ref}' does not exist", file=sys.stderr)
        return 2

    # Run from repo root so paths from `git diff` resolve correctly.
    os.chdir(run_git("rev-parse", "--show-toplevel").strip())

    print(f"Checking pending changes against {args.ref}...")
    print()

    diff_output = run_git("diff", "--name-status", args.ref, "--")
    if not diff_output.strip():
        print(f"No changes vs {args.ref}. Nothing to check.")
        return 0

    # Lazy dependency check.
    needs_yaml = needs_toml = False
    for line in diff_output.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        path = parts[2] if parts[0][0] in ("R", "C") and len(parts) >= 3 else parts[1]
        if path.endswith((".yaml", ".yml")):
            needs_yaml = True
        elif path.endswith(".toml"):
            needs_toml = True

    if needs_yaml:
        try:
            import yaml  # noqa: F401
        except ImportError:
            print(
                "error: PyYAML required for YAML checks but not installed",
                file=sys.stderr,
            )
            print(
                "  uv sync  (PyYAML is declared in pyproject.toml dev deps)",
                file=sys.stderr,
            )
            return 2
    if needs_toml:
        try:
            import tomllib  # noqa: F401
        except ImportError:
            print(
                "error: tomllib required (Python 3.11+ needed)",
                file=sys.stderr,
            )
            return 2

    fail_count = 0
    fails: list[tuple[str, str]] = []

    for line in diff_output.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status = parts[0]
        # For R/C, parts[2] is the new path; use it for file content.
        path = parts[2] if status[0] in ("R", "C") and len(parts) >= 3 else parts[1]

        clean, label, diff = check_file(args.ref, status, path)
        if clean:
            status_pass(label, path)
        else:
            status_fail(label, path)
            fail_count += 1
            fails.append((path, diff))

    print()
    if fail_count == 0:
        print(f"{GREEN}\u2713 no executable changes detected \u2014 safe to skip re-test{RESET}")
        return 0

    print(f"{RED}\u2717 {fail_count} file(s) have executable changes:{RESET}")
    for path, _ in fails:
        print(f"    {path}")

    if args.verbose:
        print()
        print(f"{DIM}--- diffs ---{RESET}")
        for path, diff in fails:
            print()
            print(f"=== {path} ===")
            print(diff)
    else:
        print()
        print(f"{DIM}Run with --verbose to see diffs.{RESET}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
