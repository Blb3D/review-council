"""JUnit XML formatter for CI/CD integration.

Port of cli/lib/junit-formatter.ps1.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from xml.dom import minidom
from xml.etree import ElementTree as ET


def export_junit_results(
    all_findings: dict[str, list[dict]],
    output_path: Path,
    fail_on: list[str] | None = None,
    project_name: str = "Code Conclave",
    duration: float = 0,
) -> dict:
    """Export findings as JUnit XML.

    Args:
        all_findings: Dict of agent_key -> list of finding dicts.
            Each finding has: id, title, severity, file, line, issue, recommendation.
        output_path: Path to write the XML file.
        fail_on: Severities to mark as failures. Default: BLOCKER, HIGH.
        project_name: Name for the testsuites element.
        duration: Total duration in seconds.

    Returns:
        Dict with: path, total_tests, failures, passed.
    """
    if fail_on is None:
        fail_on = ["BLOCKER", "HIGH"]
    fail_set = set(fail_on)

    testsuites = ET.Element("testsuites")
    testsuites.set("name", project_name)
    testsuites.set("timestamp", datetime.now().strftime("%Y-%m-%dT%H:%M:%S"))

    total_tests = 0
    total_failures = 0

    for agent_key, findings in all_findings.items():
        if not findings:
            continue

        agent_name = agent_key.upper()
        testsuite = ET.SubElement(testsuites, "testsuite")
        testsuite.set("name", agent_name)
        testsuite.set("tests", str(len(findings)))

        suite_failures = 0

        for finding in findings:
            total_tests += 1

            testcase = ET.SubElement(testsuite, "testcase")
            testcase.set("name", f"{finding.get('id', '?')}: {finding.get('title', '?')}")
            testcase.set("classname", agent_name)

            if finding.get("file"):
                testcase.set("file", finding["file"])
            if finding.get("line") is not None:
                testcase.set("line", str(finding["line"]))

            severity = finding.get("severity", "")
            if severity in fail_set:
                total_failures += 1
                suite_failures += 1

                failure = ET.SubElement(testcase, "failure")
                failure.set("message", f"[{severity}] {finding.get('title', '')}")
                failure.set("type", severity.lower())

                text_parts = [f"Severity: {severity}"]
                if finding.get("file"):
                    text_parts.append(f"File: {finding['file']}")
                if finding.get("line") is not None:
                    text_parts.append(f"Line: {finding['line']}")
                if finding.get("issue"):
                    text_parts.append(f"\nDescription:\n{finding['issue']}")
                if finding.get("recommendation"):
                    text_parts.append(f"\nRemediation:\n{finding['recommendation']}")

                failure.text = "\n".join(text_parts)

        testsuite.set("failures", str(suite_failures))
        testsuite.set("errors", "0")
        testsuite.set("skipped", "0")

    testsuites.set("tests", str(total_tests))
    testsuites.set("failures", str(total_failures))
    testsuites.set("errors", "0")
    if duration > 0:
        testsuites.set("time", str(round(duration, 2)))

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Pretty-print XML
    rough = ET.tostring(testsuites, encoding="unicode")
    dom = minidom.parseString(rough)
    xml_str = dom.toprettyxml(indent="  ", encoding="UTF-8")
    output_path.write_bytes(xml_str)

    return {
        "path": str(output_path),
        "total_tests": total_tests,
        "failures": total_failures,
        "passed": total_tests - total_failures,
    }


def convert_parsed_findings_to_junit(
    json_findings: dict[str, dict],
) -> dict[str, list[dict]]:
    """Convert parsed findings (from parse_findings_markdown) to JUnit format."""
    result: dict[str, list[dict]] = {}
    for agent_key, agent_data in json_findings.items():
        result[agent_key] = []
        if agent_data and agent_data.get("findings"):
            for f in agent_data["findings"]:
                result[agent_key].append({
                    "id": f.get("id", ""),
                    "title": f.get("title", ""),
                    "severity": f.get("severity", ""),
                    "file": f.get("file"),
                    "line": f.get("line"),
                    "issue": f.get("issue", ""),
                    "recommendation": f.get("recommendation", ""),
                })
    return result
