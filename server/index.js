// Minimal secure Express + Socket.IO bootstrap
require('dotenv').config();
const express = require('express');
const http = require('http');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { body, query, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const cookieParser = require('cookie-parser');
const { Server } = require('socket.io');

const app = express();
app.use(helmet()); // secure headers

// CORS: whitelist in production; allow all in local dev (change via env)
const allowedOrigins = (process.env.CORS_ORIGINS || 'http://localhost:3000,http://127.0.0.1:3000').split(',');
app.use(cors({
  origin: function(origin, cb){
    if(!origin) return cb(null, true); // allow non-browser (curl, server)
    if(allowedOrigins.indexOf(origin) !== -1) return cb(null, true);
    return cb(new Error('CORS not allowed'));
  },
  credentials: true,
}));

app.use(express.json());
app.use(cookieParser());

// Basic rate limit for HTTP endpoints
const apiLimiter = rateLimit({
  windowMs: 1000, // 1s window
  max: 10,        // max 10 requests per window per IP
});
app.use('/api/', apiLimiter);

// Simple health route
app.get('/api/health', (req, res) => res.json({ ok: true }));

// Mock entitlements endpoint (validate)
app.get('/api/entitlements',
  [ query('userId').optional().isString().trim().escape() ],
  (req, res) => {
    const errors = validationResult(req);
    if(!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
    const userId = req.query.userId || 'guest';
    // return mock in-memory entitlements (replace with DB later)
    res.json({ userId, entitlements: [] });
  }
);

// Helper: verify JWT if present. In development, allow "guest" if no token or no secret.
function verifyTokenOptional(req, res, next){
  const auth = req.get('authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '').trim();

  if(!token){
    // No token: in prod with JWT_SECRET require token; otherwise allow guest for dev/testing
    if(process.env.NODE_ENV === 'production' && process.env.JWT_SECRET) return res.status(401).json({ error: 'unauthorized' });
    req.user = { id: 'guest' };
    return next();
  }

  if(process.env.JWT_SECRET){
    jwt.verify(token, process.env.JWT_SECRET, (err, payload) => {
      if(err) return res.status(401).json({ error: 'invalid token' });
      req.user = payload;
      next();
    });
  } else {
    // No secret configured: decode without verifying for local development only
    try{
      const decoded = jwt.decode(token);
      req.user = decoded || { id: 'guest' };
    }catch(e){
      req.user = { id: 'guest' };
    }
    next();
  }
}

// Mock purchase endpoint (server validates itemId & optional token)
app.post('/api/purchase',
  verifyTokenOptional,
  [ body('itemId').isString().trim().escape() ],
  (req, res) => {
    const errors = validationResult(req);
    if(!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const itemId = req.body.itemId;
    // In a real app: validate itemId exists, charge user, persist purchase
    // Here we return a mock response
    const purchaser = req.user && req.user.id ? req.user.id : 'guest';

    res.json({
      ok: true,
      purchaser,
      itemId,
      purchasedAt: new Date().toISOString(),
    });
  }
);

// Create HTTP server and attach Socket.IO
const port = parseInt(process.env.PORT || '3000', 10);
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: allowedOrigins,
    methods: ['GET','POST'],
    credentials: true,
  },
  // pingInterval / pingTimeout can be tuned for mobile/slow networks
});

// Simple in-memory room state (for demo only)
const rooms = new Map();

io.on('connection', (socket) => {
  console.log('socket connected', socket.id);

  socket.on('join', (roomId, meta = {}) => {
    try{
      roomId = String(roomId || 'lobby');
      socket.join(roomId);
      if(!rooms.has(roomId)) rooms.set(roomId, new Map());
      // store a small presence object
      rooms.get(roomId).set(socket.id, { id: socket.id, meta, joinedAt: Date.now() });

      // Notify room of new member
      io.to(roomId).emit('presence', Array.from(rooms.get(roomId).values()));
    }catch(e){ console.error(e); }
  });

  socket.on('move', (payload) => {
    // payload should include roomId and position/state; validate minimally
    if(!payload || !payload.roomId) return;
    const roomId = String(payload.roomId);
    // Broadcast movement to others in the room
    socket.to(roomId).emit('player:moved', { id: socket.id, state: payload.state || {} });
  });

  socket.on('disconnect', () => {
    console.log('socket disconnected', socket.id);
    // remove from rooms
    for(const [roomId, map] of rooms.entries()){
      if(map.has(socket.id)){
        map.delete(socket.id);
        io.to(roomId).emit('presence', Array.from(map.values()));
        if(map.size === 0) rooms.delete(roomId);
      }
    }
  });
});

server.listen(port, () => {
  console.log(`Server listening on port ${port} (http://localhost:${port})`);
});
