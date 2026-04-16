"""Project scanning with 7-tier file selection.

Gathers project context (file tree, source code, diffs) for AI analysis.
Port of cli/lib/project-scanner.ps1.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EXCLUDE_DIRS = {
    "node_modules", ".git", "__pycache__", ".venv", "venv",
    "dist", "build", ".next", ".nuxt", "coverage", ".pytest_cache",
    ".code-conclave", ".review-council", ".claude", "vendor",
    "bin", "obj", ".vs", ".idea",
}

INCLUDE_EXTENSIONS = {
    ".ps1", ".py", ".js", ".ts", ".jsx", ".tsx", ".cs", ".java",
    ".go", ".rs", ".rb", ".php", ".swift", ".kt", ".scala",
    ".vue", ".svelte", ".html", ".css", ".scss", ".sql",
    ".yaml", ".yml", ".json", ".toml", ".md",
}

EXCLUDE_PATTERNS = {
    "*.min.js", "*.min.css", "*.map", "*.lock", "package-lock.json",
    "*.generated.*", "*.g.cs", "*.designer.cs",
}

TIER1_ALWAYS = {
    "main.py", "app.py", "server.js", "server.ts",
    "nginx.conf", "dockerfile", "manage.py", "wsgi.py", "asgi.py",
    ".env.example", "requirements.txt", "package.json", "pyproject.toml",
    "setup.cfg", "makefile", "rakefile", "gemfile",
    "go.mod", "cargo.toml", "pom.xml", "build.gradle",
}

TIER1_BYPASS_NAMES = {
    "dockerfile", "makefile", "rakefile", "gemfile", "vagrantfile",
    "nginx.conf", "requirements.txt", ".env.example", ".gitignore",
    "procfile", "brewfile",
}

TIER2_DIRS = {
    "services", "core", "lib", "utils", "middleware", "api", "hooks",
    "controllers", "handlers", "routes", "endpoints",
}

TIER3_DIRS = {"models", "schemas", "entities", "types"}

TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs"}

DOC_DIRS = {"docs", "documentation", "doc"}

TIER6_DIRS = {"components", "pages", "views", "screens", "layouts", "templates"}

API_DIRS = {"services", "api", "endpoints", "controllers", "handlers", "routes"}

TIER_FILE_CAPS = {1: 15, 2: 15, 3: 8, 4: 10, 5: 8, 6: 10, 7: 5}


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class ScanResult:
    content: str
    file_count: int
    total_size_kb: float
    total_eligible: int


@dataclass
class DiffContext:
    changed_files: list[str]
    file_contents: str
    diff: str
    file_count: int
    total_size_kb: float
    base_ref: str


# ---------------------------------------------------------------------------
# File tree
# ---------------------------------------------------------------------------

def get_project_file_tree(
    project_path: Path,
    max_depth: int = 4,
    exclude_dirs: Optional[set[str]] = None,
) -> str:
    """Generate a text-based file tree representation."""
    excludes = exclude_dirs or EXCLUDE_DIRS
    lines: list[str] = [project_path.name]

    def _walk(path: Path, prefix: str, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            entries = sorted(path.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
        except PermissionError:
            return
        entries = [e for e in entries if e.name not in excludes]
        for i, entry in enumerate(entries):
            is_last = i == len(entries) - 1
            connector = "+-- " if is_last else "|-- "
            extension = "    " if is_last else "|   "
            lines.append(f"{prefix}{connector}{entry.name}")
            if entry.is_dir():
                _walk(entry, prefix + extension, depth + 1)

    _walk(project_path, "", 1)
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# File tier classification
# ---------------------------------------------------------------------------

def _is_test_file(name: str) -> bool:
    """Check if a filename indicates a test file."""
    return (
        name.startswith("test_")
        or "_test." in name
        or ".test." in name
        or ".Tests." in name
        or ".spec." in name
        or name == "conftest.py"
    )


def _matches_glob(name: str, pattern: str) -> bool:
    """Simple glob match supporting * wildcard."""
    import fnmatch
    return fnmatch.fnmatch(name, pattern)


def get_file_tier(file_path: Path, project_path: Path) -> int:
    """Classify a file into a priority tier (1=highest, 7=lowest)."""
    name = file_path.name.lower()
    try:
        relative = file_path.relative_to(project_path)
    except ValueError:
        relative = Path(file_path.name)
    parts = [p.lower() for p in relative.parts]

    # Tier 1: Entry points & config
    if name in TIER1_ALWAYS:
        return 1
    if name.startswith("docker-compose."):
        return 1

    # Ambiguous names — only Tier 1 if NOT inside API dirs
    in_api_dir = any(p in API_DIRS for p in parts)
    if not in_api_dir:
        if name in ("settings.py", "setup.py") or name.startswith("config."):
            return 1

    # index.js/ts only Tier 1 if near root (max 2 dirs deep)
    if name in ("index.js", "index.ts") and len(parts) <= 3:
        return 1

    # Tier 2: Core business logic
    in_tier2_dir = any(p in TIER2_DIRS for p in parts)
    if in_tier2_dir and not _is_test_file(name):
        return 2

    # Tier 3: Models & schemas
    if any(p in TIER3_DIRS for p in parts):
        return 3

    # Tier 4: Tests
    if _is_test_file(name) or any(p in TEST_DIRS for p in parts):
        return 4

    # Tier 5: Documentation
    doc_patterns = [
        "readme*", "contributing*", "changelog*", "license*",
        "rollback*", "migration*", "deployment*", "backup*",
        "operations*", "runbook*", "install*", "architecture*",
    ]
    for pat in doc_patterns:
        if _matches_glob(name, pat):
            return 5
    if any(p in DOC_DIRS for p in parts) and file_path.suffix.lower() == ".md":
        return 5

    # Tier 6: Frontend components
    if any(p in TIER6_DIRS for p in parts):
        return 6

    # Tier 7: Everything else
    return 7


# ---------------------------------------------------------------------------
# Source file scanning
# ---------------------------------------------------------------------------

def _should_include_file(file_path: Path) -> bool:
    """Check if a file should be included based on extension and patterns."""
    name = file_path.name.lower()
    ext = file_path.suffix.lower()

    # Check extension or known bypass names
    if ext not in INCLUDE_EXTENSIONS and name not in TIER1_BYPASS_NAMES:
        return False

    # Check exclude patterns
    for pattern in EXCLUDE_PATTERNS:
        if _matches_glob(name, pattern):
            return False

    return True


def _is_in_excluded_dir(file_path: Path, project_path: Path) -> bool:
    """Check if a file is inside an excluded directory."""
    try:
        relative = file_path.relative_to(project_path)
    except ValueError:
        return False
    return any(p in EXCLUDE_DIRS for p in relative.parts)


def get_source_files_content(
    project_path: Path,
    max_files: int = 75,
    max_size_kb: int = 750,
    min_file_bytes: int = 50,
    max_file_kb: int = 50,
) -> ScanResult:
    """Read source files using 7-tier priority selection with two-pass filling."""
    max_bytes = max_size_kb * 1024
    max_file_bytes = max_file_kb * 1024
    tier_size_cap = int(max_bytes * 0.30)

    # Gather all eligible files
    all_files: list[Path] = []
    for root, dirs, files in os.walk(project_path):
        # Prune excluded dirs
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            fp = Path(root) / fname
            if _should_include_file(fp):
                all_files.append(fp)

    total_eligible = len(all_files)

    # Size filter
    sized_files = [
        f for f in all_files
        if min_file_bytes <= f.stat().st_size <= max_file_bytes
    ]

    # Classify into tiers
    tiered: list[tuple[Path, int]] = [
        (f, get_file_tier(f, project_path)) for f in sized_files
    ]

    # Group by tier, sort within by size descending
    tier_groups: dict[int, list[tuple[Path, int]]] = {}
    for f, tier in tiered:
        tier_groups.setdefault(tier, []).append((f, tier))
    for t in tier_groups:
        tier_groups[t].sort(key=lambda x: x[0].stat().st_size, reverse=True)

    # Pass 1: select up to cap from each tier
    selected: list[tuple[Path, int]] = []
    total_size = 0

    for t in range(1, 8):
        group = tier_groups.get(t, [])
        file_cap = TIER_FILE_CAPS.get(t, 5)
        tier_count = 0
        tier_size = 0
        for f, tier in group:
            if tier_count >= file_cap:
                break
            if len(selected) >= max_files:
                break
            fsize = f.stat().st_size
            if total_size + fsize > max_bytes:
                continue
            if tier_size + fsize > tier_size_cap:
                continue
            selected.append((f, tier))
            total_size += fsize
            tier_size += fsize
            tier_count += 1

    # Pass 2: fill remaining budget from unused files
    if len(selected) < max_files and total_size < max_bytes:
        selected_paths = {f for f, _ in selected}
        remaining = [
            (f, tier) for f, tier in tiered if f not in selected_paths
        ]
        remaining.sort(key=lambda x: (x[1], -x[0].stat().st_size))
        for f, tier in remaining:
            if len(selected) >= max_files:
                break
            fsize = f.stat().st_size
            if total_size + fsize > max_bytes:
                continue
            selected.append((f, tier))
            total_size += fsize

    # Build content (sorted by tier, then size desc)
    selected.sort(key=lambda x: (x[1], -x[0].stat().st_size))

    parts: list[str] = []
    file_count = 0
    actual_size = 0

    for f, _tier in selected:
        if file_count >= max_files:
            break
        fsize = f.stat().st_size
        if actual_size + fsize > max_bytes:
            continue
        try:
            content = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if not content.strip():
            continue

        relative = f.relative_to(project_path)
        lang_hint = f.suffix.lstrip(".")
        parts.append(f"---\n## File: {relative}\n```{lang_hint}\n{content}\n```\n")
        actual_size += fsize
        file_count += 1

    if file_count == 0:
        return ScanResult(
            content="(No source files found matching criteria)",
            file_count=0,
            total_size_kb=0,
            total_eligible=total_eligible,
        )

    header = f"# Source Files ({file_count} files, {round(actual_size / 1024, 1)} KB)\n\n"
    return ScanResult(
        content=header + "\n".join(parts),
        file_count=file_count,
        total_size_kb=round(actual_size / 1024, 1),
        total_eligible=total_eligible,
    )


# ---------------------------------------------------------------------------
# Diff context
# ---------------------------------------------------------------------------

def get_diff_context(
    project_path: Path,
    base_branch: Optional[str] = None,
    max_diff_kb: int = 100,
    max_content_kb: int = 200,
    max_file_kb: int = 50,
) -> Optional[DiffContext]:
    """Get diff-scoped context for PR/CI reviews."""
    # Auto-detect base branch from CI env
    if not base_branch:
        base_branch = (
            os.environ.get("GITHUB_BASE_REF")
            or (os.environ.get("SYSTEM_PULLREQUEST_TARGETBRANCH", "")
                .removeprefix("refs/heads/") or None)
        )

    if not base_branch:
        return None

    project_str = str(project_path)

    # Verify git repo
    try:
        check = subprocess.run(
            ["git", "-C", project_str, "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True, timeout=10,
        )
        if check.stdout.strip() != "true":
            return None
    except Exception:
        return None

    # Find base ref
    base_ref = None
    for candidate in [f"origin/{base_branch}", base_branch]:
        try:
            result = subprocess.run(
                ["git", "-C", project_str, "rev-parse", "--verify", candidate],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                base_ref = candidate
                break
        except Exception:
            continue

    if not base_ref:
        return None

    # Get changed files
    try:
        result = subprocess.run(
            ["git", "-C", project_str, "diff", "--name-only", base_ref],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        changed_files = [
            f for f in result.stdout.strip().split("\n")
            if f and not f.startswith("fatal:")
        ]
    except Exception:
        return None

    if not changed_files:
        return None

    # Get unified diff
    try:
        result = subprocess.run(
            ["git", "-C", project_str, "diff", base_ref],
            capture_output=True, text=True, timeout=30,
        )
        diff_text = result.stdout if result.returncode == 0 else "(diff unavailable)"
        max_diff_bytes = max_diff_kb * 1024
        if len(diff_text.encode("utf-8")) > max_diff_bytes:
            diff_text = diff_text[:max_diff_bytes]
            diff_text += (
                f"\n\n[Diff truncated at {max_diff_kb}KB"
                " -- some files omitted. Full file contents included above.]"
            )
    except Exception:
        diff_text = "(diff unavailable)"

    # Read full content of changed files
    parts: list[str] = []
    total_size = 0
    max_content_bytes = max_content_kb * 1024
    max_file_bytes = max_file_kb * 1024
    file_count = 0

    files_to_read = []
    for rel in changed_files:
        full = project_path / rel
        if full.is_file():
            fsize = full.stat().st_size
            if fsize <= max_file_bytes:
                files_to_read.append((rel, full, fsize))

    files_to_read.sort(key=lambda x: x[2])

    for rel, full, fsize in files_to_read:
        if total_size + fsize > max_content_bytes:
            continue
        try:
            content = full.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if not content:
            continue
        ext = full.suffix.lstrip(".")
        parts.append(f"---\n## File: {rel}\n```{ext}\n{content}\n```\n")
        total_size += fsize
        file_count += 1

    file_contents = (
        f"# Changed Files ({file_count} files, {round(total_size / 1024, 1)} KB)\n\n"
        + "\n".join(parts)
        if file_count > 0
        else "(No readable changed files found)"
    )

    return DiffContext(
        changed_files=changed_files,
        file_contents=file_contents,
        diff=diff_text,
        file_count=file_count,
        total_size_kb=round(total_size / 1024, 1),
        base_ref=base_ref,
    )
