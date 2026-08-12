#!/usr/bin/env bash
set -euo pipefail

BRANCH="feature/app-support"

# ensure we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository. cd to the repo root and re-run."
  exit 1
fi

# abort if branch exists
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  echo "Branch '$BRANCH' already exists locally. Aborting to avoid overwriting."
  echo "If you want to update it, checkout that branch and apply changes manually."
  exit 1
fi

# create branch from current HEAD
git checkout -b "$BRANCH"

# backup existing package.json if present
if [ -f package.json ]; then
  echo "Backing up existing package.json -> package.json.bak"
  cp package.json package.json.bak
fi

# create client directory and files
mkdir -p client client/icons

cat > client/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Tarmac Titan — 3D Demo Client</title>
  <meta name="theme-color" content="#0b0f14" />
  <link rel="manifest" href="/manifest.webmanifest">
  <style>
    html,body{height:100%;margin:0;background:#0b0f14;color:#e6eef6;overflow:hidden;font-family:system-ui,-apple-system,Segoe UI,Roboto,"Helvetica Neue",Arial}
    #overlay{position:absolute;left:16px;top:16px;z-index:10}
    #players{margin-top:8px;font-size:13px;opacity:0.9}
    #hotbar{position:absolute;left:50%;transform:translateX(-50%);bottom:14px;display:flex;gap:8px;z-index:10}
    .hot-slot{width:56px;height:56px;border-radius:8px;background:rgba(255,255,255,0.04);display:flex;align-items:center;justify-content:center}
    #controls { position: absolute; right: 16px; bottom: 16px; z-index: 10; display:flex; gap:8px; flex-direction:column }
    .ctl { width:56px; height:56px; border-radius:8px; background:rgba(255,255,255,0.05); display:flex; align-items:center; justify-content:center; font-weight:700 }
    #chatBox { position: absolute; left: 16px; bottom: 16px; width:320px; max-height:200px; overflow:auto; background: rgba(0,0,0,0.25); padding:8px; border-radius:8px; font-size:12px }
    #chatInput { width: 300px; padding:6px; border-radius:6px; border:0; outline: none }
    #playerList { margin-top:8px; font-size:12px }
    canvas{display:block}
  </style>
</head>
<body>
  <div id="overlay">
    <div><strong>Tarmac Titan — 3D demo</strong></div>
    <div id="players">players: 0</div>
    <div id="playerList"></div>
  </div>

  <div id="hotbar" aria-hidden="false">
    <div class="hot-slot">1</div><div class="hot-slot">2</div><div class="hot-slot">3</div>
  </div>

  <div id="controls">
    <div id="btnUp" class="ctl">↑</div>
    <div id="btnAction" class="ctl">●</div>
    <div id="btnDown" class="ctl">↓</div>
  </div>

  <div id="chatBox">
    <div id="chatList" style="max-height:140px; overflow:auto; font-size:12px"></div>
    <div style="margin-top:6px; display:flex; gap:6px">
      <input id="chatInput" placeholder="Type message or /tp <id>" />
    </div>
  </div>

  <script src="https://cdn.socket.io/4.7.0/socket.io.min.js"></script>
  <script type="module">
    import * as THREE from 'https://unpkg.com/three@0.154.0/build/three.module.js';
    import { OrbitControls } from 'https://unpkg.com/three@0.154.0/examples/jsm/controls/OrbitControls.js';

    const socket = io(window.location.origin);
    const playersEl = document.getElementById('players');

    // Scene & renderer
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0b0f14);
    const camera = new THREE.PerspectiveCamera(60, innerWidth/innerHeight, 0.1, 1000);
    camera.position.set(0, 6, 12);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(innerWidth, innerHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    document.body.appendChild(renderer.domElement);

    // Controls (for dev)
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.target.set(0,1.2,0);
    controls.update();

    // Lights
    const hemi = new THREE.HemisphereLight(0xffffee, 0x080820, 0.8);
    scene.add(hemi);
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(5,10,7);
    scene.add(dir);

    // Ground
    const groundMat = new THREE.MeshStandardMaterial({ color: 0x07101b, roughness: 0.9 });
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(120,120), groundMat);
    ground.rotation.x = -Math.PI/2;
    ground.position.y = 0;
    scene.add(ground);

    // Simple toon-like material
    function createToonMaterial(color=0xffffff){
      return new THREE.MeshToonMaterial({ color });
    }

    // Helper: create a low-poly stickman (thin limbs, sphere head)
    function createStickman(color=0xffffff){
      const g = new THREE.Group();
      const mat = createToonMaterial(color);
      const jointMat = createToonMaterial(0x111111);

      // Head
      const head = new THREE.Mesh(new THREE.SphereGeometry(0.35, 12, 8), mat);
      head.position.y = 1.8;
      g.add(head);

      // Torso
      const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.12,0.12,1.0,8), mat);
      torso.position.y = 1.1;
      g.add(torso);

      // Limb factory
      function limb(length){
        const limbGeo = new THREE.CylinderGeometry(0.07,0.07,length,8);
        const m = new THREE.Mesh(limbGeo, mat);
        return m;
      }

      // Arms
      const leftArm = limb(0.9);
      leftArm.position.set(-0.35,1.3,0);
      leftArm.rotation.z = Math.PI/6;
      g.add(leftArm);

      const rightArm = limb(0.9);
      rightArm.position.set(0.35,1.3,0);
      rightArm.rotation.z = -Math.PI/6;
      g.add(rightArm);

      // Legs
      const leftLeg = limb(1.0);
      leftLeg.position.set(-0.12,0.25,0);
      leftLeg.rotation.z = -Math.PI/30;
      g.add(leftLeg);

      const rightLeg = limb(1.0);
      rightLeg.position.set(0.12,0.25,0);
      rightLeg.rotation.z = Math.PI/30;
      g.add(rightLeg);

      // Add small joint spheres for style
      const js = new THREE.Mesh(new THREE.SphereGeometry(0.08,8,6), jointMat);
      js.position.set(-0.35,1.3,0);
      g.add(js);
      const js2 = js.clone(); js2.position.x = 0.35; g.add(js2);

      return g;
    }

    // Capsule avatar (test)
    function createCapsule(color=0x66ccff){
      const g = new THREE.Group();
      const mat = createToonMaterial(color);
      // Cylinder body
      const body = new THREE.Mesh(new THREE.CylinderGeometry(0.35,0.35,1.2,12), mat);
      body.position.y = 1.0;
      g.add(body);
      // Hemispheres
      const top = new THREE.Mesh(new THREE.SphereGeometry(0.35,12,8), mat);
      top.position.y = 1.6; g.add(top);
      const bot = new THREE.Mesh(new THREE.SphereGeometry(0.35,12,8), mat);
      bot.position.y = 0.4; g.add(bot);
      return g;
    }

    // Avatar management
    const avatars = new Map(); // id -> { mesh, type, position }
    const positions = new Map(); // id -> {x,y,z}

    function addAvatar(id, opts={ type:'stick', color: 0xffffff }){
      if(avatars.has(id)) return avatars.get(id).mesh;
      let mesh;
      if(opts.type === 'capsule') mesh = createCapsule(opts.color);
      else mesh = createStickman(opts.color);
      mesh.position.set((Math.random()-0.5)*4, 0, (Math.random()-0.5)*4);
      scene.add(mesh);
      avatars.set(id, { mesh, type: opts.type });
      positions.set(id, { x: mesh.position.x, y: mesh.position.y, z: mesh.position.z });
      return mesh;
    }

    function removeAvatar(id){
      const a = avatars.get(id);
      if(a){ scene.remove(a.mesh); avatars.delete(id); positions.delete(id); }
    }

    function updateAvatarPosition(id, pos){
      const a = avatars.get(id);
      if(!a) return;
      a.mesh.position.set(pos.x, pos.y, pos.z);
      positions.set(id, { x: pos.x, y: pos.y, z: pos.z });
    }

    // Local player id (use socket id once connected)
    let localId = null;

    // Handle presence list from server
    socket.on('presence', (list) => {
      // list is array of presence objects {id, meta, joinedAt}
      playersEl.textContent = 'players: ' + (Array.isArray(list) ? list.length : 0);
      const ids = new Set((Array.isArray(list) ? list.map(p => p.id) : []));

      // Add missing avatars
      ids.forEach(id => {
        if(!avatars.has(id)){
          // Use capsule for testing users with meta.testCapsule true, otherwise stickman
          const meta = (Array.isArray(list) ? list.find(p=>p.id===id).meta : {}) || {};
          addAvatar(id, { type: meta && meta.testCapsule ? 'capsule' : 'stick', color: id===localId ? 0x88ff88 : 0xffffff });
        }
      });

      // Remove avatars no longer present
      for(const id of Array.from(avatars.keys())){
        if(!ids.has(id)) removeAvatar(id);
      }

      // update player list UI
      refreshPlayerList(Array.isArray(list) ? list : []);
    });

    // Handle remote move events
    socket.on('player:moved', (payload) => {
      if(!payload || !payload.id) return;
      const id = payload.id;
      const s = payload.state || {};
      if(!avatars.has(id)) addAvatar(id, { type: 'stick' });
      // payload.state expected to have x,y,z
      if(typeof s.x === 'number'){
        updateAvatarPosition(id, { x: s.x, y: s.y || 0, z: s.z || 0 });
      }
    });

    // handle teleports if server implements them
    socket.on('player:teleported', ({ id, pos }) => {
      if(!pos) return;
      if(!avatars.has(id)) addAvatar(id, { type: 'stick' });
      updateAvatarPosition(id, { x: pos.x, y: pos.y || 0, z: pos.z });
      if(id === localId) localPos = { x: pos.x, y: pos.y || 0, z: pos.z };
    });

    // Connect and join
    socket.on('connect', () => {
      localId = socket.id;
      socket.emit('join', 'lobby', { platform: navigator.userAgent, testCapsule: false });
      // add local avatar immediately
      addAvatar(localId, { type: 'stick', color: 0x88ff88 });
    });

    socket.on('disconnect', () => {
      console.warn('disconnected from server');
    });

    // Simple movement controls: keyboard + buttons
    let localPos = { x: 0, y: 0, z: 0 };
    const speed = 0.25;

    function sendMove(){
      socket.emit('move', { roomId: 'lobby', state: { x: localPos.x, y: localPos.y, z: localPos.z } });
    }

    function moveDir(dir){
      if(dir === 'up') localPos.z -= speed;
      if(dir === 'down') localPos.z += speed;
      if(dir === 'left') localPos.x -= speed;
      if(dir === 'right') localPos.x += speed;
      if(dir === 'action') localPos.y = Math.sin(Date.now()/200) * 0.2;
      updateAvatarPosition(localId, localPos);
      sendMove();
    }

    window.addEventListener('keydown', (e) => {
      if(e.key === 'w' || e.key === 'ArrowUp') moveDir('up');
      if(e.key === 's' || e.key === 'ArrowDown') moveDir('down');
      if(e.key === 'a' || e.key === 'ArrowLeft') moveDir('left');
      if(e.key === 'd' || e.key === 'ArrowRight') moveDir('right');
      if(e.key === ' ') moveDir('action');
    });

    document.getElementById('btnUp').addEventListener('click', ()=> moveDir('up'));
    document.getElementById('btnDown').addEventListener('click', ()=> moveDir('down'));
    document.getElementById('btnAction').addEventListener('click', ()=> moveDir('action'));

    // Chat and command handling
    const chatInput = document.getElementById('chatInput');
    const chatList = document.getElementById('chatList');

    chatInput.addEventListener('keydown', (e) => {
      if(e.key === 'Enter'){
        const text = chatInput.value.trim();
        if(!text) return;
        if(text.startsWith('/')){
          socket.emit('command', text);
        } else {
          socket.emit('chat:message', { text });
        }
        chatInput.value = '';
      }
    });

    socket.on('chat:message', (m) => {
      const el = document.createElement('div');
      el.textContent = `${m.id ? m.id.substring(0,6) : 'anon'}: ${m.text}`;
      chatList.appendChild(el);
      chatList.scrollTop = chatList.scrollHeight;
    });

    // respond to request:pos from server
    socket.on('request:pos', ({ requester, target }) => {
      if(socket.id !== target) return;
      socket.emit('reply:pos', { requester, pos: localPos });
    });

    // maintain and show player list (click to tp)
    function refreshPlayerList(presences) {
      const pl = document.getElementById('playerList');
      pl.innerHTML = '';
      presences.forEach(p => {
        const d = document.createElement('div');
        d.textContent = p.id.substring(0,8);
        d.style.cursor = 'pointer';
        d.onclick = () => { chatInput.value = '/tp ' + p.id; chatInput.focus(); };
        pl.appendChild(d);
      });
    }

    // Animation loop
    function animate(){
      requestAnimationFrame(animate);
      const t = Date.now() * 0.001;
      avatars.forEach((val, id) => {
        if(id === localId) return;
        const mesh = val.mesh;
        mesh.rotation.y = Math.sin(t + id.length) * 0.1;
      });
      renderer.render(scene, camera);
    }
    animate();

    // Handle resize
    window.addEventListener('resize', () => {
      camera.aspect = innerWidth/innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(innerWidth, innerHeight);
    });

    // Register service worker for PWA
    if('serviceWorker' in navigator){
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').then(reg => {
          console.log('ServiceWorker registered', reg.scope);
        }).catch(err => console.warn('ServiceWorker registration failed', err));
      });
    });

  </script>
