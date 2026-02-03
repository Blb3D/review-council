# Compliance Standards Guide

Code Conclave supports mapping review findings to regulatory compliance frameworks. This guide explains how to use compliance packs for regulated industries.

---

## Overview

Compliance packs define:
- **Controls**: Specific requirements from a standard
- **Finding Patterns**: Which Code Conclave findings address each control
- **Agent Mappings**: Which agents are relevant to each control
- **Gap Analysis**: Identification of unaddressed controls

---

## Available Standards

### CMMC Level 2 (cmmc-l2)

**Domain**: Cybersecurity Maturity Model Certification

**Applicability**: Defense contractors handling Controlled Unclassified Information (CUI)

| Attribute | Value |
|-----------|-------|
| ID | `cmmc-l2` |
| Version | 2.0 |
| Controls | 110 practices |
| Domains | 14 |

**Domains covered**:
- AC: Access Control
- AU: Audit and Accountability
- AT: Awareness and Training
- CM: Configuration Management
- IA: Identification and Authentication
- IR: Incident Response
- MA: Maintenance
- MP: Media Protection
- PS: Personnel Security
- PE: Physical Protection
- RA: Risk Assessment
- CA: Security Assessment
- SC: System and Communications Protection
- SI: System and Information Integrity

```powershell
# Run review with CMMC context
.\cli\ccl.ps1 -Project "C:\myproject" -Standard cmmc-l2
```

---

### FDA 21 CFR 820 QSR (fda-820-qsr)

**Domain**: Medical Device Quality System Regulation

**Applicability**: Medical device manufacturers subject to FDA regulation

| Attribute | Value |
|-----------|-------|
| ID | `fda-820-qsr` |
| Version | Current |
| Controls | ~45 requirements |
| Subparts | 14 |

**Key sections**:
- 820.30: Design Controls
- 820.40: Document Controls
- 820.50: Purchasing Controls
- 820.70: Production and Process Controls
- 820.75: Process Validation
- 820.90: Nonconforming Product
- 820.100: Corrective and Preventive Action (CAPA)
- 820.180: General Requirements for Records

```powershell
# Run review with FDA 820 context
.\cli\ccl.ps1 -Project "C:\myproject" -Standard fda-820-qsr
```

---

### FDA 21 CFR Part 11 (fda-21-cfr-11)

**Domain**: Electronic Records and Electronic Signatures

**Applicability**: Organizations using electronic records in FDA-regulated activities

| Attribute | Value |
|-----------|-------|
| ID | `fda-21-cfr-11` |
| Version | Current |
| Controls | ~25 requirements |
| Subparts | 3 |

**Key sections**:
- Subpart B: Electronic Records
  - 11.10: Controls for Closed Systems
  - 11.30: Controls for Open Systems
  - 11.50: Signature Manifestations
  - 11.70: Signature/Record Linking
- Subpart C: Electronic Signatures
  - 11.100: General Requirements
  - 11.200: Electronic Signature Components
  - 11.300: Controls for Identification Codes/Passwords

```powershell
# Run review with FDA Part 11 context
.\cli\ccl.ps1 -Project "C:\myproject" -Standard fda-21-cfr-11
```

---

## Using Compliance Standards

### Review with Compliance Context

When you specify a standard, agents receive additional context about relevant controls:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -Standard cmmc-l2
```

This enhances findings with:
- Control references where applicable
- Compliance-relevant context
- Standard-specific severity adjustments

### Map Existing Findings

Map findings from a previous review to a compliance standard:

```powershell
.\cli\ccl.ps1 -Map "C:\myproject\.code-conclave" -Standard cmmc-l2
```

Output: `COMPLIANCE-MAPPING-CMMC-L2.md`

### List Available Standards

```powershell
.\cli\ccl.ps1 -Standards list
```

Output:
```
Available Compliance Standards
===============================

[cybersecurity]
  cmmc-l2 - CMMC Level 2 (110 controls)

[medical]
  fda-820-qsr - FDA 21 CFR 820 QSR
  fda-21-cfr-11 - FDA 21 CFR Part 11
```

### Get Standard Details

```powershell
.\cli\ccl.ps1 -Standards info -Standard cmmc-l2
```

Output:
```
CMMC Level 2
============

ID:      cmmc-l2
Domain:  cybersecurity
Version: 2.0

Controls:
  Total: 110
  Critical: 15

