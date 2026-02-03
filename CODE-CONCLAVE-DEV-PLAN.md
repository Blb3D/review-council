# Code Conclave Development Plan

**Status:** ACTIVE DEVELOPMENT
**Location:** C:\repos\code-conclave (to be created from review-council)
**Coordination:** Claude.ai + VS Claude

---

## Phase 1: Repository Restructure

### TASK-001: Create New Repository Structure
**Assignee:** VS Claude
**Priority:** BLOCKER
**Effort:** 30 min

Create the following structure from existing review-council repo:

```
C:\repos\code-conclave\
├── core\
│   ├── agents\
│   │   ├── sentinel.md
│   │   ├── guardian.md
│   │   ├── architect.md
│   │   ├── navigator.md
│   │   ├── herald.md
│   │   └── operator.md
│   ├── standards\
│   │   ├── core\
│   │   │   └── .gitkeep
│   │   └── regulated\
│   │       ├── cybersecurity\
│   │       ├── aerospace\
│   │       ├── medical\
│   │       ├── laboratory\
│   │       └── environmental\
│   ├── mappings\
│   │   └── .gitkeep
│   ├── templates\
│   │   └── .gitkeep
│   └── schemas\
│       ├── finding.schema.json
│       └── verdict.schema.json
├── cli\
│   ├── ccl.ps1
│   ├── commands\
│   │   ├── run.ps1
│   │   ├── agent.ps1
│   │   ├── report.ps1
│   │   └── map.ps1
│   ├── providers\
│   │   ├── anthropic.ps1
│   │   └── provider-base.ps1
│   └── config\
│       └── ccl.config.example.yaml
├── vscode\
│   └── .gitkeep  (Phase 3)
├── dashboard\
│   ├── server.js
│   ├── index.html
│   └── package.json
├── shared\
│   └── .gitkeep
├── docs\
│   ├── README.md
│   ├── AGENTS.md
│   ├── STANDARDS.md
│   └── CLI.md
├── examples\
│   └── sample-output\
├── .gitignore
├── LICENSE
└── README.md
```

