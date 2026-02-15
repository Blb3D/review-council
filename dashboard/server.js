/**
 * Code Conclave - Live Dashboard Server
 *
 * Watches review output files and broadcasts updates via WebSocket.
 * Supports JSON findings files (preferred) with markdown fallback.
 * Provides run history via archive directory.
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

const ccDir = path.join(projectPath, '.code-conclave');
const reviewsDir = path.join(ccDir, 'reviews');
const archiveDir = path.join(reviewsDir, 'archive');
const PORT = 3847;

// Agent definitions
const AGENTS = ['guardian', 'sentinel', 'architect', 'navigator', 'herald', 'operator'];

const AGENT_INFO = {
    guardian:  { name: 'GUARDIAN',  role: 'Security',             icon: '\u{1F512}', color: '#ff4466' },
    sentinel:  { name: 'SENTINEL',  role: 'Quality & Compliance', icon: '\u{1F6E1}\uFE0F', color: '#ffaa00' },
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

// Reset all agent states to pending
function resetAgentStates() {
    AGENTS.forEach(id => {
        state.agents[id] = {
            ...AGENT_INFO[id],
            id,
            status: 'pending',
            progress: 0,
            findings: null,
            parsedFindings: null,
            tokens: null,
        };
    });
}

// Initialize agent states
resetAgentStates();

// Parse findings from markdown file (fallback when no JSON available)
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

// Load agent data from JSON file (preferred path)
function loadAgentJson(agentId, filePath) {
    try {
        let content = fs.readFileSync(filePath, 'utf-8');
        if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);
        const data = JSON.parse(content);

        // Track duration
        if (agentStartTimes[agentId]) {
            const duration = Date.now() - agentStartTimes[agentId];
            agentDurations.push(duration);
            state.agents[agentId].duration = duration;
        }

        state.agents[agentId].status = data.status === 'error' ? 'failed' : 'complete';
        state.agents[agentId].progress = 100;
        state.agents[agentId].findings = data.summary || null;
        state.agents[agentId].parsedFindings = data.findings || null;
        state.agents[agentId].tokens = data.tokens || null;

        if (data.run && data.run.durationSeconds) {
            state.agents[agentId].duration = data.run.durationSeconds * 1000;
        }

        const s = data.summary || { blockers: 0, high: 0, medium: 0, low: 0 };
        addLog(`${AGENT_INFO[agentId].name} complete: ${s.blockers} blocker, ${s.high} high, ${s.medium} medium, ${s.low} low`,
            s.blockers > 0 ? 'error' : s.high > 0 ? 'warning' : 'success');

        updateTimeEstimate();
        return true;
    } catch (err) {
        console.error(`Failed to parse ${filePath}: ${err.message}`);
        return false;
    }
}

// Check markdown file and update state (fallback)
function checkAgentFile(agentId) {
    const filePath = path.join(reviewsDir, `${agentId}-findings.md`);

    if (fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf-8');
        const findings = parseFindings(content);

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

// Check for agent file (prefer JSON, fall back to markdown)
function checkAgentAnyFormat(agentId) {
    const jsonPath = path.join(reviewsDir, `${agentId}-findings.json`);
    if (fs.existsSync(jsonPath)) {
        return loadAgentJson(agentId, jsonPath);
    }
    return checkAgentFile(agentId);
}

// Detect currently running agent
function detectRunningAgent() {
    let foundComplete = false;
    for (const id of AGENTS) {
        if (state.agents[id].status === 'complete') {
            foundComplete = true;
        } else if (foundComplete && state.agents[id].status === 'pending') {
            state.agents[id].status = 'running';
            state.agents[id].progress = Math.floor(Math.random() * 50) + 25;
            agentStartTimes[id] = Date.now();
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

    let currentElapsed = 0;
    if (runningAgent && agentStartTimes[runningAgent]) {
        currentElapsed = Date.now() - agentStartTimes[runningAgent];
    }

    const estimatedRemaining = (avgDuration * remainingCount) - currentElapsed;
    state.timeEstimate = Math.max(0, Math.round(estimatedRemaining / 1000));
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
function broadcast() {
    const message = JSON.stringify({ type: 'state', data: state });
    wss.clients.forEach(client => {
        if (client.readyState === 1) {
            client.send(message);
        }
    });
}

// Handle file addition (new findings file appears)
function handleFileAdd(filePath) {
    const fileName = path.basename(filePath);

    // Prefer JSON findings files
    const jsonMatch = fileName.match(/^(\w+)-findings\.json$/);
    if (jsonMatch && AGENTS.includes(jsonMatch[1])) {
        setTimeout(() => {
            loadAgentJson(jsonMatch[1], filePath);
            detectRunningAgent();
            updateTimeEstimate();
            calculateVerdict();
            broadcast();
        }, 500);
        return;
    }

    // Fallback: markdown findings (only if no JSON exists for this agent)
    const mdMatch = fileName.match(/^(\w+)-findings\.md$/);
    if (mdMatch && AGENTS.includes(mdMatch[1])) {
        const jsonPath = path.join(reviewsDir, `${mdMatch[1]}-findings.json`);
        if (!fs.existsSync(jsonPath)) {
            setTimeout(() => {
                checkAgentFile(mdMatch[1]);
                detectRunningAgent();
                updateTimeEstimate();
                calculateVerdict();
                broadcast();
            }, 500);
        }
    }
}

// Handle file change
function handleFileChange(filePath) {
    const fileName = path.basename(filePath);

    const jsonMatch = fileName.match(/^(\w+)-findings\.json$/);
    if (jsonMatch && AGENTS.includes(jsonMatch[1])) {
        loadAgentJson(jsonMatch[1], filePath);
        broadcast();
        return;
    }

    const mdMatch = fileName.match(/^(\w+)-findings\.md$/);
    if (mdMatch && AGENTS.includes(mdMatch[1])) {
        const jsonPath = path.join(reviewsDir, `${mdMatch[1]}-findings.json`);
        if (!fs.existsSync(jsonPath)) {
            checkAgentFile(mdMatch[1]);
            broadcast();
        }
    }
}

// Handle file deletion (working files cleaned up = run archived)
function handleFileDelete(filePath) {
    const fileName = path.basename(filePath);
    const match = fileName.match(/^(\w+)-findings\.(json|md)$/);

    if (match && AGENTS.includes(match[1])) {
        const agentId = match[1];

        // Reset this agent
        state.agents[agentId].status = 'pending';
        state.agents[agentId].progress = 0;
        state.agents[agentId].findings = null;
        state.agents[agentId].parsedFindings = null;
        state.agents[agentId].tokens = null;
        state.agents[agentId].duration = null;

        // Check if all agents are now pending (run was archived)
        // Only log once - guard on verdict being non-null (first reset clears it)
        const allPending = AGENTS.every(id => state.agents[id].status === 'pending');
        if (allPending && state.verdict !== null) {
            state.verdict = null;
            state.startTime = null;
            state.timeEstimate = null;
            agentStartTimes = {};
            agentDurations = [];
            addLog('Run archived - ready for next review', 'info');
        }

        broadcast();
    }
}

// Initial scan
function initialScan() {
    addLog('Code Conclave Dashboard connected', 'info');
    addLog(`Watching: ${projectPath}`, 'info');

    // Check for existing files (prefer JSON)
    AGENTS.forEach(id => checkAgentAnyFormat(id));
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

// Security: Limit JSON body size to prevent DoS
app.use(express.json({ limit: '100kb' }));

app.post('/api/log', (req, res) => {
    const { message, type } = req.body;

    if (!message || typeof message !== 'string') {
        return res.status(400).json({ error: 'Message is required and must be a string' });
    }
    if (message.length > 1000) {
        return res.status(400).json({ error: 'Message too long (max 1000 characters)' });
    }

    const validTypes = ['info', 'warning', 'error', 'success'];
    const safeType = (typeof type === 'string' && validTypes.includes(type)) ? type : 'info';

    addLog(message, safeType);
    broadcast();
    res.json({ ok: true });
});

app.post('/api/agent-status', (req, res) => {
    const { agentId, status, progress } = req.body;

    if (typeof agentId !== 'string' || !AGENTS.includes(agentId)) {
        return res.status(400).json({ error: 'Invalid agent ID' });
    }

    const validStatuses = ['pending', 'running', 'complete', 'error'];
    if (typeof status !== 'string' || !validStatuses.includes(status)) {
        return res.status(400).json({ error: 'Invalid status' });
    }

    state.agents[agentId].status = status;

    if (progress !== undefined) {
        if (typeof progress !== 'number' || isNaN(progress) || progress < 0 || progress > 100) {
            return res.status(400).json({ error: 'Invalid progress value (must be 0-100)' });
        }
        state.agents[agentId].progress = Math.floor(progress);
    }

    broadcast();
    res.json({ ok: true });
});

app.get('/api/state', (req, res) => {
    res.json(state);
});

// Health check endpoint
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

// Serve findings content (prefer JSON, fall back to markdown)
app.get('/api/findings/:agentId', (req, res) => {
    const { agentId } = req.params;
    const sanitizedId = agentId.replace(/[^a-zA-Z0-9-]/g, '');

    if (!AGENTS.includes(sanitizedId)) {
        return res.status(400).json({ error: 'Invalid agent ID' });
    }

    const resolvedReviewsDir = path.resolve(reviewsDir);

    // Prefer JSON
    const jsonPath = path.join(reviewsDir, `${sanitizedId}-findings.json`);
    const resolvedJson = path.resolve(jsonPath);
    if (resolvedJson.startsWith(resolvedReviewsDir) && fs.existsSync(resolvedJson)) {
        try {
            const content = fs.readFileSync(resolvedJson, 'utf-8');
            return res.type('application/json').send(content);
        } catch (err) {
            console.error('File read error:', err.message);
        }
    }

    // Fall back to markdown
    const mdPath = path.join(reviewsDir, `${sanitizedId}-findings.md`);
    const resolvedMd = path.resolve(mdPath);
    if (resolvedMd.startsWith(resolvedReviewsDir) && fs.existsSync(resolvedMd)) {
        try {
            const content = fs.readFileSync(resolvedMd, 'utf-8');
            return res.type('text/plain').send(content);
        } catch (err) {
            console.error('File read error:', err.message);
        }
    }

    res.status(404).json({ error: 'Findings not found' });
});

// History: list archived runs
app.get('/api/history', (req, res) => {
    if (!fs.existsSync(archiveDir)) {
        return res.json([]);
    }

    try {
        const files = fs.readdirSync(archiveDir)
            .filter(f => f.endsWith('.json'))
            .sort()
            .reverse(); // Most recent first

        const runs = files.map(f => {
            try {
                let content = fs.readFileSync(path.join(archiveDir, f), 'utf-8');
                // Strip UTF-8 BOM if present (PowerShell may write it)
                if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);
                const data = JSON.parse(content);
                return {
                    id: (data.run && data.run.id) || f.replace('.json', ''),
                    timestamp: data.run && data.run.timestamp,
                    project: data.run && data.run.project,
                    verdict: data.verdict,
                    summary: data.summary,
                    agentCount: (data.run && data.run.agentsRequested && data.run.agentsRequested.length) || 0,
                    durationSeconds: data.run && data.run.durationSeconds,
                    dryRun: (data.run && data.run.dryRun) || false,
                    fileName: f,
                };
            } catch {
                return null;
            }
        }).filter(Boolean);

        res.json(runs);
    } catch (err) {
        console.error('Failed to read archive:', err.message);
        res.status(500).json({ error: 'Failed to read archive' });
    }
});

// History: get a specific archived run
app.get('/api/history/:runId', (req, res) => {
    const { runId } = req.params;

    // Sanitize: only allow alphanumeric + T (timestamp format: 20260211T143000)
    const sanitizedId = runId.replace(/[^a-zA-Z0-9T]/g, '');
    if (sanitizedId !== runId || sanitizedId.length > 20) {
        return res.status(400).json({ error: 'Invalid run ID' });
    }

    if (!fs.existsSync(archiveDir)) {
        return res.status(404).json({ error: 'No archive found' });
    }

    const filePath = path.join(archiveDir, `${sanitizedId}.json`);
    const resolved = path.resolve(filePath);
    const resolvedArchiveDir = path.resolve(archiveDir);

    if (!resolved.startsWith(resolvedArchiveDir)) {
        return res.status(400).json({ error: 'Invalid request' });
    }

    try {
        if (!fs.existsSync(resolved)) {
            return res.status(404).json({ error: 'Run not found' });
        }
        let content = fs.readFileSync(resolved, 'utf-8');
        if (content.charCodeAt(0) === 0xFEFF) content = content.slice(1);
        res.type('application/json').send(content);
    } catch (err) {
        console.error('Archive read error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Global error handler
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err.message);
    res.status(err.status || 500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// WebSocket connections with origin validation
wss.on('connection', (ws, req) => {
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

// File watcher setup
let reviewsWatcher = null;

function startReviewsWatcher() {
    if (reviewsWatcher) return;

    reviewsWatcher = chokidar.watch(reviewsDir, {
        persistent: true,
        ignoreInitial: false,
        ignored: /archive/, // Don't watch archive subdirectory
    });

    reviewsWatcher.on('add', handleFileAdd);
    reviewsWatcher.on('change', handleFileChange);
    reviewsWatcher.on('unlink', handleFileDelete);

    console.log(`  Watching: ${reviewsDir}`);
}

// Start watcher or wait for reviews directory to appear
if (fs.existsSync(reviewsDir)) {
    startReviewsWatcher();
} else {
    console.log(`  Waiting for reviews directory: ${reviewsDir}`);

    // Watch the parent .code-conclave dir for reviews to be created
    const parentToWatch = fs.existsSync(ccDir) ? ccDir : projectPath;
    const parentWatcher = chokidar.watch(parentToWatch, {
        persistent: true,
        ignoreInitial: true,
        depth: 2,
    });

    parentWatcher.on('addDir', (dirPath) => {
        if (path.resolve(dirPath) === path.resolve(reviewsDir)) {
            console.log('  Reviews directory created, starting watcher...');
            startReviewsWatcher();
            parentWatcher.close();
        }
    });
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