Agent Coverage:
  SENTINEL    12 controls
  GUARDIAN    45 controls
  ARCHITECT   18 controls
  NAVIGATOR   8 controls
  HERALD      15 controls
  OPERATOR    22 controls
```

---

## Compliance Reports

### Gap Analysis Report

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template gap-analysis -Standard cmmc-l2
```

Generates a report showing:
- Coverage overview (controls addressed vs gaps)
- Coverage by domain
- Critical gaps requiring attention
- Mapped findings with control references
- Remediation roadmap

### Traceability Matrix

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template traceability-matrix -Standard cmmc-l2
```

Generates:
- Finding → Control mapping
- Control → Finding reverse mapping
- Gaps (controls without findings)
- Unmapped findings

### Export Formats

```powershell
# Markdown (default)
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template gap-analysis -Standard cmmc-l2

# JSON (for programmatic processing)
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template gap-analysis -Standard cmmc-l2 -Format json

# CSV (for spreadsheet analysis)
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template gap-analysis -Standard cmmc-l2 -Format csv
```

---

## How Mapping Works

### Finding Patterns

Each control in a standard specifies patterns that indicate a finding addresses it:

```yaml
controls:
  - id: AC.L2-3.1.1
    title: Authorized Access Control
    agents: [guardian, architect]
    finding_patterns:
      - "GUARDIAN-*"      # Any GUARDIAN finding
      - "ARCHITECT-003"   # Specific finding
```

### Pattern Matching

| Pattern | Matches |
|---------|---------|
| `GUARDIAN-*` | Any GUARDIAN finding (GUARDIAN-001, GUARDIAN-002, etc.) |
| `SENTINEL-005` | Only SENTINEL-005 specifically |
| `*-AUTH-*` | Any finding with AUTH in the ID |

### Coverage Calculation

```
Coverage % = (Controls with at least one mapped finding / Total controls) × 100
```

A control is "addressed" if at least one finding matches its patterns.

---

## Creating Custom Standards

### Standard Schema

Standards are defined in YAML following `core/schemas/standard.schema.json`:

```yaml
id: my-standard
name: My Custom Standard
domain: custom
version: "1.0"
description: Custom compliance framework

domains:
  - id: DOM1
    name: Domain One
    controls:
      - id: DOM1.001
        title: Control Title
        description: What this control requires
        agents: [guardian, sentinel]
        finding_patterns:
          - "GUARDIAN-*"
        critical: true  # Optional: marks as critical control
```

### Adding a Standard

1. Create YAML file in appropriate directory:
   ```
   core/standards/
   ├── core/           # General standards (ISO 9001, etc.)
   └── regulated/
       ├── cybersecurity/  # CMMC, SOC 2, etc.
       ├── medical/        # FDA, ISO 13485, etc.
       ├── aerospace/      # AS9100, DO-178C, etc.
       └── environmental/  # ISO 14001, etc.
   ```

2. Validate against schema (optional):
   ```powershell
   # Schema validation is automatic when loading
   ```

3. Test:
   ```powershell
   .\cli\ccl.ps1 -Standards info -Standard my-standard
   ```

---

## Agent-Control Relationships

### Which Agents Address Which Domains

| Standard Domain | Primary Agents | Secondary Agents |
|-----------------|----------------|------------------|
| Access Control | GUARDIAN | ARCHITECT |
| Audit/Logging | OPERATOR | SENTINEL |
| Configuration | ARCHITECT | OPERATOR |
| Documentation | HERALD | SENTINEL |
| Identification/Auth | GUARDIAN | ARCHITECT |
| Incident Response | OPERATOR | GUARDIAN |
| System Protection | GUARDIAN | OPERATOR |
| Testing/Validation | SENTINEL | ARCHITECT |

### Improving Coverage

To improve compliance coverage:

1. **Run all agents**: Full coverage requires all 6 agents
2. **Use compliance context**: `-Standard` flag provides agents with control context
3. **Review gaps**: Gap analysis shows which controls need attention
4. **Add focused findings**: Create findings that specifically address gap controls

---

## Best Practices

1. **Run full review first**: Get baseline findings before mapping
2. **Start with gap analysis**: Identify coverage before deep-diving
3. **Focus on critical controls**: Address critical gaps first
4. **Document compensating controls**: When technical controls aren't feasible
5. **Iterate**: Re-run mapping after addressing findings

---

*Code Conclave v2.0*
