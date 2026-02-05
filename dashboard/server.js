/**
 * Code Conclave - Live Dashboard Server
 *
 * Watches review output files and broadcasts updates via WebSocket
 *
 * Usage:
 *   node server.js --project "C:\repos\filaops"
 *   node server.js -p "C:\repos\filaops"
 */

const express = require('express');
const { WebSocketServer } = require('ws');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const http = require('http');

// Parse command line args
const args = process.argv.slice(2);
let projectPath = null;

for (let i = 0; i < args.length; i++) {
    if ((args[i] === '--project' || args[i] === '-p') && args[i + 1]) {
        projectPath = args[i + 1];
        break;
    }
}

if (!projectPath) {
    console.log('Usage: node server.js --project "C:\\path\\to\\project"');
    console.log('');
    console.log('The project must have been initialized with ccl -Init');
    process.exit(1);
}

const reviewsDir = path.join(projectPath, '.code-conclave', 'reviews');
const PORT = 3847;

// Agent definitions
const AGENTS = ['sentinel', 'guardian', 'architect', 'navigator', 'herald', 'operator'];

const AGENT_INFO = {
    sentinel:  { name: 'SENTINEL',  role: 'Quality & Compliance', icon: '\u{1F6E1}\uFE0F', color: '#ffaa00' },
    guardian:  { name: 'GUARDIAN',  role: 'Security',             icon: '\u{1F512}', color: '#ff4466' },
    architect: { name: 'ARCHITECT', role: 'Code Health',          icon: '\u{1F3D7}\uFE0F', color: '#00d4ff' },
    navigator: { name: 'NAVIGATOR', role: 'UX Review',            icon: '\u{1F9ED}', color: '#00ff88' },
    herald:    { name: 'HERALD',    role: 'Documentation',        icon: '\u{1F4DC}', color: '#aa66ff' },
    operator:  { name: 'OPERATOR',  role: 'Production Ready',     icon: '\u2699\uFE0F', color: '#ff8844' },
};

// State
let state = {
    project: path.basename(projectPath),
    projectPath: projectPath,
    agents: {},
    logs: [],
    verdict: null,
    startTime: null,
    timeEstimate: null,
};

// Timing tracking
let agentStartTimes = {};
let agentDurations = [];

// Initialize agent states
AGENTS.forEach(id => {
    state.agents[id] = {
        ...AGENT_INFO[id],
        id,
        status: 'pending',
        progress: 0,
        findings: null,
    };
});

// Parse findings from markdown file
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

// Check file and update state
function checkAgentFile(agentId) {
    const filePath = path.join(reviewsDir, `${agentId}-findings.md`);

    if (fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf-8');
        const findings = parseFindings(content);

        // Track duration if we have a start time
        if (agentStartTimes[agentId]) {
            const duration = Date.now() - agentStartTimes[agentId];
            agentDurations.push(duration);
            state.agents[agentId].duration = duration;
        }

        state.agents[agentId].status = 'complete';
        state.agents[agentId].progress = 100;
        state.agents[agentId].findings = findings;

        addLog(`${AGENT_INFO[agentId].name} complete: ${findings.blockers} blocker, ${findings.high} high, ${findings.medium} medium, ${findings.low} low`,
            findings.blockers > 0 ? 'error' : findings.high > 0 ? 'warning' : 'success');

        updateTimeEstimate();
        return true;
    }
    return false;
}

// Detect currently running agent
function detectRunningAgent() {
    // Find first non-complete agent after any complete ones
    let foundComplete = false;
    for (const id of AGENTS) {
        if (state.agents[id].status === 'complete') {
            foundComplete = true;
        } else if (foundComplete && state.agents[id].status === 'pending') {
            state.agents[id].status = 'running';
            state.agents[id].progress = Math.floor(Math.random() * 50) + 25; // Simulated progress
            agentStartTimes[id] = Date.now(); // Track start time
            addLog(`Deploying ${AGENT_INFO[id].name}...`, 'info');
            break;
        }
    }
}

