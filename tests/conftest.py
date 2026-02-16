"""Shared fixtures for Code Conclave tests."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest


@pytest.fixture
def tmp_project(tmp_path: Path) -> Path:
    """Create a minimal project structure for testing."""
    project = tmp_path / "test-project"
    project.mkdir()
    (project / "src").mkdir()
    (project / "src" / "main.py").write_text("print('hello')\n", encoding="utf-8")
    (project / "src" / "utils.py").write_text("def add(a, b): return a + b\n", encoding="utf-8")
    (project / "README.md").write_text("# Test Project\n", encoding="utf-8")
    return project


@pytest.fixture
def initialized_project(tmp_project: Path) -> Path:
    """Create a project with .code-conclave initialized."""
    cc_dir = tmp_project / ".code-conclave"
    cc_dir.mkdir()
    (cc_dir / "reviews").mkdir()
    (cc_dir / "reviews" / "archive").mkdir()
    (cc_dir / "agents").mkdir()

    config = cc_dir / "config.yaml"
    config.write_text(
        'project:\n  name: "test-project"\n\nai:\n  provider: anthropic\n',
        encoding="utf-8",
    )
    return tmp_project


@pytest.fixture
def sample_findings_markdown() -> str:
    """Return a sample agent findings markdown."""
    return """# GUARDIAN Security Review

## Project: test-project

### GUARDIAN-001: Hardcoded API Key [BLOCKER]

**Location:** src/config.py:42
**Effort:** Medium

**Issue:**
API key is hardcoded in source code.

**Evidence:**
```python
API_KEY = "sk-abc123"
```

**Recommendation:**
Move to environment variables.

### GUARDIAN-002: Missing HTTPS [MEDIUM]

**Location:** src/api.py:10
**Effort:** Low

**Issue:**
HTTP used instead of HTTPS for API calls.

**Recommendation:**
Switch to HTTPS.

COMPLETE: 1 BLOCKER, 0 HIGH, 1 MEDIUM, 0 LOW
"""


@pytest.fixture
def sample_parsed_findings() -> dict:
    """Return a sample parsed findings dict for one agent."""
    return {
        "agent": {
            "id": "guardian",
            "name": "The Guardian",
            "role": "Security",
            "tier": "primary",
        },
        "status": "success",
        "summary": {"blockers": 1, "high": 0, "medium": 1, "low": 0, "total": 2},
        "findings": [
            {
                "id": "GUARDIAN-001",
                "title": "Hardcoded API Key",
                "severity": "BLOCKER",
                "file": "src/config.py",
                "line": 42,
                "effort": "Medium",
                "issue": "API key is hardcoded in source code.",
                "evidence": 'API_KEY = "sk-abc123"',
                "recommendation": "Move to environment variables.",
            },
            {
                "id": "GUARDIAN-002",
                "title": "Missing HTTPS",
                "severity": "MEDIUM",
                "file": "src/api.py",
                "line": 10,
                "effort": "Low",
                "issue": "HTTP used instead of HTTPS for API calls.",
                "evidence": "",
                "recommendation": "Switch to HTTPS.",
            },
        ],
        "run": {"durationSeconds": 5.2},
    }


@pytest.fixture
def sample_all_findings(sample_parsed_findings: dict) -> dict[str, dict]:
    """Return findings for multiple agents."""
    sentinel = {
        "agent": {
            "id": "sentinel",
            "name": "The Sentinel",
            "role": "Quality",
            "tier": "primary",
        },
        "status": "success",
        "summary": {"blockers": 0, "high": 1, "medium": 0, "low": 1, "total": 2},
        "findings": [
            {
                "id": "SENTINEL-001",
                "title": "No Unit Tests",
                "severity": "HIGH",
                "file": "src/main.py",
                "line": None,
                "effort": "High",
                "issue": "No unit tests found.",
                "evidence": "",
                "recommendation": "Add pytest tests.",
            },
            {
                "id": "SENTINEL-002",
                "title": "Missing Docstrings",
                "severity": "LOW",
                "file": "src/utils.py",
                "line": 1,
                "effort": "Low",
                "issue": "Functions lack docstrings.",
                "evidence": "",
                "recommendation": "Add docstrings.",
            },
        ],
        "run": {"durationSeconds": 4.8},
    }
    return {
        "guardian": sample_parsed_findings,
        "sentinel": sentinel,
    }