</body>
</html>
EOF

cat > client/manifest.webmanifest <<'EOF'
{
  "name": "Tarmac Titan",
  "short_name": "Tarmac",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0b0f14",
  "theme_color": "#0b0f14",
  "description": "TarmacTitan — lightweight 3D demo",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
EOF

cat > client/sw.js <<'EOF'
const CACHE_NAME = 'tarmac-titan-v1';
const ASSETS = [
  '/',
  '/client/index.html',
  '/client/index.html',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request).catch(() => caches.match('/'));
    })
  );
});
EOF

# electron files
mkdir -p electron
cat > electron/main.js <<'EOF'
const { app, BrowserWindow } = require('electron');
const path = require('path');

function createWindow () {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  const startUrl = process.env.ELECTRON_START_URL || `file://${path.join(__dirname, '..', 'client', 'index.html')}`;
  win.loadURL(startUrl);
  // Open devtools when in development
  if(process.env.ELECTRON_START_URL) win.webContents.openDevTools();
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
EOF

# write package.json (backup already done above)
cat > package.json <<'EOF'
{
  "name": "tarmac-titan",
  "version": "0.1.0",
  "description": "TarmacTitan demo server + 3D client",
  "main": "server/index.js",
  "scripts": {
    "start": "node server/index.js",
    "dev": "nodemon server/index.js",
    "electron:dev": "cross-env ELECTRON_START_URL=http://localhost:3000 electron .",
    "build:electron": "electron-builder"
  },
  "author": "henrymdillardiv-ui",
  "license": "MIT",
  "engines": {
    "node": ">=18"
  },
  "dependencies": {
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "express-rate-limit": "^6.8.0",
    "express-validator": "^7.0.1",
    "helmet": "^7.0.0",
    "jsonwebtoken": "^9.0.0",
    "socket.io": "^4.7.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22",
    "electron": "^26.0.0",
    "electron-builder": "^24.6.0",
    "cross-env": "^7.0.3"
  },
  "build": {
    "appId": "com.yourorg.tarmac-titan",
    "files": [
      "client/**",
      "server/**",
      "package.json"
    ],
    "mac": { "target": ["dmg","zip"] },
    "win": { "target": ["nsis"] }
  }
}
EOF

# Dockerfiles and gitignore
cat > Dockerfile <<'EOF'
# Multi-stage Dockerfile for Tarmac Titan (Node + Socket.IO)

FROM node:18-alpine AS base
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF

cat > .dockerignore <<'EOF'
.gitignore
node_modules
npm-debug.log
.DS_Store
.env
EOF

# GitHub Actions CI workflow
mkdir -p .github/workflows
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [ feature/app-support, main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js 18
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      - name: Install dependencies
        run: npm ci
      - name: Run lint/test (skip if none)
        run: echo "No tests configured"
      - name: Build Docker image
        run: docker build -t tarmac-titan:ci .
      - name: Upload artifact (docker image info)
        run: docker images | head -n 20
EOF

# README
cat > README.md <<'EOF'
# Docker / Electron / PWA added in feature/app-support

Quick start (web):

1. npm install
2. npm start
3. Open http://localhost:3000

Run Electron (dev):

1. npm install
2. npm start   # run the server
3. npm run electron:dev

Build Electron app (requires electron-builder):

npm run build:electron

Docker (build & run):

docker build -t tarmac-titan .
docker run -p 3000:3000 tarmac-titan
EOF

# Add and commit
git add -A
git commit -m "feat(app): add PWA, Electron wrapper, Dockerfile and CI skeleton (feature/app-support)"

# push branch
git push -u origin "$BRANCH"

echo "Branch '$BRANCH' created and pushed. Review changes, then open a Pull Request on GitHub."