// Calculate time estimate
function updateTimeEstimate() {
    const completedCount = AGENTS.filter(id => state.agents[id].status === 'complete').length;
    const remainingCount = AGENTS.length - completedCount;

    if (agentDurations.length === 0 || remainingCount === 0) {
        state.timeEstimate = null;
        return;
    }

    const avgDuration = agentDurations.reduce((a, b) => a + b, 0) / agentDurations.length;
    const runningAgent = AGENTS.find(id => state.agents[id].status === 'running');

    // Account for time already spent on current agent
    let currentElapsed = 0;
    if (runningAgent && agentStartTimes[runningAgent]) {
        currentElapsed = Date.now() - agentStartTimes[runningAgent];
    }

    const estimatedRemaining = (avgDuration * remainingCount) - currentElapsed;
    state.timeEstimate = Math.max(0, Math.round(estimatedRemaining / 1000)); // seconds
}

// Calculate verdict
function calculateVerdict() {
    const completedCount = AGENTS.filter(id => state.agents[id].status === 'complete').length;

    if (completedCount === AGENTS.length) {
        const totals = AGENTS.reduce((acc, id) => {
            const f = state.agents[id].findings || { blockers: 0, high: 0, medium: 0, low: 0 };
            return {
                blockers: acc.blockers + f.blockers,
                high: acc.high + f.high,
                medium: acc.medium + f.medium,
                low: acc.low + f.low,
            };
        }, { blockers: 0, high: 0, medium: 0, low: 0 });

        state.verdict = totals.blockers > 0 ? 'HOLD' : totals.high > 3 ? 'CONDITIONAL' : 'SHIP';
        addLog(`Review complete! Verdict: ${state.verdict}`,
            state.verdict === 'SHIP' ? 'success' : state.verdict === 'HOLD' ? 'error' : 'warning');
    }
}

// Add log entry
function addLog(message, type = 'info') {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false });
    state.logs.push({ time, message, type });
    if (state.logs.length > 100) state.logs.shift();
}

// Broadcast state to all clients
function broadcast(wss) {
    const message = JSON.stringify({ type: 'state', data: state });
    wss.clients.forEach(client => {
        if (client.readyState === 1) { // OPEN
            client.send(message);
        }
    });
}

// Initial scan
function initialScan() {
    addLog('Code Conclave Dashboard connected', 'info');
    addLog(`Watching: ${projectPath}`, 'info');

    // Check for existing files
    AGENTS.forEach(id => checkAgentFile(id));
    detectRunningAgent();
    calculateVerdict();
}

// Setup Express + WebSocket
const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Security: Allowed origins for WebSocket connections (localhost only)
const ALLOWED_ORIGINS = [
    'http://localhost:3847',
    'http://127.0.0.1:3847',
    `http://localhost:${PORT}`,
    `http://127.0.0.1:${PORT}`,
];

// Serve static files
app.use(express.static(__dirname));

// API endpoint to receive updates from PowerShell
// Security: Limit JSON body size to prevent DoS
app.use(express.json({ limit: '100kb' }));

app.post('/api/log', (req, res) => {
    const { message, type } = req.body;

    // Validate message exists and is a string
    if (!message || typeof message !== 'string') {
        return res.status(400).json({ error: 'Message is required and must be a string' });
    }

    if (message.length > 1000) {
        return res.status(400).json({ error: 'Message too long (max 1000 characters)' });
    }

    // Validate and sanitize type
    const validTypes = ['info', 'warning', 'error', 'success'];
    const safeType = (typeof type === 'string' && validTypes.includes(type)) ? type : 'info';

    addLog(message, safeType);
    broadcast(wss);
    res.json({ ok: true });
});

app.post('/api/agent-status', (req, res) => {
    const { agentId, status, progress } = req.body;

    // Validate agentId exists and is a string
    if (typeof agentId !== 'string' || !AGENTS.includes(agentId)) {
        return res.status(400).json({ error: 'Invalid agent ID' });
    }

    // Validate status
    const validStatuses = ['pending', 'running', 'complete', 'error'];
    if (typeof status !== 'string' || !validStatuses.includes(status)) {
        return res.status(400).json({ error: 'Invalid status' });
    }

    state.agents[agentId].status = status;

    // Validate progress with strict type checking
    if (progress !== undefined) {
        if (typeof progress !== 'number' || isNaN(progress) || progress < 0 || progress > 100) {
            return res.status(400).json({ error: 'Invalid progress value (must be 0-100)' });
        }
        state.agents[agentId].progress = Math.floor(progress);
    }

    broadcast(wss);
    res.json({ ok: true });
});

