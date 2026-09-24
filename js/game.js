(() => {
  const W = 432;
  const H = 768;
  const GROUND_H = 112;
  const GROUND_Y = H - GROUND_H;
  const PIPE_W = 76;
  const CAP_W = 98;
  const CAP_H = 34;
  const BIRD_X = 128;
  const BIRD_R = 19;
  const GRAVITY = 1880;
  const FLAP_V = -520;
  const MAX_FALL = 760;

  const SPRINKLE = ["#ff4d6d", "#ffd166", "#7ae0ff", "#c9b6ff", "#7dffa0", "#fff"];
  const VARIANTS = [
    { a: "#ff4d6d", b: "#fff7fa", edge: "#d7264a" },
    { a: "#2ed38a", b: "#f3fffa", edge: "#128a58" },
    { a: "#7c6bff", b: "#f7f5ff", edge: "#4a39c4" },
    { a: "#ffd166", b: "#fffdf6", edge: "#e09a12" },
  ];

  const THEMES = [
    { sky: ["#ffc1de", "#ffe4f4", "#c8f4ff"], hillFar: "#f7b3d4", hillNear: "#8fd4f2", cloud: "#fff6fb", cloud2: "#ddf7ff", ground: "#7a4630", frost: "#fff6ee" },
    { sky: ["#ffd1a8", "#ffd0ea", "#e7d6ff"], hillFar: "#f3b183", hillNear: "#e7b6f5", cloud: "#fff3e8", cloud2: "#f6e6ff", ground: "#6d3d2c", frost: "#fff1ea" },
    { sky: ["#ff8fb8", "#e0b0ff", "#8ecbff"], hillFar: "#f08ab4", hillNear: "#7d8cff", cloud: "#ffe6f3", cloud2: "#ece8ff", ground: "#5c3428", frost: "#ffe8f2" },
    { sky: ["#2e2158", "#6b3d88", "#ff7ab8"], hillFar: "#3d2c58", hillNear: "#245e66", cloud: "#6a5688", cloud2: "#8d6ea6", ground: "#2c1814", frost: "#f0d4e4" },
  ];

  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const menuEl = document.getElementById("menu");
  const overEl = document.getElementById("gameover");
  const pauseEl = document.getElementById("paused");
  const playBtn = document.getElementById("play");
  const againBtn = document.getElementById("again");
  const resumeBtn = document.getElementById("resume");
  const muteBtn = document.getElementById("mute");
  const finalScoreEl = document.getElementById("final-score");
  const bestScoreEl = document.getElementById("best-score");
  const menuBestEl = document.getElementById("menu-best");
  const medalEl = document.getElementById("medal");
  const newBestEl = document.getElementById("new-best");
  const liveEl = document.getElementById("live");

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const audio = {
    ctx: null,
    muted: loadBool("sugarflap-muted"),
    unlock() {
      if (this.muted) return;
      try {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        if (!this.ctx) this.ctx = new AC();
        if (this.ctx.state === "suspended") this.ctx.resume();
      } catch (_) { /* autoplay policies vary */ }
    },
    tone(freq, dur, type, vol, toFreq, delay) {
      if (this.muted || !this.ctx) return;
      const t = this.ctx.currentTime + (delay || 0);
      const o = this.ctx.createOscillator();
      const g = this.ctx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(freq, t);
      if (toFreq) o.frequency.exponentialRampToValueAtTime(Math.max(40, toFreq), t + dur);
      g.gain.setValueAtTime(vol, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g);
      g.connect(this.ctx.destination);
      o.start(t);
      o.stop(t + dur + 0.02);
    },
    noise(dur, vol) {
      if (this.muted || !this.ctx) return;
      const length = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
      const buffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / length);
      const src = this.ctx.createBufferSource();
      const filter = this.ctx.createBiquadFilter();
      const g = this.ctx.createGain();
      src.buffer = buffer;
      filter.type = "lowpass";
      filter.frequency.value = 900;
      g.gain.value = vol;
      src.connect(filter);
      filter.connect(g);
      g.connect(this.ctx.destination);
      src.start();
    },
    flap() {
      this.unlock();
      this.tone(620, 0.09, "triangle", 0.07, 1100);
    },
    score() {
      this.unlock();
      this.tone(880, 0.09, "sine", 0.06);
      this.tone(1320, 0.14, "sine", 0.05, null, 0.07);
    },
    candy() {
      this.unlock();
      this.tone(1040, 0.08, "triangle", 0.05, 1560);
    },
    hit() {
      this.unlock();
      this.noise(0.16, 0.07);
      this.tone(240, 0.28, "sine", 0.05, 70);
    },
  };

  const textures = VARIANTS.map(makeStripeTexture);
  const clouds = [
    { x: 30, y: 110, s: 1, v: 16 },
    { x: 240, y: 70, s: 0.72, v: 22 },
    { x: 150, y: 190, s: 0.85, v: 12 },
    { x: 360, y: 150, s: 0.6, v: 26 },
  ];
  const lollipops = Array.from({ length: 6 }, (_, i) => ({
    x: 40 + i * 150,
    color: SPRINKLE[i % 5],
    s: 0.7 + (i % 3) * 0.18,
    spin: i,
  }));
  const stars = Array.from({ length: 28 }, () => ({
    x: Math.random() * W,
    y: 20 + Math.random() * 280,
    r: 1 + Math.random() * 1.6,
    p: Math.random() * Math.PI * 2,
  }));
  const beads = Array.from({ length: 36 }, (_, i) => ({
    color: SPRINKLE[i % SPRINKLE.length],
  }));

  let mode = "menu";
  let time = 0;
  let scroll = 0;
  let score = 0;
  let best = loadNum("sugarflap-best");
  let scorePop = 1;
  let pipes = [];
  let particles = [];
  let floaters = [];
  let traveled = 0;
  let nextSpawn = 160;
  let spawnCount = 0;
  let flash = 0;
  let shake = 0;
  let deadFor = 0;
  let overReady = false;
  let newBest = false;
  let last = 0;
  const bird = { x: BIRD_X, y: H * 0.45, vy: 0, rot: 0, flap: 0, r: BIRD_R };

  renderMute();
  renderMenuBest();

  function makeStripeTexture(variant) {
    const c = document.createElement("canvas");
    c.width = PIPE_W;
    c.height = 140;
    const g = c.getContext("2d");
    g.fillStyle = variant.b;
    g.fillRect(0, 0, c.width, c.height);
    g.strokeStyle = variant.a;
    g.lineWidth = 16;
    g.lineCap = "square";
    g.beginPath();
    for (let y = -c.width; y < c.height + c.width; y += 32) {
      g.moveTo(-4, y);
      g.lineTo(c.width + 4, y + c.width * 0.72);
    }
    g.stroke();
    g.fillStyle = "rgba(255,255,255,0.35)";
    g.fillRect(8, 0, 12, c.height);
    return c;
  }

  function loadNum(key) {
    try { return Number(localStorage.getItem(key)) || 0; } catch (_) { return 0; }
  }
  function loadBool(key) {
    try { return localStorage.getItem(key) === "1"; } catch (_) { return false; }
  }
  function save(key, value) {
    try { localStorage.setItem(key, String(value)); } catch (_) { /* private mode */ }
  }

  function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function lerpColor(a, b, t) {
    const pa = hexToRgb(a);
    const pb = hexToRgb(b);
    const c = pa.map((v, i) => Math.round(v + (pb[i] - v) * t));
    return `rgb(${c[0]}, ${c[1]}, ${c[2]})`;
  }
  function themeAt(points) {
    const x = Math.max(0, Math.min(points / 18, THEMES.length - 1));
    const i = Math.floor(x);
    const f = x - i;
    const a = THEMES[i];
    const b = THEMES[Math.min(i + 1, THEMES.length - 1)];
    return {
      sky: a.sky.map((c, idx) => lerpColor(c, b.sky[idx], f)),
      hillFar: lerpColor(a.hillFar, b.hillFar, f),
      hillNear: lerpColor(a.hillNear, b.hillNear, f),
      cloud: lerpColor(a.cloud, b.cloud, f),
      cloud2: lerpColor(a.cloud2, b.cloud2, f),
      ground: lerpColor(a.ground, b.ground, f),
      frost: lerpColor(a.frost, b.frost, f),
      night: x / (THEMES.length - 1),
    };
  }

  function speedFor(points) {
    return 148 + Math.min(points, 36) * 3.1;
  }
  function gapFor(points) {
    return Math.max(158, 204 - points * 1.35);
  }
  function spacingFor(points) {
    return Math.max(214, 268 - points * 1.1);
  }

  function resetRun() {
    score = 0;
    scorePop = 1;
    pipes = [];
    particles = [];
    floaters = [];
    traveled = 0;
    nextSpawn = 150;
    spawnCount = 0;
    flash = 0;
    shake = 0;
    deadFor = 0;
    overReady = false;
    newBest = false;
    bird.x = BIRD_X;
    bird.y = H * 0.46;
    bird.vy = 0;
    bird.rot = 0;
    bird.flap = 0;
    liveEl.textContent = "";
  }

  function show(el) { el.classList.remove("hidden"); }
  function hide(el) { el.classList.add("hidden"); }

  function renderMenuBest() {
    if (best > 0) {
      menuBestEl.hidden = false;
      menuBestEl.textContent = `Best ${best}`;
    } else {
      menuBestEl.hidden = true;
    }
  }

  function renderMute() {
    muteBtn.textContent = audio.muted ? "🔇" : "🔊";
    muteBtn.setAttribute("aria-label", audio.muted ? "Unmute sound" : "Mute sound");
    muteBtn.setAttribute("aria-pressed", String(audio.muted));
  }

  function medalFor(points) {
    if (points >= 30) return { cls: "rainbow", label: "Rainbow" };
    if (points >= 18) return { cls: "mint", label: "Mint" };
    if (points >= 10) return { cls: "berry", label: "Berry" };
    if (points >= 5) return { cls: "lemon", label: "Lemon" };
    return null;
  }

  function startGame() {
    resetRun();
    mode = "play";
    hide(menuEl);
    hide(overEl);
    hide(pauseEl);
    flap();
  }

  function flap() {
    if (mode !== "play") return;
    bird.vy = FLAP_V;
    bird.flap = 1;
    audio.flap();
    burst(bird.x - 8, bird.y + 4, 7);
  }

  function togglePause() {
    if (mode === "play") {
      mode = "pause";
      show(pauseEl);
    } else if (mode === "pause") {
      mode = "play";
      hide(pauseEl);
    }
  }

  function die() {
    if (mode !== "play") return;
    mode = "dead";
    deadFor = 0;
    flash = 1;
    shake = reduceMotion ? 0 : 9;
    audio.hit();
    burst(bird.x, bird.y, 20);
    if (navigator.vibrate) navigator.vibrate(30);
    if (score > best) {
      best = score;
      newBest = true;
      save("sugarflap-best", best);
    }
  }

  function openGameOver() {
    if (overReady) return;
    overReady = true;
    finalScoreEl.textContent = String(score);
    bestScoreEl.textContent = String(best);
    newBestEl.hidden = !newBest;
    const medal = medalFor(score);
    if (medal) {
      medalEl.hidden = false;
      medalEl.className = `medal ${medal.cls}`;
      medalEl.textContent = medal.label;
    } else {
      medalEl.hidden = true;
      medalEl.className = "medal";
      medalEl.textContent = "";
    }
    renderMenuBest();
    show(overEl);
    againBtn.focus();
  }

  function addScore(amount, x, y, chime) {
    score += amount;
    scorePop = 1.35;
    liveEl.textContent = `Score ${score}`;
    floaters.push({ x, y, text: `+${amount}`, life: 0.8, max: 0.8 });
    if (chime === "candy") audio.candy();
    else audio.score();
  }

  function burst(x, y, n) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = 50 + Math.random() * 180;
      particles.push({
        x, y,
        vx: Math.cos(a) * s,
        vy: Math.sin(a) * s - 30,
        life: 0.45 + Math.random() * 0.35,
        max: 0.8,
        color: SPRINKLE[i % SPRINKLE.length],
        rot: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 10,
        w: 3 + Math.random() * 3,
        h: 8 + Math.random() * 5,
        front: true,
      });
    }
    if (particles.length > 140) particles.splice(0, particles.length - 140);
  }

  function spawnPipe() {
    const gap = gapFor(score);
    const margin = 78;
    const min = margin + gap / 2;
    const max = GROUND_Y - margin - gap / 2;
    const gapY = min + Math.random() * Math.max(1, max - min);
    pipes.push({
      x: W + 24,
      gapY,
      gap,
      variant: spawnCount % VARIANTS.length,
      scored: false,
      candy: spawnCount === 0 || Math.random() < 0.72,
      candyShift: (Math.random() * 2 - 1) * Math.min(28, gap * 0.16),
      candyTaken: false,
    });
    spawnCount += 1;
  }

  function candyCenter(pipe) {
    return { x: pipe.x + PIPE_W / 2, y: pipe.gapY + pipe.candyShift };
  }

  function circleHitsRect(cx, cy, r, rx, ry, rw, rh) {
    const nx = Math.max(rx, Math.min(cx, rx + rw));
    const ny = Math.max(ry, Math.min(cy, ry + rh));
    const dx = cx - nx;
    const dy = cy - ny;
    return dx * dx + dy * dy < r * r;
  }

  function hitsPipe(pipe) {
    const r = bird.r * 0.72;
    const gapTop = pipe.gapY - pipe.gap / 2;
    const gapBot = pipe.gapY + pipe.gap / 2;
    const capX = pipe.x - (CAP_W - PIPE_W) / 2;
    if (circleHitsRect(bird.x, bird.y, r, pipe.x, -40, PIPE_W, gapTop - CAP_H + 40)) return true;
    if (circleHitsRect(bird.x, bird.y, r, capX, gapTop - CAP_H, CAP_W, CAP_H)) return true;
    if (circleHitsRect(bird.x, bird.y, r, capX, gapBot, CAP_W, CAP_H)) return true;
    if (circleHitsRect(bird.x, bird.y, r, pipe.x, gapBot + CAP_H, PIPE_W, GROUND_Y - gapBot)) return true;
    return false;
  }

  function update(dt) {
    time += dt;
    const scenery = mode === "play" ? 1 : mode === "menu" ? 0.35 : 0;
    scroll += speedFor(mode === "play" ? score : 0) * dt * (mode === "play" ? 1 : scenery);

    for (const cloud of clouds) {
      cloud.x -= cloud.v * dt * (mode === "menu" ? 0.45 : mode === "play" ? 1 : 0);
      if (cloud.x < -160) cloud.x = W + 50;
    }

    if (mode === "menu") {
      bird.y = H * 0.46 + Math.sin(time * 2.3) * 14;
      bird.rot = Math.sin(time * 2.3) * 0.12;
      bird.flap = Math.max(0, bird.flap - dt * 3);
      return;
    }

    if (mode === "pause") return;

    bird.flap = Math.max(0, bird.flap - dt * 4.2);
    scorePop += (1 - scorePop) * Math.min(1, dt * 8);
    flash *= Math.pow(0.02, dt);
    shake *= Math.pow(0.04, dt);

    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.vy += 520 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      p.life -= dt;
      if (p.life <= 0) particles.splice(i, 1);
    }
    for (let i = floaters.length - 1; i >= 0; i--) {
      floaters[i].y -= 42 * dt;
      floaters[i].life -= dt;
      if (floaters[i].life <= 0) floaters.splice(i, 1);
    }

    bird.vy = Math.min(MAX_FALL, bird.vy + GRAVITY * dt);
    bird.y += bird.vy * dt;
    const targetRot = Math.max(-0.85, Math.min(1.15, bird.vy / 680));
    bird.rot += (targetRot - bird.rot) * Math.min(1, dt * 9);

    if (bird.y < bird.r + 2) {
      bird.y = bird.r + 2;
      if (bird.vy < 0) bird.vy = 0;
    }

    if (mode === "dead") {
      deadFor += dt;
      if (bird.y + bird.r > GROUND_Y) {
        bird.y = GROUND_Y - bird.r;
        bird.vy = 0;
        bird.rot = Math.PI / 2;
      }
      if (bird.y + bird.r >= GROUND_Y || deadFor > 1.15) openGameOver();
      return;
    }

    if (mode !== "play") return;

    if (!reduceMotion && Math.random() < dt * 18) {
      particles.push({
        x: bird.x - bird.r,
        y: bird.y + (Math.random() * 10 - 5),
        vx: -40 - Math.random() * 30,
        vy: Math.random() * 20 - 10,
        life: 0.35,
        max: 0.35,
        color: "rgba(255,255,255,0.9)",
        rot: 0,
        vr: 0,
        w: 3,
        h: 3,
        front: false,
      });
    }

    const spd = speedFor(score);
    traveled += spd * dt;
    if (traveled >= nextSpawn) {
      traveled = 0;
      nextSpawn = spacingFor(score);
      spawnPipe();
    }

    for (let i = pipes.length - 1; i >= 0; i--) {
      const pipe = pipes[i];
      pipe.x -= spd * dt;
      if (pipe.candy && !pipe.candyTaken) {
        const c = candyCenter(pipe);
        const dx = bird.x - c.x;
        const dy = bird.y - c.y;
        if (dx * dx + dy * dy < (bird.r + 12) * (bird.r + 12)) {
          pipe.candyTaken = true;
          addScore(1, c.x, c.y - 18, "candy");
          burst(c.x, c.y, 10);
        }
      }
      if (!pipe.scored && bird.x > pipe.x + PIPE_W) {
        pipe.scored = true;
        addScore(1, pipe.x + PIPE_W, pipe.gapY, "gate");
      }
      if (pipe.x + CAP_W < -30) pipes.splice(i, 1);
    }

    if (bird.y + bird.r * 0.82 >= GROUND_Y) {
      bird.y = GROUND_Y - bird.r;
      die();
      openGameOver();
      return;
    }
    for (const pipe of pipes) {
      if (hitsPipe(pipe)) {
        die();
        return;
      }
    }
  }

  function roundRect(x, y, w, h, r) {
    const radius = Math.max(0, Math.min(r, w / 2, h / 2));
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  function drawBackground(theme) {
    const sky = ctx.createLinearGradient(0, 0, 0, H);
    sky.addColorStop(0, theme.sky[0]);
    sky.addColorStop(0.48, theme.sky[1]);
    sky.addColorStop(1, theme.sky[2]);
    ctx.fillStyle = sky;
    ctx.fillRect(-40, -40, W + 80, H + 80);

    if (theme.night > 0.45) {
      ctx.save();
      ctx.globalAlpha = Math.min(1, (theme.night - 0.45) / 0.4);
      for (const star of stars) {
        const tw = 0.45 + Math.sin(time * 3 + star.p) * 0.55;
        ctx.globalAlpha = tw * Math.min(1, (theme.night - 0.45) / 0.4);
        ctx.fillStyle = "#fff8ea";
        ctx.beginPath();
        ctx.arc(star.x, star.y, star.r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }

    drawSun();
    drawHills(theme.hillFar, 0.22, 598, 26);
    drawLollipops();
    drawHills(theme.hillNear, 0.4, 636, 16);
    for (const cloud of clouds) drawCloud(cloud.x, cloud.y, cloud.s, theme);
  }

  function drawSun() {
    ctx.save();
    ctx.translate(348, 92);
    if (!reduceMotion) ctx.rotate(time * 0.12);
    ctx.strokeStyle = "rgba(255, 214, 120, 0.85)";
    ctx.lineWidth = 4;
    ctx.lineCap = "round";
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a) * 34, Math.sin(a) * 34);
      ctx.lineTo(Math.cos(a) * 50, Math.sin(a) * 50);
      ctx.stroke();
    }
    const g = ctx.createRadialGradient(-8, -10, 4, 0, 0, 30);
    g.addColorStop(0, "#fff7d0");
    g.addColorStop(1, "#ffb703");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(0, 0, 28, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawHills(color, parallax, base, amp) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(0, H);
    for (let x = 0; x <= W; x += 8) {
      const world = x + scroll * parallax;
      const y = base
        + Math.sin(world * 0.012) * amp
        + Math.sin(world * 0.031) * amp * 0.35;
      ctx.lineTo(x, y);
    }
    ctx.lineTo(W, H);
    ctx.closePath();
    ctx.fill();
  }

  function drawLollipops() {
    for (const pop of lollipops) {
      const x = ((pop.x - scroll * 0.25) % (W + 180) + (W + 180)) % (W + 180) - 40;
      const y = 586 + Math.sin(pop.x) * 8;
      ctx.save();
      ctx.translate(x, y);
      ctx.scale(pop.s, pop.s);
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 4;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(0, 10);
      ctx.lineTo(2, 58);
      ctx.stroke();
      ctx.rotate(time * 0.4 + pop.spin);
      ctx.fillStyle = pop.color;
      ctx.beginPath();
      ctx.arc(0, 0, 16, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.85)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, 9, 0.4, 2.2);
      ctx.stroke();
      ctx.restore();
    }
  }

  function drawCloud(x, y, s, theme) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(s, s);
    const puffs = [[0, 10, 28], [26, 0, 34], [58, 12, 26], [34, 18, 24]];
    for (let i = 0; i < puffs.length; i++) {
      const [px, py, r] = puffs[i];
      ctx.fillStyle = i % 2 === 0 ? theme.cloud : theme.cloud2;
      ctx.beginPath();
      ctx.arc(px, py, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawPipe(pipe) {
    const variant = VARIANTS[pipe.variant];
    const texture = textures[pipe.variant];
    const gapTop = pipe.gapY - pipe.gap / 2;
    const gapBot = pipe.gapY + pipe.gap / 2;
    const capX = pipe.x - (CAP_W - PIPE_W) / 2;
    drawShaft(pipe.x, -30, gapTop - CAP_H + 42, texture, variant);
    drawCap(capX, gapTop - CAP_H, true, variant);
    drawCap(capX, gapBot, false, variant);
    drawShaft(pipe.x, gapBot + CAP_H - 12, GROUND_Y - (gapBot + CAP_H) + 20, texture, variant);
    if (pipe.candy && !pipe.candyTaken) {
      const c = candyCenter(pipe);
      drawBonbon(c.x, c.y, variant.a);
    }
  }

  function drawShaft(x, y, h, texture, variant) {
    if (h <= 0) return;
    ctx.save();
    roundRect(x, y, PIPE_W, h, 16);
    ctx.clip();
    for (let yy = y; yy < y + h; yy += texture.height) {
      ctx.drawImage(texture, x, yy, PIPE_W, texture.height);
    }
    ctx.restore();
    ctx.strokeStyle = variant.edge;
    ctx.lineWidth = 3;
    roundRect(x, y, PIPE_W, h, 16);
    ctx.stroke();
  }

  function drawCap(x, y, dripDown, variant) {
    ctx.save();
    ctx.fillStyle = "rgba(90, 20, 40, 0.12)";
    ctx.fillRect(x + 8, dripDown ? y + CAP_H - 2 : y - 4, CAP_W - 16, 8);
    ctx.fillStyle = "#fffdfb";
    roundRect(x, y, CAP_W, CAP_H, 14);
    ctx.fill();
    ctx.strokeStyle = variant.edge;
    ctx.lineWidth = 4;
    ctx.stroke();
    ctx.fillStyle = "rgba(255,255,255,0.7)";
    roundRect(x + 10, y + 7, 28, 10, 6);
    ctx.fill();
    ctx.restore();
  }

  function drawBonbon(x, y, color) {
    ctx.save();
    ctx.translate(x, y);
    if (!reduceMotion) ctx.rotate(Math.sin(time * 3 + x) * 0.25);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(-20, 0);
    ctx.lineTo(-9, -7);
    ctx.lineTo(-9, 7);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(20, 0);
    ctx.lineTo(9, -7);
    ctx.lineTo(9, 7);
    ctx.closePath();
    ctx.fill();
    const g = ctx.createRadialGradient(-3, -4, 1, 0, 0, 11);
    g.addColorStop(0, "#fff");
    g.addColorStop(0.45, color);
    g.addColorStop(1, color);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(0, 0, 11, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.8)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(-2, -2, 5, Math.PI * 1.1, Math.PI * 1.8);
    ctx.stroke();
    ctx.restore();
  }

  function drawGround(theme) {
    ctx.fillStyle = theme.frost;
    ctx.beginPath();
    ctx.moveTo(0, GROUND_Y - 6);
    for (let x = 0; x <= W; x += 8) {
      ctx.lineTo(x, GROUND_Y - 4 + Math.sin((x + scroll) * 0.06) * 3);
    }
    ctx.lineTo(W, H);
    ctx.lineTo(0, H);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = theme.ground;
    ctx.fillRect(0, GROUND_Y + 16, W, GROUND_H);
    ctx.fillStyle = "rgba(255,255,255,0.08)";
    ctx.fillRect(0, GROUND_Y + 16, W, 8);

    const span = 26;
    const offset = scroll % span;
    for (let i = -1; i < W / span + 2; i++) {
      const x = i * span - offset;
      const idx = Math.floor((scroll + i * span) / span);
      ctx.fillStyle = beads[((idx % beads.length) + beads.length) % beads.length].color;
      ctx.beginPath();
      ctx.arc(x + span / 2, GROUND_Y + 16, 7, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.save();
    for (let i = 0; i < 18; i++) {
      const world = i * 48;
      const x = ((world - scroll * 1.1) % (W + 48) + (W + 48)) % (W + 48) - 10;
      const y = GROUND_Y + 36 + (i % 5) * 12;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate((i * 0.7) % Math.PI);
      ctx.fillStyle = SPRINKLE[i % SPRINKLE.length];
      roundRect(-2, -6, 4, 12, 2);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  function drawBird() {
    ctx.save();
    ctx.translate(bird.x, bird.y + 16);
    ctx.fillStyle = "rgba(120, 30, 70, 0.16)";
    ctx.beginPath();
    ctx.ellipse(0, 0, 16, 5, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.translate(bird.x, bird.y);
    ctx.rotate(bird.rot);
    const wing = Math.sin(time * (mode === "play" ? 16 : 8)) * 0.35 - bird.flap * 1.15;

    ctx.save();
    ctx.rotate(-0.5 + wing);
    ctx.fillStyle = "#ffd6ea";
    ctx.beginPath();
    ctx.ellipse(-2, 6, 15, 10, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#ff9ec8";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();

    const body = ctx.createRadialGradient(-8, -10, 3, 2, 2, bird.r + 2);
    body.addColorStop(0, "#ffe6f2");
    body.addColorStop(0.42, "#ff5fa2");
    body.addColorStop(1, "#e2186e");
    ctx.fillStyle = body;
    ctx.beginPath();
    ctx.arc(0, 0, bird.r, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#fff3f8";
    ctx.beginPath();
    ctx.ellipse(1, 7, 10, 8, 0, 0, Math.PI * 2);
    ctx.fill();

    drawMiniSprinkle(-8, -1, "#7ae0ff", 0.5);
    drawMiniSprinkle(4, 9, "#ffd166", -0.4);
    drawMiniSprinkle(-3, 11, "#b388ff", 0.8);

    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.ellipse(8, -4, 7.2, 8, 0.1, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#2b1d24";
    ctx.beginPath();
    ctx.arc(10, -3.5, 3.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.arc(11.3, -4.7, 1.3, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "rgba(255, 90, 130, 0.4)";
    ctx.beginPath();
    ctx.ellipse(3, 5, 4, 2.3, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#ff9f1c";
    ctx.beginPath();
    ctx.moveTo(14, -1);
    ctx.lineTo(29, 4);
    ctx.lineTo(14, 9);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "#ffe08a";
    ctx.beginPath();
    ctx.moveTo(14, -1);
    ctx.lineTo(24, 2.4);
    ctx.lineTo(14, 4);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function drawMiniSprinkle(x, y, color, rot) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rot);
    ctx.fillStyle = color;
    roundRect(-1.5, -4, 3, 8, 1.5);
    ctx.fill();
    ctx.restore();
  }

  function drawParticles(front) {
    for (const p of particles) {
      if (Boolean(p.front) !== front) continue;
      ctx.save();
      ctx.globalAlpha = Math.max(0, p.life / p.max);
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      ctx.fillStyle = p.color;
      roundRect(-p.w / 2, -p.h / 2, p.w, p.h, 2);
      ctx.fill();
      ctx.restore();
    }
  }

  function drawFloaters() {
    ctx.save();
    ctx.font = "700 22px Fredoka, Trebuchet MS, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (const f of floaters) {
      ctx.globalAlpha = Math.max(0, f.life / f.max);
      ctx.lineWidth = 4;
      ctx.strokeStyle = "#c2185b";
      ctx.fillStyle = "#fff";
      ctx.strokeText(f.text, f.x, f.y);
      ctx.fillText(f.text, f.x, f.y);
    }
    ctx.restore();
  }

  function drawScore() {
    if (mode === "menu" || (mode === "dead" && overReady)) return;
    ctx.save();
    ctx.translate(W / 2, 96);
    ctx.scale(scorePop, scorePop);
    ctx.font = "700 68px Fredoka, Trebuchet MS, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 8;
    ctx.lineJoin = "round";
    ctx.strokeStyle = "#c2185b";
    ctx.fillStyle = "#fff";
    const label = String(score);
    ctx.strokeText(label, 0, 0);
    ctx.fillText(label, 0, 0);
    ctx.restore();
  }

  function draw() {
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const targetW = Math.max(1, Math.round(rect.width * dpr));
    const targetH = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== targetW || canvas.height !== targetH) {
      canvas.width = targetW;
      canvas.height = targetH;
    }
    const shakeX = shake > 0.4 ? (Math.random() - 0.5) * shake : 0;
    const shakeY = shake > 0.4 ? (Math.random() - 0.5) * shake : 0;
    ctx.setTransform(canvas.width / W, 0, 0, canvas.height / H, 0, 0);
    ctx.translate(shakeX, shakeY);

    const theme = themeAt(mode === "menu" ? 0 : score);
    drawBackground(theme);
    for (const pipe of pipes) drawPipe(pipe);
    drawGround(theme);
    drawParticles(false);
    drawBird();
    drawParticles(true);
    drawFloaters();
    if (flash > 0.02) {
      ctx.fillStyle = `rgba(255,255,255,${Math.min(0.85, flash)})`;
      ctx.fillRect(-20, -20, W + 40, H + 40);
    }
    drawScore();
  }

  function act() {
    if (mode === "menu" || (mode === "dead" && overReady)) startGame();
    else if (mode === "play") flap();
    else if (mode === "pause") togglePause();
  }

  playBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    startGame();
  });
  againBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    startGame();
  });
  resumeBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (mode === "pause") togglePause();
  });
  muteBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    audio.muted = !audio.muted;
    save("sugarflap-muted", audio.muted ? "1" : "0");
    renderMute();
    if (!audio.muted) {
      audio.unlock();
      audio.flap();
    }
  });
  canvas.addEventListener("pointerdown", (e) => {
    if (e.target !== canvas) return;
    e.preventDefault();
    act();
  });

  window.addEventListener("keydown", (e) => {
    if (e.repeat) return;
    if (e.key === " " || e.key === "ArrowUp" || e.key === "w" || e.key === "W") {
      e.preventDefault();
      act();
    } else if (e.key === "p" || e.key === "P" || e.key === "Escape") {
      if (mode === "play" || mode === "pause") {
        e.preventDefault();
        togglePause();
      }
    } else if (e.key === "m" || e.key === "M") {
      muteBtn.click();
    }
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden && mode === "play") togglePause();
  });

  function frame(now) {
    if (!last) last = now;
    const dt = Math.min(0.033, (now - last) / 1000);
    last = now;
    update(dt);
    draw();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
