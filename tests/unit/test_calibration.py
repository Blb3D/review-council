"""Tests for the calibration system."""

import yaml
from pathlib import Path

from conclave.core.calibration import (
    add_project_rule,
    add_reviewed_finding,
    build_calibration_context,
    load_calibration,
    save_calibration,
)


class TestLoadSaveCalibration:
    def test_load_missing_file(self, tmp_path):
        cal = load_calibration(tmp_path)
        assert cal["reviewed_findings"] == []
        assert cal["project_rules"] == []

    def test_save_and_load_roundtrip(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        data = {
            "reviewed_findings": [{"finding_id": "GUARDIAN-001", "verdict": "confirmed"}],
            "project_rules": [{"rule": "All endpoints use JWT"}],
        }
        save_calibration(tmp_path, data)
        loaded = load_calibration(tmp_path)
        assert len(loaded["reviewed_findings"]) == 1
        assert loaded["reviewed_findings"][0]["finding_id"] == "GUARDIAN-001"
        assert len(loaded["project_rules"]) == 1

    def test_load_with_bom(self, tmp_path):
        """Files with BOM should load correctly."""
        cc_dir = tmp_path / ".code-conclave"
        cc_dir.mkdir(parents=True)
        cal_path = cc_dir / "calibration.yaml"
        cal_path.write_text(
            "\ufeffreviewed_findings: []\nproject_rules: []\n",
            encoding="utf-8",
        )
        cal = load_calibration(tmp_path)
        assert cal["reviewed_findings"] == []

    def test_load_corrupt_file(self, tmp_path):
        """Corrupt YAML returns empty defaults."""
        cc_dir = tmp_path / ".code-conclave"
        cc_dir.mkdir(parents=True)
        (cc_dir / "calibration.yaml").write_text("{{{{invalid yaml", encoding="utf-8")
        cal = load_calibration(tmp_path)
        assert cal["reviewed_findings"] == []


class TestAddReviewedFinding:
    def test_add_false_positive(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        entry = add_reviewed_finding(
            tmp_path,
            finding_id="GUARDIAN-002",
            agent="guardian",
            original_severity="BLOCKER",
            adjusted_severity="REJECTED",
            verdict="false_positive",
            reason="Admin-only endpoint, parameterized ORM",
            file_path="backend/services/customer_service.py",
            title="SQL Injection Risk in Customer Search",
        )
        assert entry["finding_id"] == "GUARDIAN-002"
        assert entry["verdict"] == "false_positive"

        # Verify it persisted
        cal = load_calibration(tmp_path)
        assert len(cal["reviewed_findings"]) == 1
        assert cal["reviewed_findings"][0]["original_severity"] == "BLOCKER"

    def test_add_adjusted(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path,
            finding_id="GUARDIAN-003",
            agent="guardian",
            original_severity="HIGH",
            adjusted_severity="LOW",
            verdict="adjusted",
            reason="Internal endpoint only",
        )
        cal = load_calibration(tmp_path)
        assert cal["reviewed_findings"][0]["adjusted_severity"] == "LOW"

    def test_replaces_existing_finding(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path, "GUARDIAN-001", "guardian", "BLOCKER", "BLOCKER",
            "confirmed", "Real issue",
        )
        add_reviewed_finding(
            tmp_path, "GUARDIAN-001", "guardian", "BLOCKER", "MEDIUM",
            "adjusted", "Actually not that bad",
        )
        cal = load_calibration(tmp_path)
        assert len(cal["reviewed_findings"]) == 1
        assert cal["reviewed_findings"][0]["verdict"] == "adjusted"


class TestAddProjectRule:
    def test_add_rule(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        entry = add_project_rule(
            tmp_path,
            rule="All /api/v1/admin/ endpoints require JWT auth",
            applies_to="guardian",
            severity_cap="MEDIUM",
        )
        assert entry["rule"].startswith("All /api/v1/admin/")
        assert entry["severity_cap"] == "MEDIUM"

        cal = load_calibration(tmp_path)
        assert len(cal["project_rules"]) == 1

    def test_add_multiple_rules(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_project_rule(tmp_path, "Rule 1")
        add_project_rule(tmp_path, "Rule 2")
        cal = load_calibration(tmp_path)
        assert len(cal["project_rules"]) == 2


class TestBuildCalibrationContext:
    def test_empty_calibration(self, tmp_path):
        ctx = build_calibration_context(tmp_path, "guardian")
        assert ctx == ""

    def test_false_positive_context(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path, "GUARDIAN-002", "guardian", "BLOCKER", "REJECTED",
            "false_positive", "ORM is parameterized",
            file_path="services/search.py",
            title="SQL Wildcard Injection",
        )
        ctx = build_calibration_context(tmp_path, "guardian")
        assert "CALIBRATION DATA" in ctx
        assert "False Positives" in ctx
        assert "GUARDIAN-002" in ctx
        assert "ORM is parameterized" in ctx

    def test_adjusted_context(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path, "GUARDIAN-003", "guardian", "HIGH", "LOW",
            "adjusted", "Admin endpoint",
            title="Missing Rate Limit",
        )
        ctx = build_calibration_context(tmp_path, "guardian")
        assert "Severity Adjustments" in ctx
        assert "was HIGH, adjusted to LOW" in ctx

    def test_confirmed_context(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path, "GUARDIAN-001", "guardian", "BLOCKER", "BLOCKER",
            "confirmed", "Real hardcoded key",
            title="Hardcoded API Key",
        )
        ctx = build_calibration_context(tmp_path, "guardian")
        assert "True Positives" in ctx
        assert "confirmed" in ctx

    def test_filters_by_agent(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_reviewed_finding(
            tmp_path, "GUARDIAN-001", "guardian", "BLOCKER", "REJECTED",
            "false_positive", "FP reason",
        )
        add_reviewed_finding(
            tmp_path, "SENTINEL-001", "sentinel", "HIGH", "REJECTED",
            "false_positive", "Different agent FP",
        )
        # Guardian context should only show Guardian findings
        ctx = build_calibration_context(tmp_path, "guardian")
        assert "GUARDIAN-001" in ctx
        assert "SENTINEL-001" not in ctx

    def test_project_rules_included(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_project_rule(tmp_path, "All admin endpoints behind auth", "guardian")
        ctx = build_calibration_context(tmp_path, "guardian")
        assert "Project-Specific Rules" in ctx
        assert "admin endpoints" in ctx

    def test_project_rules_filter_by_agent(self, tmp_path):
        (tmp_path / ".code-conclave").mkdir(parents=True)
        add_project_rule(tmp_path, "Guardian-only rule", "guardian")
        add_project_rule(tmp_path, "All-agent rule", "all")
        add_project_rule(tmp_path, "Sentinel-only rule", "sentinel")

        ctx = build_calibration_context(tmp_path, "guardian")
        assert "Guardian-only rule" in ctx
        assert "All-agent rule" in ctx
        assert "Sentinel-only rule" not in ctx
