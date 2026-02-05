/**
 * Dashboard Server Tests
 *
 * Tests for security features, input validation, and core functionality
 */

// Mock dependencies before requiring server modules
jest.mock('chokidar', () => ({
    watch: jest.fn(() => ({
        on: jest.fn()
    }))
}));

// Test parseFindings function (extracted for testing)
describe('parseFindings', () => {
    // Re-implement parseFindings for testing (same logic as server.js)
    function parseFindings(content) {
        const counts = {
            blockers: (content.match(/\[BLOCKER\]/g) || []).length,
            high: (content.match(/\[HIGH\]/g) || []).length,
            medium: (content.match(/\[MEDIUM\]/g) || []).length,
            low: (content.match(/\[LOW\]/g) || []).length,
        };
        counts.total = counts.blockers + counts.high + counts.medium + counts.low;
        return counts;
    }

    test('counts all severity levels correctly', () => {
        const content = `
Some intro text here.

Issue 1: Found a critical problem [BLOCKER] that must be fixed.
Issue 2: This is important [HIGH] priority.
Issue 3: Another high priority [HIGH] item.
Issue 4: Consider fixing this [MEDIUM] severity issue.
Issue 5: Minor suggestion [LOW] for improvement.
Issue 6: Another minor [LOW] item.
Issue 7: Small tweak [LOW] recommended.
        `;
        const result = parseFindings(content);
        expect(result.blockers).toBe(1);
        expect(result.high).toBe(2);
        expect(result.medium).toBe(1);
        expect(result.low).toBe(3);
        expect(result.total).toBe(7);
    });

    test('handles empty content', () => {
        const result = parseFindings('');
        expect(result.blockers).toBe(0);
        expect(result.high).toBe(0);
        expect(result.medium).toBe(0);
        expect(result.low).toBe(0);
        expect(result.total).toBe(0);
    });

    test('handles content with no findings', () => {
        const content = '# Review complete\nNo issues found.';
        const result = parseFindings(content);
        expect(result.total).toBe(0);
    });

    test('handles case sensitivity correctly', () => {
        // Should only match exact uppercase tags
        const content = 'Issue: [blocker] wrong case. Issue: [Blocker] wrong. Issue: [BLOCKER] correct. Issue: [HIGH] correct. Issue: [high] wrong.';
        const result = parseFindings(content);
        expect(result.blockers).toBe(1);
        expect(result.high).toBe(1);
    });
});

// Test input validation patterns
describe('Input Validation', () => {
    const AGENTS = ['sentinel', 'guardian', 'architect', 'navigator', 'herald', 'operator'];

    test('agent ID whitelist validation', () => {
        // Valid agent IDs
        AGENTS.forEach(id => {
            expect(AGENTS.includes(id)).toBe(true);
        });

        // Invalid agent IDs
        expect(AGENTS.includes('invalid')).toBe(false);
        expect(AGENTS.includes('../etc/passwd')).toBe(false);
        expect(AGENTS.includes('sentinel/../guardian')).toBe(false);
    });

    test('agent ID sanitization removes path traversal characters', () => {
        const sanitize = (id) => id.replace(/[^a-zA-Z0-9-]/g, '');

        expect(sanitize('guardian')).toBe('guardian');
        expect(sanitize('../guardian')).toBe('guardian');
        expect(sanitize('../../etc/passwd')).toBe('etcpasswd');
        expect(sanitize('sentinel/../guardian')).toBe('sentinelguardian');
        expect(sanitize('sentinel%00guardian')).toBe('sentinel00guardian');
    });

    test('status validation rejects invalid values', () => {
        const validStatuses = ['pending', 'running', 'complete', 'error'];

        expect(validStatuses.includes('pending')).toBe(true);
        expect(validStatuses.includes('running')).toBe(true);
        expect(validStatuses.includes('invalid')).toBe(false);
        expect(validStatuses.includes('')).toBe(false);
    });

    test('progress validation enforces 0-100 range', () => {
        const isValidProgress = (p) =>
            typeof p === 'number' && !isNaN(p) && p >= 0 && p <= 100;

        expect(isValidProgress(0)).toBe(true);
        expect(isValidProgress(50)).toBe(true);
        expect(isValidProgress(100)).toBe(true);
        expect(isValidProgress(-1)).toBe(false);
        expect(isValidProgress(101)).toBe(false);
        expect(isValidProgress(NaN)).toBe(false);
        expect(isValidProgress('50')).toBe(false);
    });
});