**Actions:**
1. Copy C:\repos\review-council to C:\repos\code-conclave
2. Create directory structure above
3. Move agents/*.md to core/agents/
4. Move dashboard files to dashboard/
5. Refactor Start-ReviewCouncil.ps1 → cli/ccl.ps1
6. Update all "Review Council" references to "Code Conclave"
7. Update all ".review-council" references to ".code-conclave"

---

### TASK-002: Update Branding in Dashboard
**Assignee:** VS Claude
**Priority:** HIGH
**Effort:** 15 min
**Depends on:** TASK-001

Files to update:
- `dashboard/index.html`
  - Title: "Code Conclave" 
  - Header: "Code Conclave - AI-Powered Code Review"
  - Any "Review Council" text
- `dashboard/server.js`
  - Console logs
  - Any branding references

---

### TASK-003: Update Agent File Headers
**Assignee:** VS Claude
**Priority:** MEDIUM
**Effort:** 15 min
**Depends on:** TASK-001

Update each agent in core/agents/:
- Change any "Review Council" references to "Code Conclave"
- Ensure consistent header format:

```markdown
# AGENT_NAME - Code Conclave

## Role
[description]

## Scope
[what to review]

## Standards
[frameworks referenced]

## Output Format
[finding structure]
```

---

## Phase 2: Compliance Pack Foundation

### TASK-004: Create Standard Schema
**Assignee:** VS Claude
**Priority:** HIGH
**Effort:** 30 min

Create `core/schemas/standard.schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "name", "domain", "version", "controls"],
  "properties": {
    "id": { "type": "string" },
    "name": { "type": "string" },
    "domain": { "type": "string" },
    "version": { "type": "string" },
    "description": { "type": "string" },
    "controls": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "title", "agents"],
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "description": { "type": "string" },
          "agents": { "type": "array", "items": { "type": "string" } },
          "finding_patterns": { "type": "array", "items": { "type": "string" } }
        }
      }
    },
    "mappings": { "type": "object" }
  }
}
```

---

### TASK-005: Create CMMC Level 2 Pack
**Assignee:** Claude.ai (domain knowledge)
**Priority:** HIGH
**Effort:** 2 hours

Create `core/standards/regulated/cybersecurity/cmmc-l2.yaml`

CMMC Level 2 has 110 practices across 14 domains:
- Access Control (AC)
- Audit and Accountability (AU)
- Awareness and Training (AT)
- Configuration Management (CM)
- Identification and Authentication (IA)
- Incident Response (IR)
- Maintenance (MA)
- Media Protection (MP)
- Personnel Security (PS)
- Physical Protection (PE)
- Risk Assessment (RA)
- Security Assessment (CA)
- System and Communications Protection (SC)
- System and Information Integrity (SI)

Map Code Conclave findings to relevant controls.

---

### TASK-006: Create ISO 13485 Pack
**Assignee:** Claude.ai (domain knowledge)
**Priority:** HIGH
**Effort:** 2 hours

Create `core/standards/regulated/medical/iso-13485.yaml`

Key sections relevant to software:
- 4.1.6 - Software validation
- 7.3 - Design and development
- 7.5.6 - Identification and traceability
- 8.2.4 - Monitoring and measurement

Map Code Conclave findings to relevant controls.

---

### TASK-007: Create FDA 21 CFR Part 820 Pack
**Assignee:** Claude.ai (domain knowledge)
**Priority:** HIGH  
**Effort:** 2 hours

Create `core/standards/regulated/medical/fda-21cfr820.yaml`

Key sections:
- 820.30 - Design Controls
- 820.70 - Production and Process Controls
- 820.75 - Process Validation
- 820.90 - Nonconforming Product
- 820.100 - CAPA

Also include 21 CFR Part 11 (Electronic Records) mappings.

---

## Phase 3: CLI Enhancement

### TASK-008: Refactor CLI to Support Standards
**Assignee:** VS Claude
**Priority:** HIGH
**Effort:** 1 hour
**Depends on:** TASK-001, TASK-004

Update `cli/ccl.ps1` to support:

```powershell
# Existing functionality
ccl run ./project

# New: Run with compliance standard
ccl run ./project --standard cmmc-l2

# New: Map existing findings to standard
ccl map ./project/.code-conclave --standard iso-13485

# New: List available standards
ccl standards list

# New: Show standard details
ccl standards info cmmc-l2
```

**Implementation:**
1. Add `-Standard` parameter to run command
2. Create `commands/map.ps1` for post-hoc mapping
3. Create `commands/standards.ps1` for standard management
4. Load YAML files from core/standards/

---

### TASK-009: Create Mapping Engine
**Assignee:** VS Claude
**Priority:** HIGH
**Effort:** 1 hour
**Depends on:** TASK-005, TASK-006, TASK-007

Create `shared/mapping-engine.ps1` (or .js):

```powershell
function Get-ComplianceMapping {
    param(
        [string]$FindingsPath,
        [string]$StandardId
    )
    
    # 1. Load findings from .code-conclave/
    # 2. Load standard YAML
    # 3. Match findings to controls
    # 4. Generate gap analysis
    # 5. Return structured result
}
```

Output structure:
```json
{
  "standard": "cmmc-l2",
  "coverage": {
    "total_controls": 110,
    "addressed": 45,
    "gaps": 65,
    "percentage": 40.9
  },
  "by_domain": [...],
  "findings_mapped": [...],
  "gaps": [...]
}
```

---

## Phase 4: Report Generation

### TASK-010: Create Report Templates
**Assignee:** VS Claude
**Priority:** MEDIUM
**Effort:** 1 hour

Create templates in `core/templates/`:

1. `executive-summary.md` - One-page verdict + key findings
2. `full-report.md` - All findings, all agents
3. `gap-analysis.md` - Compliance gaps by standard
4. `traceability-matrix.md` - Finding → Control → Evidence

---

### TASK-011: Create Report Generator
**Assignee:** VS Claude
**Priority:** MEDIUM
**Effort:** 1 hour
**Depends on:** TASK-010

Create `cli/commands/report.ps1`:

```powershell
ccl report ./project/.code-conclave --format markdown
ccl report ./project/.code-conclave --format pdf
ccl report ./project/.code-conclave --format excel --template gap-analysis
```

---

## Phase 5: VS Code Extension (Future)

### TASK-012: Scaffold VS Code Extension
**Assignee:** TBD
**Priority:** LOW (after CLI stable)
**Effort:** 4 hours

Use Yeoman generator:
```bash
npx yo code
```

Create basic extension with:
- Chat Participants (@conclave, @sentinel, etc.)
- Settings for provider selection
- Command palette integration

---

## Task Assignment Summary

| Task | Assignee | Status | Priority |
|------|----------|--------|----------|
| TASK-001: Repo Structure | VS Claude | DONE | BLOCKER |
| TASK-002: Dashboard Branding | VS Claude | DONE (in TASK-001) | HIGH |
| TASK-003: Agent Headers | VS Claude | DONE (in TASK-001) | MEDIUM |
| TASK-004: Standard Schema | VS Claude | DONE | HIGH |
| TASK-005: CMMC L2 Pack | Claude.ai | TODO | HIGH |
| TASK-006: ISO 13485 Pack | Claude.ai | TODO | HIGH |
| TASK-007: FDA 820 Pack | Claude.ai | TODO | HIGH |
| TASK-008: CLI Standards Support | VS Claude | TODO | HIGH |
| TASK-009: Mapping Engine | VS Claude | TODO | HIGH |
| TASK-010: Report Templates | VS Claude | TODO | MEDIUM |
| TASK-011: Report Generator | VS Claude | TODO | MEDIUM |
| TASK-012: VS Code Extension | TBD | BACKLOG | LOW |

---

## Coordination Notes

**VS Claude Focus:**
- Repository structure
- Code refactoring
- CLI implementation
- Dashboard updates

**Claude.ai Focus:**
- Compliance pack content (domain knowledge)
- Standards research
- Control mappings
- Documentation

**Handoff Points:**
1. VS Claude creates structure → Claude.ai populates standards
2. Claude.ai defines schema → VS Claude implements parser
3. VS Claude builds CLI → Claude.ai tests with real standards

---

## Definition of Done

### MVP (Ship to first customer):
- [ ] Repo restructured with code-conclave branding
- [ ] CLI runs with `--standard` flag
- [ ] At least 1 compliance pack complete (CMMC L2)
- [ ] Gap analysis output works
- [ ] Basic documentation

### v1.0:
- [ ] 3+ compliance packs (CMMC, ISO 13485, FDA 820)
- [ ] PDF report generation
- [ ] Evidence package bundler
- [ ] Landing page + Stripe

### v1.1:
- [ ] VS Code extension (Copilot integration)
- [ ] Additional packs (SOC 2, AS9100D)
- [ ] CI/CD integration examples
