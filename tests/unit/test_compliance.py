"""Tests for compliance/."""

from __future__ import annotations

from conclave.compliance.mapping import (
    get_agent_controls,
    get_all_controls,
    get_compliance_mapping,
    match_finding_to_controls,
    test_finding_pattern as check_finding_pattern,
)


class TestFindingPattern:
    def test_exact_match(self):
        assert check_finding_pattern("GUARDIAN-001", "GUARDIAN-001") is True

    def test_exact_no_match(self):
        assert check_finding_pattern("GUARDIAN-001", "GUARDIAN-002") is False

    def test_wildcard_match(self):
        assert check_finding_pattern("GUARDIAN-001", "GUARDIAN-*") is True

    def test_wildcard_no_match(self):
        assert check_finding_pattern("SENTINEL-001", "GUARDIAN-*") is False

    def test_wildcard_any(self):
        assert check_finding_pattern("ANYTHING-999", "*") is True


class TestGetAllControls:
    def test_cmmc_style(self):
        standard = {
            "id": "cmmc-l2",
            "name": "CMMC Level 2",
            "domains": [
                {
                    "id": "AC",
                    "name": "Access Control",
                    "controls": [
                        {"id": "AC.1.001", "title": "Limit access", "agents": ["guardian"]},
                        {"id": "AC.1.002", "title": "Transaction control"},
                    ],
                }
            ],
        }
        controls = get_all_controls(standard)
        assert len(controls) == 2
        assert controls[0].id == "AC.1.001"
        assert controls[0].domain_id == "AC"

    def test_fda_style_with_subsections(self):
        standard = {
            "id": "fda-820",
            "name": "FDA 820 QSR",
            "subparts": [
                {
                    "id": "A",
                    "name": "General Provisions",
                    "sections": [
                        {
                            "id": "820.1",
                            "title": "Scope",
                            "subsections": [
                                {"id": "820.1(a)", "title": "Applicability"},
                                {"id": "820.1(b)", "title": "Limitations"},
                            ],
                        }
                    ],
                }
            ],
        }
        controls = get_all_controls(standard)
        assert len(controls) == 2
        assert controls[0].id == "820.1(a)"

    def test_fda_style_without_subsections(self):
        standard = {
            "id": "fda-820",
            "name": "FDA 820 QSR",
            "subparts": [
                {
                    "id": "A",
                    "name": "General",
                    "sections": [
                        {"id": "820.1", "title": "Scope"},
                    ],
                }
            ],
        }
        controls = get_all_controls(standard)
        assert len(controls) == 1
        assert controls[0].id == "820.1"

    def test_empty_standard(self):
        controls = get_all_controls({"id": "empty", "name": "Empty"})
        assert controls == []


class TestMatchFindingToControls:
    def test_matches_by_pattern(self):
        controls = get_all_controls({
            "domains": [{
                "id": "AC", "name": "AC",
                "controls": [
                    {"id": "AC.1", "title": "Test", "finding_patterns": ["GUARDIAN-*"]},
                ],
            }],
        })
        finding = {"id": "GUARDIAN-001", "title": "Test", "severity": "HIGH"}
        matched = match_finding_to_controls(finding, controls)
        assert len(matched) == 1
        assert matched[0].id == "AC.1"

    def test_no_match(self):
        controls = get_all_controls({
            "domains": [{
                "id": "AC", "name": "AC",
                "controls": [
                    {"id": "AC.1", "title": "Test", "finding_patterns": ["SENTINEL-*"]},
                ],
            }],
        })
        finding = {"id": "GUARDIAN-001", "title": "Test", "severity": "HIGH"}
        matched = match_finding_to_controls(finding, controls)
        assert len(matched) == 0


class TestGetComplianceMapping:
    def _make_standard(self):
        return {
            "id": "test-std",
            "name": "Test Standard",
            "domains": [
                {
                    "id": "D1",
                    "name": "Domain 1",
                    "controls": [
                        {"id": "D1.1", "title": "Control 1", "finding_patterns": ["GUARDIAN-*"], "critical": True},
                        {"id": "D1.2", "title": "Control 2", "finding_patterns": ["SENTINEL-*"]},
                        {"id": "D1.3", "title": "Control 3"},
                    ],
                }
            ],
        }

    def test_coverage_calculation(self):
        standard = self._make_standard()
        findings = [
            {"id": "GUARDIAN-001", "title": "Test", "severity": "BLOCKER"},
        ]
        mapping = get_compliance_mapping(findings, standard)
        assert mapping.total_controls == 3
        assert mapping.addressed_controls == 1
        assert mapping.gapped_controls == 2

    def test_gaps_identified(self):
        standard = self._make_standard()
        findings = [
            {"id": "GUARDIAN-001", "title": "Test", "severity": "HIGH"},
        ]
        mapping = get_compliance_mapping(findings, standard)
        gap_ids = [g.id for g in mapping.gaps]
        assert "D1.2" in gap_ids
        assert "D1.3" in gap_ids

    def test_critical_gaps(self):
        standard = self._make_standard()
        # No findings match D1.1 (critical)
        findings = [
            {"id": "SENTINEL-001", "title": "Test", "severity": "LOW"},
        ]
        mapping = get_compliance_mapping(findings, standard)
        assert len(mapping.critical_gaps) == 1
        assert mapping.critical_gaps[0].id == "D1.1"

    def test_full_coverage(self):
        standard = self._make_standard()
        findings = [
            {"id": "GUARDIAN-001", "title": "A", "severity": "HIGH"},
            {"id": "SENTINEL-001", "title": "B", "severity": "MEDIUM"},
        ]
        mapping = get_compliance_mapping(findings, standard)
        # D1.1 and D1.2 addressed, D1.3 has no patterns so stays gapped
        assert mapping.addressed_controls == 2

    def test_domain_coverage(self):
        standard = self._make_standard()
        findings = [{"id": "GUARDIAN-001", "title": "A", "severity": "HIGH"}]
        mapping = get_compliance_mapping(findings, standard)
        assert "D1" in mapping.by_domain
        assert mapping.by_domain["D1"].total == 3
        assert mapping.by_domain["D1"].addressed == 1


class TestGetAgentControls:
    def test_filters_by_agent(self):
        standard = {
            "domains": [{
                "id": "AC", "name": "AC",
                "controls": [
                    {"id": "AC.1", "title": "A", "agents": ["guardian"]},
                    {"id": "AC.2", "title": "B", "agents": ["sentinel"]},
                    {"id": "AC.3", "title": "C", "agents": ["guardian", "sentinel"]},
                ],
            }],
        }
        controls = get_agent_controls(standard, "guardian")
        ids = [c.id for c in controls]
        assert "AC.1" in ids
        assert "AC.3" in ids
        assert "AC.2" not in ids
