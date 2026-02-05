# Compliance Standards Reference

Guide to using compliance standards with Code Conclave.

---

## Table of Contents

- [Overview](#overview)
- [How Standards Work](#how-standards-work)
- [Available Standards](#available-standards)
- [Standard Tiers](#standard-tiers)
- [Using Standards](#using-standards)
- [Standard Profiles](#standard-profiles)
- [Finding-to-Control Mapping](#finding-to-control-mapping)
- [Custom Standards](#custom-standards)

---

## Overview

Code Conclave includes built-in compliance standard packs that map code review findings to regulatory controls. This helps teams:

- **Track compliance** during development
- **Generate evidence** for audits
- **Identify gaps** in control coverage
- **Prioritize fixes** based on compliance impact

---

## How Standards Work

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Agent     │────▶│  Findings   │────▶│  Standard   │
│   Review    │     │  Report     │     │   Mapper    │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  Compliance │
                                        │   Report    │
                                        └─────────────┘
```

1. Agents produce findings with tags (e.g., `security`, `testing`, `logging`)
2. Mapping engine matches tags to standard controls
3. Compliance report shows which controls have findings

---

## Available Standards

### Quality Management

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `iso-9001-2015` | ISO 9001 | 2015 | Quality Management Systems |
| `iso-13485-2016` | ISO 13485 | 2016 | Medical Device QMS |

### Cybersecurity

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `cmmc-l1` | CMMC Level 1 | 2.0 | Basic cyber hygiene (17 practices) |
| `cmmc-l2` | CMMC Level 2 | 2.0 | Advanced cyber hygiene (110 practices) |
| `nist-800-171` | NIST 800-171 | Rev 2 | CUI protection (110 controls) |

### Medical Device

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `fda-21-cfr-11` | 21 CFR Part 11 | Current | Electronic records/signatures |
| `fda-820-qsr` | FDA 820 QSR | Current | Quality System Regulation |
| `iso-14971-2019` | ISO 14971 | 2019 | Risk management for medical devices |

### Aerospace

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `as9100-rev-d` | AS9100 | Rev D | Aerospace QMS |

### Export Control

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `itar` | ITAR | Current | International Traffic in Arms (45 controls) |

### Automotive

| ID | Name | Version | Description |
|----|------|---------|-------------|
| `iatf-16949-2016` | IATF 16949 | 2016 | Automotive QMS |

---

## Standard Tiers

Standards are organized into three tiers:

### Tier 1: Required

**Always applied, cannot be skipped.**

Use for organizational mandates that must apply to all projects.

```yaml
standards:
  required:
    - iso-9001-2015  # Company-wide QMS requirement
```

### Tier 2: Default

**Applied unless explicitly skipped with `-SkipStandards`.**

Use for standards that normally apply but can be bypassed for specific situations.

```yaml
standards:
  default:
    - fda-21-cfr-11
    - iso-13485-2016
```

Skip for a run:
```powershell
ccl -Project . -SkipStandards fda-21-cfr-11
```

### Tier 3: Available

**Not applied unless explicitly added with `-AddStandards`.**

Use for situationally applicable standards.

```yaml
standards:
  available:
    - cmmc-l2
    - itar
    - as9100-rev-d
```

Add for a run:
```powershell
ccl -Project . -AddStandards cmmc-l2,itar
```

---

## Using Standards

### List Available Standards

```powershell
ccl -Standards list
```

Output:
```
Available Compliance Standards
==============================

Quality Management:
  iso-9001-2015    ISO 9001:2015 Quality Management Systems
  iso-13485-2016   ISO 13485:2016 Medical Device QMS

Cybersecurity:
  cmmc-l1          CMMC Level 1 (17 practices)
  cmmc-l2          CMMC Level 2 (110 practices)
  ...
```

### Get Standard Details

```powershell
ccl -Standards info -Standard cmmc-l2
```

Output:
```
CMMC Level 2
============
Version: 2.0
Category: Cybersecurity
Controls: 110

Domains:
  AC - Access Control (22 controls)
  AU - Audit and Accountability (9 controls)
  ...
```

### Apply Standards to Review

```powershell
# Add specific standards
ccl -Project . -AddStandards cmmc-l2,itar

# Use a profile
ccl -Project . -Profile defense-medical

# Skip default standards
ccl -Project . -SkipStandards fda-21-cfr-11
```

### Map Existing Findings

```powershell
ccl -Map ".code-conclave/reviews" -Standard cmmc-l2
```

---

## Standard Profiles

Profiles are pre-defined bundles of standards for common scenarios.

### Built-in Profiles

| Profile | Description | Standards |
|---------|-------------|-----------|
| `defense-medical` | Medical devices for DoD | cmmc-l2, itar, fda-21-cfr-11, iso-13485 |
| `aerospace` | Aerospace manufacturing | as9100-rev-d, itar |
| `medical-device` | FDA-regulated devices | fda-21-cfr-11, fda-820-qsr, iso-13485, iso-14971 |
| `internal-tools` | Internal projects | (none - only required) |

### Using Profiles

```powershell
ccl -Project . -Profile defense-medical
```

### Custom Profiles

Define in config:

```yaml
standards:
  profiles:
    my-profile:
      description: "Custom profile for our needs"
      standards:
        - iso-9001-2015
        - cmmc-l2
        - custom-internal
```

---

## Finding-to-Control Mapping

### How Mapping Works

Each standard defines mapping rules:

```yaml
# cmmc-l2.yaml
controls:
  - id: AC.L2-3.1.1
    title: Authorized Access Control
    domain: Access Control
    mappings:
      agents:
        - guardian
      keywords:
        - authentication
        - authorization
        - access control
        - permission
```

When GUARDIAN finds an issue tagged with `authentication`, it maps to `AC.L2-3.1.1`.

### Compliance Report Output

```markdown
## CMMC Level 2 Compliance Mapping

### AC - Access Control

| Control | Title | Findings |
|---------|-------|----------|
| AC.L2-3.1.1 | Authorized Access Control | GUA-001, GUA-003 |
| AC.L2-3.1.2 | Transaction Control | - |
| AC.L2-3.1.3 | Flow Control | GUA-005 |

### Compliance Summary

- Total Controls: 110
- Controls with Findings: 23
- Controls Clear: 87
- Coverage: 21%
```

### Gap Analysis

Controls without mapped findings may indicate:

1. **Good**: No issues in that area
2. **Gap**: Area not covered by review
3. **Scope**: Control not applicable to this project

---

## Custom Standards

### Creating a Custom Standard

1. Create standard definition file:

```yaml
# core/standards/custom/my-standard.yaml
metadata:
  id: my-standard
  name: My Custom Standard
  version: "1.0"
  category: custom
  description: Custom compliance standard for our organization

domains:
  - id: SEC
    name: Security
    description: Security controls
  - id: QA
    name: Quality
    description: Quality controls

controls:
  - id: SEC-001
    domain: SEC
    title: Input Validation
    description: All user input must be validated
    mappings:
      agents:
        - guardian
      keywords:
        - input validation
        - sanitization
        - injection
        
  - id: QA-001
    domain: QA
    title: Test Coverage
    description: Code must have adequate test coverage
    mappings:
      agents:
        - sentinel
      keywords:
        - test coverage
        - unit test
        - testing
```

2. Add to available standards:

```yaml
# .code-conclave/config.yaml
standards:
  available:
    - my-standard
```

3. Use in review:

```powershell
ccl -Project . -AddStandards my-standard
```

### Standard Schema

```yaml
metadata:
  id: string          # Unique identifier
  name: string        # Display name
  version: string     # Standard version
  category: string    # Grouping category
  description: string # Brief description

domains:
  - id: string        # Domain code
    name: string      # Domain name
    description: string

controls:
  - id: string        # Control ID
    domain: string    # Domain reference
    title: string     # Control title
    description: string
    mappings:
      agents:         # Which agents can map to this
        - sentinel
        - guardian
      keywords:       # Keywords that trigger mapping
        - keyword1
        - keyword2
      severity:       # Minimum severity to map
        - high
        - blocker
```

---

## Standard Control Categories

### Access Control (AC)
- Authentication
- Authorization
- Session management
- Privilege escalation

### Audit (AU)
- Logging
- Audit trails
- Event correlation
- Log protection

### Configuration Management (CM)
- Change control
- Baseline configuration
- Security settings

### Identification (IA)
- User identification
- Device identification
- Credential management

### Incident Response (IR)
- Incident detection
- Response procedures
- Recovery

### Maintenance (MA)
- System maintenance
- Patching
- Update procedures

### Media Protection (MP)
- Data encryption
- Media handling
- Data disposal

### Personnel Security (PS)
- Access agreements
- Termination procedures

### Risk Assessment (RA)
- Vulnerability scanning
- Risk analysis

### Security Assessment (CA)
- Security testing
- Compliance verification

### System Protection (SC)
- Boundary protection
- Cryptography
- Secure communications

---

*Last updated: 2025-02-04*
