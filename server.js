const express = require('express');
const { WebSocketServer } = require('ws');
const app = express();

app.use(express.json());

// 1. HTTP Endpoint for Joystick Commands (Flutter -> Node)
app.post('/control', (req, res) => {
    console.log('Drone Command Received:', req.body);
    res.status(200).send({ status: 'ok' });
});

const server = app.listen(8080, '0.0.0.0', () => {
    console.log('Server running on port 8080');
});

// 2. WebSocket for Telemetry Relay (Python -> Node -> Flutter)
const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
    console.log('Client connected to WebSocket');
    ws.on('message', (data) => {
        // Broadcast incoming telemetry/video signaling to all connected clients
        wss.clients.forEach((client) => {
            if (client !== ws && client.readyState === 1) {
                client.send(data.toString());
            }
        });
    });
});