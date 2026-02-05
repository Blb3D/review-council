# Agent Reference

Detailed reference for all Code Conclave review agents.

---

## Table of Contents

- [Overview](#overview)
- [Agent Summary](#agent-summary)
- [SENTINEL - Quality Assurance](#sentinel---quality-assurance)
- [GUARDIAN - Security](#guardian---security)
- [ARCHITECT - Code Health](#architect---code-health)
- [NAVIGATOR - User Experience](#navigator---user-experience)
- [HERALD - Documentation](#herald---documentation)
- [OPERATOR - Production Readiness](#operator---production-readiness)
- [Custom Agents](#custom-agents)
- [Agent Contracts](#agent-contracts)

---

## Overview

Code Conclave deploys specialized AI agents, each focusing on a specific aspect of code quality. Each agent:

- Has a defined mission and focus areas
- Follows the shared CONTRACTS for output format
- Produces a structured findings report
- Assigns severity levels to issues
- Provides remediation suggestions

### Why Multiple Agents?

A single reviewer can't be equally expert in security, testing, UX, and operations. By deploying specialized agents, you get:

- **Depth**: Each agent goes deep in their domain
- **Coverage**: Nothing falls through the cracks
- **Consistency**: Same checklist every time
- **Speed**: Parallel execution (optional)

---

## Agent Summary

| Agent | Role | Default Tier | Key Questions |
|-------|------|-------------|---------------|
| **SENTINEL** | Quality Assurance | primary | Are there enough tests? Will this break in production? |
| **GUARDIAN** | Security | primary | Can this be exploited? Are secrets exposed? |
| **ARCHITECT** | Code Health | primary | Is this maintainable? Is there tech debt? |
| **NAVIGATOR** | User Experience | lite | Can users figure this out? Is it accessible? |
| **HERALD** | Documentation | lite | Can someone understand this code? |
| **OPERATOR** | Production | lite | Can we deploy this safely? Can we debug it? |

### Model Tiering

Each agent is assigned a **tier** that determines which AI model it uses:

- **primary**: Uses the full model (e.g., Sonnet 4, GPT-4o). Best for tasks requiring deep reasoning.
- **lite**: Uses a smaller, cheaper model (e.g., Haiku 4.5, GPT-4o-mini). Effective for pattern-based tasks.

Tiers are configurable per agent in your project config. See the [Cost Optimization Guide](COST-OPTIMIZATION.md) for details.

---

## SENTINEL - Quality Assurance

### Mission

Assess test coverage, quality gates, and regression risk.

### Focus Areas

1. **Test Coverage**
   - Unit test coverage percentage
   - Critical path coverage
   - Edge case handling

2. **Test Quality**
   - Test isolation
   - Flaky test detection
   - Meaningful assertions

3. **Regression Risk**
   - Breaking change detection
   - API contract violations
   - Database migration risks

4. **Quality Gates**
   - Linting compliance
   - Code complexity
   - Build stability

### What SENTINEL Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | Critical business logic with 0% test coverage |
| HIGH | Payment processing untested |
| MEDIUM | Missing edge case tests |
| LOW | Test naming conventions |

### Default Tier: primary

SENTINEL uses the primary (full) model because test coverage analysis and regression risk assessment require deep reasoning about code behavior.

To override:

```yaml
agents:
  sentinel:
    tier: lite    # Not recommended — may miss subtle coverage gaps
```

### Configuration

```yaml
agents:
  sentinel:
    enabled: true
    tier: primary                 # "primary" or "lite"
    coverage_target: 80           # Minimum coverage %
    complexity_threshold: 15      # Max cyclomatic complexity
```

### Example Finding

```markdown
## Finding: SEN-001
**Severity:** [HIGH]
**Title:** Payment service has no unit tests
**File:** `backend/services/payment_service.py`
**Line:** 1-145

### Evidence
```python
class PaymentService:
    def process_payment(self, amount, card_token):
        # Complex payment logic with no test coverage
        ...
```

### Remediation
Add unit tests covering:
- Successful payment flow
- Invalid card token handling
- Network timeout scenarios
- Refund processing
```

---

## GUARDIAN - Security

### Mission

Identify security vulnerabilities, authentication issues, and data exposure risks.

### Focus Areas

1. **Input Validation**
   - SQL injection
   - XSS vulnerabilities
   - Command injection
   - Path traversal

2. **Authentication & Authorization**
   - Weak authentication
   - Missing authorization checks
   - Session management issues

3. **Data Protection**
   - Hardcoded secrets
   - Sensitive data exposure
   - Insecure storage

4. **Dependencies**
   - Known vulnerable packages
   - Outdated dependencies
   - Supply chain risks

### What GUARDIAN Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | SQL injection in login |
| HIGH | Hardcoded API keys |
| MEDIUM | Missing rate limiting |
| LOW | Verbose error messages |

### Default Tier: primary

GUARDIAN uses the primary (full) model because security vulnerability detection requires deep understanding of attack vectors and code context.

To override:

```yaml
agents:
  guardian:
    tier: lite    # Not recommended — may miss subtle vulnerabilities
```

### Configuration

```yaml
agents:
  guardian:
    enabled: true
    tier: primary                 # "primary" or "lite"
    scan_dependencies: true       # Check for vulnerable deps
    check_secrets: true           # Scan for hardcoded secrets
    severity_threshold: medium    # Minimum severity to report
```

### Example Finding

```markdown
## Finding: GUA-001
**Severity:** [BLOCKER]
**Title:** SQL Injection vulnerability in user search
**File:** `backend/api/users.py`
**Line:** 45

### Evidence
```python
def search_users(query):
    # VULNERABLE: Direct string interpolation
    sql = f"SELECT * FROM users WHERE name LIKE '%{query}%'"
    return db.execute(sql)
```

### Remediation
Use parameterized queries:
```python
def search_users(query):
    sql = "SELECT * FROM users WHERE name LIKE ?"
    return db.execute(sql, (f"%{query}%",))
```
```

---

## ARCHITECT - Code Health

### Mission

Evaluate code structure, design patterns, dependencies, and technical debt.

### Focus Areas

1. **Code Structure**
   - File organization
   - Module boundaries
   - Separation of concerns

2. **Design Patterns**
   - Pattern misuse
   - Anti-patterns
   - Consistency

3. **Dependencies**
   - Circular dependencies
   - Tight coupling
   - Dependency injection

4. **Technical Debt**
   - Code duplication
   - Dead code
   - TODO/FIXME comments

### What ARCHITECT Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | Circular dependency breaking builds |
| HIGH | God class with 50+ methods |
| MEDIUM | Duplicated business logic |
| LOW | Inconsistent naming conventions |

### Default Tier: primary

ARCHITECT uses the primary (full) model because evaluating code structure, detecting anti-patterns, and assessing technical debt require thorough architectural reasoning.

To override:

```yaml
agents:
  architect:
    tier: lite    # Acceptable for smaller projects with simple architecture
```

### Configuration

```yaml
agents:
  architect:
    enabled: true
    tier: primary                 # "primary" or "lite"
    max_file_size: 500            # Flag files over N lines
    check_circular_deps: true     # Detect circular dependencies
```

### Example Finding

```markdown
## Finding: ARC-001
**Severity:** [HIGH]
**Title:** God class violates single responsibility
**File:** `backend/services/order_service.py`
**Line:** 1-850

### Evidence
```python
class OrderService:
    # 850 lines, 45 methods
    # Handles: orders, payments, shipping, notifications, reports
```

### Remediation
Extract into focused services:
- `OrderService` - Order CRUD operations
- `PaymentService` - Payment processing
- `ShippingService` - Shipping calculations
- `NotificationService` - Email/SMS notifications
```

---

## NAVIGATOR - User Experience

### Mission

Identify UX friction points, accessibility issues, and user-facing problems.

### Focus Areas

1. **Error Handling**
   - User-friendly error messages
   - Recovery guidance
   - Error boundaries

2. **Accessibility**
   - WCAG compliance
   - Screen reader support
   - Keyboard navigation

3. **Usability**
   - Confusing workflows
   - Missing feedback
   - Inconsistent UI

4. **Performance**
   - Slow interactions
   - Loading states
   - Perceived performance

### What NAVIGATOR Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | Form submission with no feedback |
| HIGH | Missing alt text on critical images |
| MEDIUM | Confusing error message |
| LOW | Inconsistent button styling |

### Default Tier: lite

NAVIGATOR uses the lite model by default. UX pattern detection, accessibility checks, and UI consistency reviews are effective with smaller models.

To override:

```yaml
agents:
  navigator:
    tier: primary    # Use for projects with complex accessibility requirements
```

### Configuration

```yaml
agents:
  navigator:
    enabled: true
    tier: lite                    # "primary" or "lite"
    accessibility_level: "AA"     # WCAG level: A, AA, AAA
    check_mobile: true            # Check mobile responsiveness
```

### Example Finding

```markdown
## Finding: NAV-001
**Severity:** [HIGH]
**Title:** Form lacks error feedback
**File:** `frontend/components/LoginForm.tsx`
**Line:** 45-78

### Evidence
```tsx
const handleSubmit = async () => {
    try {
        await login(credentials);
        navigate('/dashboard');
    } catch (e) {
        // Error swallowed - user sees nothing
    }
};
```

### Remediation
Add error state and display:
```tsx
const [error, setError] = useState<string | null>(null);

const handleSubmit = async () => {
    setError(null);
    try {
        await login(credentials);
        navigate('/dashboard');
    } catch (e) {
        setError('Invalid username or password. Please try again.');
    }
};
```
```

---

## HERALD - Documentation

### Mission

Assess documentation completeness, accuracy, and accessibility.

### Focus Areas

1. **Code Documentation**
   - Function/method docs
   - Complex logic explanations
   - Type annotations

2. **Project Documentation**
   - README completeness
   - Setup instructions
   - Architecture docs

3. **API Documentation**
   - Endpoint documentation
   - Request/response examples
   - Error codes

4. **Changelog & History**
   - Version history
   - Breaking changes
   - Migration guides

### What HERALD Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | No setup instructions, project won't build |
| HIGH | Public API undocumented |
| MEDIUM | Outdated README |
| LOW | Missing inline comments |

### Default Tier: lite

HERALD uses the lite model by default. Documentation completeness and accuracy checks are largely pattern-based and work well with smaller models.

To override:

```yaml
agents:
  herald:
    tier: primary    # Use for projects with strict documentation standards
```

### Configuration

```yaml
agents:
  herald:
    enabled: true
    tier: lite                    # "primary" or "lite"
    required_docs:
      - "README.md"
      - "CHANGELOG.md"
    api_docs_required: true       # Require API documentation
```

### Example Finding

```markdown
## Finding: HER-001
**Severity:** [HIGH]
**Title:** Public API endpoint undocumented
**File:** `backend/api/v1/orders.py`
**Line:** 1-50

### Evidence
```python
@router.post("/orders")
async def create_order(order: OrderCreate):
    # No docstring, no OpenAPI description
    # Parameters not documented
    # Response format unknown
    ...
```

### Remediation
Add comprehensive documentation:
```python
@router.post("/orders", response_model=Order)
async def create_order(order: OrderCreate):
    """
    Create a new order.
    
    Args:
        order: Order creation payload
        
    Returns:
        Created order with generated ID
        
    Raises:
        400: Invalid order data
        401: Not authenticated
        422: Validation error
    """
```
```

---

## OPERATOR - Production Readiness

### Mission

Evaluate deployment safety, observability, and operational concerns.

### Focus Areas

1. **Deployment**
   - CI/CD pipeline health
   - Rollback capability
   - Environment parity

2. **Observability**
   - Logging coverage
   - Metrics exposure
   - Tracing support

3. **Resilience**
   - Health checks
   - Graceful degradation
   - Circuit breakers

4. **Configuration**
   - Environment handling
   - Secret management
   - Feature flags

### What OPERATOR Finds

| Severity | Example Findings |
|----------|------------------|
| BLOCKER | No health check endpoint |
| HIGH | Unstructured logging |
| MEDIUM | Missing retry logic |
| LOW | No graceful shutdown |

### Default Tier: lite

OPERATOR uses the lite model by default. Operations readiness checks (health endpoints, logging, metrics) follow established checklists and work well with smaller models.

To override:

```yaml
agents:
  operator:
    tier: primary    # Use for safety-critical or high-availability systems
```

### Configuration

```yaml
agents:
  operator:
    enabled: true
    tier: lite                    # "primary" or "lite"
    require_health_check: true    # Require /health endpoint
    require_logging: true         # Require structured logging
    require_metrics: true         # Require metrics endpoint
```

### Example Finding

```markdown
## Finding: OPR-001
**Severity:** [BLOCKER]
**Title:** No health check endpoint
**File:** `backend/main.py`
**Line:** N/A

### Evidence
The application has no health check endpoint. Kubernetes/load balancers cannot verify application health.

### Remediation
Add health check endpoint:
```python
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "version": settings.VERSION,
        "checks": {
            "database": await check_db_connection(),
            "cache": await check_redis_connection()
        }
    }
```
```

---

## Custom Agents

### Creating a Custom Agent

1. Create agent instruction file:

```markdown
# CUSTOM - Your Agent Name

## Identity
You are CUSTOM, the [role] agent in the Code Conclave system.

## Mission
Assess [specific aspect] for release readiness.

## Focus Areas
1. [Area 1]
2. [Area 2]
3. [Area 3]

## Review Process
1. Scan for [what to look for]
2. Evaluate [criteria]
3. Identify [issues]

## Severity Guidelines
- BLOCKER: [criteria]
- HIGH: [criteria]
- MEDIUM: [criteria]
- LOW: [criteria]

## Output Format
Follow the standard CONTRACTS format.
```

2. Save to one of:
   - `core/agents/custom.md` (global)
   - `.code-conclave/agents/custom.md` (project-specific)

3. Run the agent:

```powershell
ccl -Project . -Agent custom
```

### Overriding Built-in Agents

To customize a built-in agent for a specific project:

1. Copy the agent file:
```powershell
Copy-Item "C:\tools\code-conclave\core\agents\sentinel.md" ".code-conclave\agents\sentinel.md"
```

2. Edit the copy to customize behavior

3. Run normally - project version takes precedence

---

## Agent Contracts

All agents follow the shared CONTRACTS defined in `CONTRACTS.md`:

### Severity Definitions

| Level | Impact | Action |
|-------|--------|--------|
| **BLOCKER** | Cannot ship | Must fix before release |
| **HIGH** | Significant risk | Should fix before release |
| **MEDIUM** | Notable issue | Consider fixing |
| **LOW** | Polish item | Nice to have |

### Output Format

```markdown
# {AGENT} Findings Report

## Finding: {AGENT_PREFIX}-{NNN}
**Severity:** [{LEVEL}]
**Title:** {Brief description}
**File:** `{path/to/file}`
**Line:** {line number or range}

### Evidence
{Code snippet or description}

### Remediation
{How to fix}

---

## Summary

| Severity | Count |
|----------|-------|
| BLOCKER | N |
| HIGH | N |
| MEDIUM | N |
| LOW | N |

## Verdict

{SHIP | CONDITIONAL | HOLD}

{Justification}
```

### Verdict Rules

```
SHIP:        0 blockers AND ≤3 high
CONDITIONAL: 0 blockers AND >3 high
HOLD:        Any blockers
```

---

*Last updated: 2026-02-05*
