"""Agent definitions, loading, and mock findings.

Defines the 6 review agents and their properties.
"""

from __future__ import annotations

from importlib import resources
from pathlib import Path
from typing import Optional

AGENT_DEFS: dict[str, dict] = {
    "guardian": {"name": "GUARDIAN", "role": "Security", "color": "red"},
    "sentinel": {"name": "SENTINEL", "role": "Quality & Testing", "color": "yellow"},
    "architect": {"name": "ARCHITECT", "role": "Code Health", "color": "blue"},
    "navigator": {"name": "NAVIGATOR", "role": "UX & Workflows", "color": "green"},
    "herald": {"name": "HERALD", "role": "Documentation", "color": "magenta"},
    "operator": {"name": "OPERATOR", "role": "Production Readiness", "color": "cyan"},
}

ALL_AGENT_KEYS = list(AGENT_DEFS.keys())
FREE_AGENT_KEYS = ["guardian", "sentinel"]


def load_agent_instructions(agent_key: str, project_path: Optional[Path] = None) -> str:
    """Load agent instruction markdown.

    Checks project-specific override first, then falls back to bundled data.
    """
    # Check project-specific override
    if project_path:
        override = project_path / ".code-conclave" / "agents" / f"{agent_key}.md"
        if override.exists():
            return override.read_text(encoding="utf-8")

    # Load from bundled package data
    try:
        data_pkg = resources.files("conclave.data.agents")
        agent_file = data_pkg / f"{agent_key}.md"
        return agent_file.read_text(encoding="utf-8")
    except Exception:
        return f"# {agent_key.upper()} Agent\n\nReview the code for issues in your domain.\n"


def load_contracts(project_path: Optional[Path] = None) -> str:
    """Load CONTRACTS.md (output format spec).

    Checks project-specific override first, then falls back to bundled data.
    """
    if project_path:
        override = project_path / ".code-conclave" / "CONTRACTS.md"
        if override.exists():
            return override.read_text(encoding="utf-8")

    try:
        data_pkg = resources.files("conclave.data")
        return (data_pkg / "contracts.md").read_text(encoding="utf-8")
    except Exception:
        return "# Output Format\n\nUse ### AGENT-NNN: Title [SEVERITY] format.\n"


# ---------------------------------------------------------------------------
# Mock findings for DryRun mode
# ---------------------------------------------------------------------------

MOCK_FINDINGS: dict[str, str] = {
    "guardian": """# GUARDIAN Security Review

### GUARDIAN-001: Hardcoded API Key in Configuration [BLOCKER]
**Location:** `src/config.js:42`
**Effort:** S

**Issue:**
API key is hardcoded in source code, exposing credentials to anyone with repo access.

**Evidence:**
```javascript
const API_KEY = "sk-live-abc123def456";
```

**Recommendation:**
Move to environment variable or secrets manager. Use `process.env.API_KEY`.

### GUARDIAN-002: Missing CSRF Protection [HIGH]
**Location:** `src/api/routes.js:15`
**Effort:** M

**Issue:**
POST endpoints lack CSRF token validation, vulnerable to cross-site request forgery.

**Recommendation:**
Add CSRF middleware (e.g., csurf for Express).

### GUARDIAN-003: Verbose Error Messages in Production [MEDIUM]
**Location:** `src/middleware/error.js:8`
**Effort:** S

**Issue:**
Stack traces are returned in error responses, leaking implementation details.

**Recommendation:**
Return generic error messages in production; log details server-side only.

COMPLETE: 1 BLOCKER, 1 HIGH, 1 MEDIUM, 0 LOW
""",
    "sentinel": """# SENTINEL Quality Review

### SENTINEL-001: No Unit Tests for Auth Module [HIGH]
**Location:** `src/auth/`
**Effort:** L

**Issue:**
Authentication module has zero test coverage. Critical path untested.

**Recommendation:**
Add unit tests for login, registration, token refresh, and permission checks.

### SENTINEL-002: Inconsistent Error Handling [MEDIUM]
**Location:** `src/services/`
**Effort:** M

**Issue:**
Some services throw errors, others return null. No consistent pattern.

**Recommendation:**
Standardize error handling: use Result pattern or consistent exception hierarchy.

### SENTINEL-003: Magic Numbers in Business Logic [LOW]
**Location:** `src/services/pricing.js:23`
**Effort:** S

**Issue:**
Hard-coded numeric values without named constants reduce readability.

**Recommendation:**
Extract to named constants (e.g., `MAX_RETRY_COUNT = 3`).

COMPLETE: 0 BLOCKER, 1 HIGH, 1 MEDIUM, 1 LOW
""",
    "architect": """# ARCHITECT Code Health Review

### ARCHITECT-001: God Class Pattern [HIGH]
**Location:** `src/services/OrderService.js`
**Effort:** L

**Issue:**
OrderService handles order creation, payment, shipping, and notifications (800+ lines).

**Recommendation:**
Split into focused services: OrderCreation, PaymentProcessor, ShippingService, NotificationService.

### ARCHITECT-002: Circular Dependency [MEDIUM]
**Location:** `src/models/User.js` <-> `src/models/Order.js`
**Effort:** M

**Issue:**
User imports Order, Order imports User. Creates tight coupling and initialization issues.

**Recommendation:**
Use dependency injection or create a shared interface module.

COMPLETE: 0 BLOCKER, 1 HIGH, 1 MEDIUM, 0 LOW
""",
    "navigator": """# NAVIGATOR UX Review

### NAVIGATOR-001: No Loading State for API Calls [MEDIUM]
**Location:** `src/components/Dashboard.jsx`
**Effort:** S

**Issue:**
Data-fetching components show no feedback while loading. Users see blank screens.

**Recommendation:**
Add loading spinners and skeleton screens for async operations.

### NAVIGATOR-002: Poor Mobile Responsiveness [LOW]
**Location:** `src/styles/layout.css`
**Effort:** M

**Issue:**
Layout breaks below 768px. Navigation overlaps content on mobile.

**Recommendation:**
Add responsive breakpoints and a mobile navigation pattern.

COMPLETE: 0 BLOCKER, 0 HIGH, 1 MEDIUM, 1 LOW
""",
    "herald": """# HERALD Documentation Review

### HERALD-001: Missing API Documentation [MEDIUM]
**Location:** `src/api/`
**Effort:** M

**Issue:**
No endpoint documentation. Developers must read source to understand API contracts.

**Recommendation:**
Add OpenAPI/Swagger spec or JSDoc annotations to all endpoints.

### HERALD-002: Outdated README Setup Instructions [LOW]
**Location:** `README.md`
**Effort:** S

**Issue:**
README references deprecated `npm start` command; project now uses `npm run dev`.

**Recommendation:**
Update setup instructions and verify all commands work from a fresh clone.

COMPLETE: 0 BLOCKER, 0 HIGH, 1 MEDIUM, 1 LOW
""",
    "operator": """# OPERATOR Production Readiness Review

### OPERATOR-001: No Health Check Endpoint [HIGH]
**Location:** `src/server.js`
**Effort:** S

**Issue:**
No /health or /ready endpoint for container orchestration health probes.

**Recommendation:**
Add GET /health returning 200 with uptime and dependency status.

### OPERATOR-002: Missing Structured Logging [MEDIUM]
**Location:** `src/`
**Effort:** M

**Issue:**
Console.log throughout codebase. No structured logging for observability.

**Recommendation:**
Adopt structured logger (e.g., pino, winston) with JSON output for log aggregation.

COMPLETE: 0 BLOCKER, 1 HIGH, 1 MEDIUM, 0 LOW
""",
}