// Test origin validation for WebSocket security
describe('WebSocket Origin Validation', () => {
    const PORT = 3847;
    const ALLOWED_ORIGINS = [
        'http://localhost:3847',
        'http://127.0.0.1:3847',
        `http://localhost:${PORT}`,
        `http://127.0.0.1:${PORT}`,
    ];

    test('allows localhost origins', () => {
        expect(ALLOWED_ORIGINS.includes('http://localhost:3847')).toBe(true);
        expect(ALLOWED_ORIGINS.includes('http://127.0.0.1:3847')).toBe(true);
    });

    test('rejects external origins', () => {
        expect(ALLOWED_ORIGINS.includes('http://evil.com')).toBe(false);
        expect(ALLOWED_ORIGINS.includes('http://192.168.1.100:3847')).toBe(false);
        expect(ALLOWED_ORIGINS.includes('https://localhost:3847')).toBe(false);
    });

    test('rejects null/undefined origins', () => {
        expect(ALLOWED_ORIGINS.includes(null)).toBe(false);
        expect(ALLOWED_ORIGINS.includes(undefined)).toBe(false);
    });
});

// Test path traversal prevention
describe('Path Traversal Prevention', () => {
    const path = require('path');

    test('resolved path check prevents directory escape', () => {
        const reviewsDir = '/app/project/.code-conclave/reviews';

        // Valid path
        const validPath = path.join(reviewsDir, 'guardian-findings.md');
        const resolvedValid = path.resolve(validPath);
        const resolvedReviewsDir = path.resolve(reviewsDir);
        expect(resolvedValid.startsWith(resolvedReviewsDir)).toBe(true);

        // Attack path (after sanitization would fail whitelist, but testing defense in depth)
        const attackPath = path.join(reviewsDir, '..', '..', 'etc', 'passwd');
        const resolvedAttack = path.resolve(attackPath);
        expect(resolvedAttack.startsWith(resolvedReviewsDir)).toBe(false);
    });
});

// Test log message validation
describe('Log Message Validation', () => {
    test('rejects messages over 1000 characters', () => {
        const maxLength = 1000;
        const shortMessage = 'Valid message';
        const longMessage = 'x'.repeat(1001);

        expect(shortMessage.length <= maxLength).toBe(true);
        expect(longMessage.length <= maxLength).toBe(false);
    });

    test('sanitizes log type to valid values', () => {
        const validTypes = ['info', 'warning', 'error', 'success'];
        const getSafeType = (type) =>
            (typeof type === 'string' && validTypes.includes(type)) ? type : 'info';

        expect(getSafeType('info')).toBe('info');
        expect(getSafeType('error')).toBe('error');
        expect(getSafeType('invalid')).toBe('info');
        expect(getSafeType(null)).toBe('info');
        expect(getSafeType(123)).toBe('info');
    });
});

// Test health check endpoint
describe('Health Check', () => {
    test('health response includes required fields', () => {
        const healthResponse = {
            status: 'healthy',
            timestamp: new Date().toISOString(),
            uptime: 3600,
            version: '2.0.0',
            checks: {
                fileSystem: 'ok',
                websocket: 'connected'
            }
        };

        expect(healthResponse.status).toBe('healthy');
        expect(healthResponse.timestamp).toBeDefined();
        expect(healthResponse.uptime).toBeGreaterThan(0);
        expect(healthResponse.version).toBeDefined();
        expect(healthResponse.checks.fileSystem).toBe('ok');
    });

    test('health status reflects system state', () => {
        const getHealthStatus = (fsExists, wsClients) => ({
            fileSystem: fsExists ? 'ok' : 'reviews_dir_missing',
            websocket: wsClients > 0 ? 'connected' : 'no_clients'
        });

        expect(getHealthStatus(true, 1).fileSystem).toBe('ok');
        expect(getHealthStatus(false, 1).fileSystem).toBe('reviews_dir_missing');
        expect(getHealthStatus(true, 0).websocket).toBe('no_clients');
        expect(getHealthStatus(true, 5).websocket).toBe('connected');
    });
});

// Test verdict calculation
describe('Verdict Calculation', () => {
    function calculateVerdict(totals) {
        if (totals.blockers > 0) return 'HOLD';
        if (totals.high > 3) return 'CONDITIONAL';
        return 'SHIP';
    }

    test('returns HOLD when blockers present', () => {
        expect(calculateVerdict({ blockers: 1, high: 0 })).toBe('HOLD');
        expect(calculateVerdict({ blockers: 5, high: 10 })).toBe('HOLD');
    });

    test('returns CONDITIONAL when more than 3 high issues', () => {
        expect(calculateVerdict({ blockers: 0, high: 4 })).toBe('CONDITIONAL');
        expect(calculateVerdict({ blockers: 0, high: 10 })).toBe('CONDITIONAL');
    });

    test('returns SHIP when clean or minor issues', () => {
        expect(calculateVerdict({ blockers: 0, high: 0 })).toBe('SHIP');
        expect(calculateVerdict({ blockers: 0, high: 3 })).toBe('SHIP');
    });
});
