"""Tests for formatters/junit.py."""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree as ET

from conclave.formatters.junit import convert_parsed_findings_to_junit, export_junit_results


class TestExportJunitResults:
    def _make_findings(self) -> dict[str, list[dict]]:
        return {
            "guardian": [
                {
                    "id": "GUARDIAN-001",
                    "title": "Hardcoded Key",
                    "severity": "BLOCKER",
                    "file": "src/config.py",
                    "line": 42,
                    "issue": "API key in source",
                    "recommendation": "Use env vars",
                },
                {
                    "id": "GUARDIAN-002",
                    "title": "Missing HTTPS",
                    "severity": "MEDIUM",
                    "file": "src/api.py",
                    "line": 10,
                    "issue": "HTTP instead of HTTPS",
                    "recommendation": "Switch to HTTPS",
                },
            ],
            "sentinel": [
                {
                    "id": "SENTINEL-001",
                    "title": "No Tests",
                    "severity": "HIGH",
                    "file": None,
                    "line": None,
                    "issue": "No unit tests",
                    "recommendation": "Add tests",
                },
            ],
        }

    def test_creates_xml_file(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        result = export_junit_results(self._make_findings(), out)
        assert out.exists()
        assert result["total_tests"] == 3

    def test_blocker_is_failure(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        export_junit_results(self._make_findings(), out)
        tree = ET.parse(out)
        root = tree.getroot()
        failures = root.findall(".//failure")
        # BLOCKER + HIGH = 2 failures
        assert len(failures) == 2

    def test_medium_is_passing(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        export_junit_results(self._make_findings(), out)
        tree = ET.parse(out)
        root = tree.getroot()
        # GUARDIAN-002 (MEDIUM) should have no failure child
        for tc in root.iter("testcase"):
            if "GUARDIAN-002" in tc.get("name", ""):
                assert tc.find("failure") is None

    def test_custom_fail_on(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        result = export_junit_results(
            self._make_findings(), out, fail_on=["BLOCKER"]
        )
        assert result["failures"] == 1  # Only BLOCKER

    def test_testsuites_attributes(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        export_junit_results(self._make_findings(), out, project_name="My Project", duration=10.5)
        tree = ET.parse(out)
        root = tree.getroot()
        assert root.get("name") == "My Project"
        assert root.get("tests") == "3"
        assert root.get("time") == "10.5"

    def test_file_and_line_attributes(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        export_junit_results(self._make_findings(), out)
        tree = ET.parse(out)
        root = tree.getroot()
        for tc in root.iter("testcase"):
            if "GUARDIAN-001" in tc.get("name", ""):
                assert tc.get("file") == "src/config.py"
                assert tc.get("line") == "42"

    def test_creates_parent_dirs(self, tmp_path: Path):
        out = tmp_path / "sub" / "dir" / "results.xml"
        export_junit_results(self._make_findings(), out)
        assert out.exists()

    def test_empty_findings(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        result = export_junit_results({}, out)
        assert result["total_tests"] == 0
        assert result["failures"] == 0

    def test_valid_xml(self, tmp_path: Path):
        out = tmp_path / "results.xml"
        export_junit_results(self._make_findings(), out)
        # Should parse without error
        ET.parse(out)


class TestConvertParsedFindingsToJunit:
    def test_converts_format(self, sample_all_findings: dict):
        result = convert_parsed_findings_to_junit(sample_all_findings)
        assert "guardian" in result
        assert "sentinel" in result
        assert len(result["guardian"]) == 2
        assert result["guardian"][0]["id"] == "GUARDIAN-001"

    def test_handles_empty(self):
        result = convert_parsed_findings_to_junit({})
        assert result == {}

    def test_handles_missing_findings(self):
        data = {"guardian": {"findings": None, "status": "error"}}
        result = convert_parsed_findings_to_junit(data)
        assert result["guardian"] == []