app.get('/api/state', (req, res) => {
    res.json(state);
});

// Health check endpoint for monitoring and load balancers
app.get('/health', (req, res) => {
    const health = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: require('./package.json').version,
        checks: {
            fileSystem: fs.existsSync(reviewsDir) ? 'ok' : 'reviews_dir_missing',
            websocket: wss.clients.size > 0 ? 'connected' : 'no_clients'
        }
    };
    res.status(200).json(health);
});

// Global error handler - catches unhandled errors in routes
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err.message);
    res.status(err.status || 500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// Serve findings content (validated against known agent names)
app.get('/api/findings/:agentId', (req, res) => {
    const { agentId } = req.params;

    // Security: Sanitize input - remove any path traversal characters
    const sanitizedId = agentId.replace(/[^a-zA-Z0-9-]/g, '');

    // Validate against whitelist of known agents
    if (!AGENTS.includes(sanitizedId)) {
        return res.status(400).json({ error: 'Invalid agent ID' });
    }

    const filePath = path.join(reviewsDir, `${sanitizedId}-findings.md`);

    // Security: Verify resolved path is within reviewsDir (defense in depth)
    const resolvedPath = path.resolve(filePath);
    const resolvedReviewsDir = path.resolve(reviewsDir);
    if (!resolvedPath.startsWith(resolvedReviewsDir)) {
        console.error(`Path traversal attempt blocked: ${agentId}`);
        return res.status(400).json({ error: 'Invalid request' });
    }

    try {
        if (fs.existsSync(resolvedPath)) {
            const content = fs.readFileSync(resolvedPath, 'utf-8');
            res.type('text/plain').send(content);
        } else {
            res.status(404).json({ error: 'Findings not found' });
        }
    } catch (err) {
        // Security: Don't leak internal error details
        console.error('File read error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// WebSocket connections with origin validation
wss.on('connection', (ws, req) => {
    // Security: Validate origin to prevent unauthorized WebSocket connections
    const origin = req.headers.origin;
    if (origin && !ALLOWED_ORIGINS.includes(origin)) {
        console.log(`Rejected WebSocket connection from unauthorized origin: ${origin}`);
        ws.close(1008, 'Unauthorized origin');
        return;
    }

    console.log('Dashboard client connected');
    ws.send(JSON.stringify({ type: 'state', data: state }));

    ws.on('close', () => {
        console.log('Dashboard client disconnected');
    });
});

// Watch for file changes
if (fs.existsSync(reviewsDir)) {
    const watcher = chokidar.watch(reviewsDir, {
        persistent: true,
        ignoreInitial: false,
    });

    watcher.on('add', (filePath) => {
        const fileName = path.basename(filePath);
        const match = fileName.match(/^(\w+)-findings\.md$/);
        if (match && AGENTS.includes(match[1])) {
            setTimeout(() => {
                checkAgentFile(match[1]);
                detectRunningAgent();
                updateTimeEstimate();
                calculateVerdict();
                broadcast(wss);
            }, 500); // Small delay to ensure file is fully written
        }
    });

    watcher.on('change', (filePath) => {
        const fileName = path.basename(filePath);
        const match = fileName.match(/^(\w+)-findings\.md$/);
        if (match && AGENTS.includes(match[1])) {
            checkAgentFile(match[1]);
            broadcast(wss);
        }
    });
} else {
    console.log(`Warning: Reviews directory not found: ${reviewsDir}`);
    console.log('Make sure to run: ccl.ps1 -Init -Project "..."');
}

// Start server (bound to localhost only for security)
server.listen(PORT, '127.0.0.1', () => {
    console.log('');
    console.log('  ================================================');
    console.log('    CODE CONCLAVE - Live Dashboard Server');
    console.log('  ================================================');
    console.log('');
    console.log(`  Project:   ${projectPath}`);
    console.log(`  Dashboard: http://localhost:${PORT}`);
    console.log(`  WebSocket: ws://localhost:${PORT}`);
    console.log('');
    console.log('  Watching for review output...');
    console.log('');

    initialScan();
});
