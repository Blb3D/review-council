"""Tests for core/findings.py."""

from __future__ import annotations

import json
from pathlib import Path

from conclave.core.findings import (
    export_findings_json,
    export_run_archive,
    parse_findings_markdown,
    remove_working_findings,
)


class TestParseFindingsMarkdown:
    def test_parses_basic_findings(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["status"] == "complete"
        assert len(result["findings"]) == 2
        assert result["summary"]["blockers"] == 1
        assert result["summary"]["medium"] == 1
        assert result["summary"]["total"] == 2

    def test_parses_finding_id(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["findings"][0]["id"] == "GUARDIAN-001"
        assert result["findings"][1]["id"] == "GUARDIAN-002"

    def test_parses_severity(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["findings"][0]["severity"] == "BLOCKER"
        assert result["findings"][1]["severity"] == "MEDIUM"

    def test_parses_location(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["findings"][0]["file"] == "src/config.py"
        assert result["findings"][0]["line"] == 42

    def test_parses_issue_section(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert "hardcoded" in result["findings"][0]["issue"].lower()

    def test_skips_findings_inside_code_blocks(self):
        content = """# Review

```markdown
### FAKE-001: Not Real [BLOCKER]
This is inside a code block.
```

### REAL-001: Actual Finding [HIGH]

**Location:** src/app.py:1
**Effort:** Low

**Issue:**
Real issue here.

**Recommendation:**
Fix it.

COMPLETE: 0 BLOCKER, 1 HIGH, 0 MEDIUM, 0 LOW
"""
        result = parse_findings_markdown(
            content=content,
            agent_key="test",
            agent_name="Test",
            agent_role="Test",
        )
        assert len(result["findings"]) == 1
        assert result["findings"][0]["id"] == "REAL-001"

    def test_empty_content(self):
        result = parse_findings_markdown(
            content="",
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["status"] == "complete"
        assert len(result["findings"]) == 0

    def test_no_findings_content(self):
        content = "# Review\n\nNo issues found.\n\nCOMPLETE: 0 BLOCKER, 0 HIGH, 0 MEDIUM, 0 LOW\n"
        result = parse_findings_markdown(
            content=content,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert result["summary"]["total"] == 0

    def test_includes_agent_metadata(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
            run_timestamp="2026-02-13T10:00:00",
            project_name="test",
            tier="primary",
        )
        assert result["agent"]["id"] == "guardian"
        assert result["agent"]["name"] == "The Guardian"

    def test_includes_run_metadata(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
            duration_seconds=5.5,
            dry_run=True,
        )
        assert result["run"]["durationSeconds"] == 5.5

    def test_parses_recommendation(self, sample_findings_markdown: str):
        result = parse_findings_markdown(
            content=sample_findings_markdown,
            agent_key="guardian",
            agent_name="The Guardian",
            agent_role="Security",
        )
        assert "environment" in result["findings"][0]["recommendation"].lower()


class TestExportFindingsJson:
    def test_writes_valid_json(self, tmp_path: Path, sample_parsed_findings: dict):
        out = tmp_path / "findings.json"
        export_findings_json(sample_parsed_findings, out)
        data = json.loads(out.read_text(encoding="utf-8"))
        assert data["agent"]["id"] == "guardian"
        assert len(data["findings"]) == 2

    def test_creates_parent_dirs(self, tmp_path: Path, sample_parsed_findings: dict):
        out = tmp_path / "sub" / "dir" / "findings.json"
        export_findings_json(sample_parsed_findings, out)
        assert out.exists()


class TestRemoveWorkingFindings:
    def test_removes_working_files(self, tmp_path: Path):
        (tmp_path / "guardian-findings.md").write_text("x", encoding="utf-8")
        (tmp_path / "guardian-findings.json").write_text("{}", encoding="utf-8")
        (tmp_path / "RELEASE-READINESS-REPORT.md").write_text("x", encoding="utf-8")
        remove_working_findings(tmp_path)
        assert not (tmp_path / "guardian-findings.md").exists()
        assert not (tmp_path / "guardian-findings.json").exists()
        assert not (tmp_path / "RELEASE-READINESS-REPORT.md").exists()

    def test_preserves_archive(self, tmp_path: Path):
        archive = tmp_path / "archive"
        archive.mkdir()
        (archive / "run-2026.json").write_text("{}", encoding="utf-8")
        remove_working_findings(tmp_path)
        assert (archive / "run-2026.json").exists()


class TestExportRunArchive:
    def test_creates_archive(self, tmp_path: Path, sample_all_findings: dict):
        reviews_dir = tmp_path / "reviews"
        reviews_dir.mkdir()
        (reviews_dir / "archive").mkdir()

        export_run_archive(
            reviews_dir,
            sample_all_findings,
            {
                "timestamp": "2026-02-13T10:00:00",
                "project": "test",
                "verdict": "HOLD",
            },
        )

        archive_files = list((reviews_dir / "archive").glob("*.json"))
        assert len(archive_files) == 1
