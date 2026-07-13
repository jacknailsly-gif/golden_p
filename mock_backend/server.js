const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const DB_FILE = path.join(__dirname, 'users.json');

// In-memory mock database for users
let users = [];

// Load users from file
if (fs.existsSync(DB_FILE)) {
    try {
        const data = fs.readFileSync(DB_FILE, 'utf8');
        users = JSON.parse(data);
        console.log(`[DB] Loaded ${users.length} users from users.json`);
    } catch (e) {
        console.error('[DB] Error reading users.json:', e);
    }
} else {
    fs.writeFileSync(DB_FILE, JSON.stringify(users), 'utf8');
}

// Helper function to save users
const saveUsers = () => {
    try {
        fs.writeFileSync(DB_FILE, JSON.stringify(users, null, 2), 'utf8');
    } catch (e) {
        console.error('[DB] Error saving users.json:', e);
    }
};

// Helper function to parse JSON body
const parseBody = (req) => {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
        });
        req.on('end', () => {
            try {
                resolve(JSON.parse(body || '{}'));
            } catch (e) {
                reject(e);
            }
        });
        req.on('error', reject);
    });
};

const server = http.createServer((req, res) => {
    // Enable CORS for all requests
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    // Handle preflight OPTIONS request
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'OK' }));
        return;
    }

    // API Routes for Authentication
    if (req.method === 'POST') {
        if (req.url === '/api/register') {
            parseBody(req).then(data => {
                const { username, password } = data;
                if (!username || !password) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify({ success: false, message: 'Username and password are required' }));
                }
                
                // Check if user exists
                if (users.find(u => u.username === username)) {
                    res.writeHead(409, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify({ success: false, message: 'Username already exists' }));
                }

                // Register user
                users.push({ username, password });
                saveUsers();
                console.log(`[AUTH] New user registered: ${username}`);
                
                res.writeHead(201, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: 'Registration successful' }));
            }).catch(err => {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'Server error' }));
            });
            return;
        }

        if (req.url === '/api/login') {
            parseBody(req).then(data => {
                const { username, password } = data;
                
                const user = users.find(u => u.username === username && u.password === password);
                if (user) {
                    console.log(`[AUTH] User logged in: ${username}`);
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, message: 'Login successful', token: 'mock-jwt-token' }));
                } else {
                    console.log(`[AUTH] Failed login attempt for: ${username}`);
                    res.writeHead(401, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, message: 'Invalid username or password' }));
                }
            }).catch(err => {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'Server error' }));
            });
            return;
        }

        if (req.url === '/api/check-user') {
            parseBody(req).then(data => {
                const { username } = data;
                const exists = users.some(u => u.username === username);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, exists: exists }));
            }).catch(err => {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'Server error' }));
            });
            return;
        }
    }

    res.writeHead(404);
    res.end();
});

const wssSignals = new WebSocket.Server({ noServer: true });
const wssAdmin = new WebSocket.Server({ noServer: true });

let clients = new Map();
let adminClients = new Set();

server.on('upgrade', (request, socket, head) => {
    if (request.url.startsWith('/ws/signals')) {
        wssSignals.handleUpgrade(request, socket, head, (ws) => {
            wssSignals.emit('connection', ws, request);
        });
    } else if (request.url.startsWith('/ws/admin')) {
        wssAdmin.handleUpgrade(request, socket, head, (ws) => {
            wssAdmin.emit('connection', ws, request);
        });
    } else {
        socket.destroy();
    }
});

// Signals Endpoint
wssSignals.on('connection', (ws, req) => {
    const ip = req.socket.remoteAddress === '::1' ? 'Localhost' : req.socket.remoteAddress;
    const device = req.headers['user-agent'] || 'Mobile App Emulator';
    
    // Parse query string for email
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const email = url.searchParams.get('email');
    
    const clientData = {
        id: email ? email : "USR-" + ip,
        device: device,
        plan: "Pro Trader",
        ping: Math.floor(Math.random() * 40 + 5) + "ms",
        action: "Receiving WSS Signals"
    };
    
    clients.set(ws, clientData);
    
    ws.on('close', () => {
        clients.delete(ws);
    });
});

// Admin Endpoint
wssAdmin.on('connection', (ws) => {
    adminClients.add(ws);
    ws.on('close', () => {
        adminClients.delete(ws);
    });
});

// Broadcast Signals to Mobile App
setInterval(() => {
    const signal = {
        type: "prediction_signal",
        data: { "BTC/USD": 65000.50 + Math.random() * 100 },
        timestamp: Math.floor(Date.now() / 1000)
    };
    const msg = JSON.stringify(signal);
    clients.forEach((clientData, ws) => {
        if (ws.readyState === WebSocket.OPEN) {
            ws.send(msg);
        }
    });
}, 3000);

// Broadcast Metrics to Web Dashboard
setInterval(() => {
    const payload = {
        type: "admin_metrics",
        ccu: clients.size,
        total_users: 1542 + users.length,
        users: Array.from(clients.values())
    };
    const msg = JSON.stringify(payload);
    adminClients.forEach((ws) => {
        if (ws.readyState === WebSocket.OPEN) {
            ws.send(msg);
        }
    });
}, 2000);

const PORT = 8080;
server.listen(PORT, () => {
    console.log(`\n==============================================`);
    console.log(`🚀 Node.js Mock Backend listening on port ${PORT}`);
    console.log(`📱 Mobile Signals: ws://localhost:${PORT}/ws/signals`);
    console.log(`💻 Dashboard Data: ws://localhost:${PORT}/ws/admin`);
    console.log(`==============================================\n`);
});
