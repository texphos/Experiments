// Browser companion prototype UI. Mirrors the SwiftUI screens; all planning logic lives in core.js.
(function () {
  "use strict";
  const H = window.HearthdayCore;
  const cal = H.makeCalendar(false);
  const { MIN, HOUR, DAY } = H;
  const KEY = "hearthday-prototype-v1";
  const FREE_FORMULAS = 2, FREE_HISTORY = 5;

  // ---------- State ----------
  const defaults = () => ({
    settings: { blocks: H.typicalWeekdayWorker(), kitchenTempC: 21, usesF: false, starterNeedsFeed: true, preferredFeedRatio: "1:2:2", allowInoc: true, allowFeed: true, onboarded: false },
    formulas: [{ id: "country", name: "Everyday country loaf", flourGrams: 500, hydrationPercent: 72, starterPercent: 20, saltPercent: 2 }],
    session: null, history: [], samples: [], simOffset: 0,
  });
  // Mirrors AppState.repair(): anything unreadable is set aside rather than crashing the page or silently discarded.
  let loadNotice = null;
  function sanitize(raw) {
    const d = defaults();
    if (!raw || typeof raw !== "object") return d;
    const num = (v, [lo, hi], fb) => (typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : fb);
    const s = Object.assign({}, d.settings, raw.settings && typeof raw.settings === "object" ? raw.settings : {});
    s.kitchenTempC = num(s.kitchenTempC, H.LIMITS.tempC, d.settings.kitchenTempC);
    s.blocks = Array.isArray(s.blocks) ? s.blocks.filter((b) => b && typeof b === "object" && H.blockIsValid(b)) : d.settings.blocks;
    if (!H.FEED_RATIOS.includes(s.preferredFeedRatio)) s.preferredFeedRatio = d.settings.preferredFeedRatio;
    const formulas = Array.isArray(raw.formulas) ? raw.formulas.filter((f) => f && typeof f === "object" && !H.formulaProblems(f).length) : [];
    const rs = raw.session;
    const session = rs && typeof rs === "object" && rs.plan && Array.isArray(rs.plan.steps) && rs.plan.steps.length
      && rs.plan.steps.every((x) => x && typeof x.start === "number" && typeof x.end === "number") && rs.completed && typeof rs.completed === "object"
      && Array.isArray(rs.checkIns) ? rs : null;
    if (session && !session.id) session.id = `bake-${session.startedAt || 0}`;
    return {
      settings: s, formulas: formulas.length ? formulas : d.formulas, session,
      history: Array.isArray(raw.history) ? raw.history.filter((r) => r && typeof r.finishedAt === "number") : [],
      samples: Array.isArray(raw.samples) ? raw.samples.filter((x) => typeof x === "number" && Number.isFinite(x)) : [],
      simOffset: num(raw.simOffset, [0, 60 * DAY], 0),
    };
  }
  let state;
  try {
    const text = localStorage.getItem(KEY);
    state = sanitize(text ? JSON.parse(text) : null);
  } catch (e) {
    try { localStorage.setItem(`${KEY}-unreadable-${Date.now()}`, localStorage.getItem(KEY)); } catch (e2) { /* ignore */ }
    loadNotice = "Saved prototype data couldn’t be read, so it was set aside and Hearthday started fresh.";
    state = defaults();
  }
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* private mode: keep in memory */ } };

  const ui = { tab: "bake", page: 0, readyBy: null, tempC: null, feed: null, formulaId: null, result: null, planning: false, selected: 0, showResult: false, sheet: null, rise: 30, ciTemp: 21, ci: null, editBlock: null, rating: null, notes: "" };
  const now = () => Date.now() + state.simOffset;

  // ---------- Formatting ----------
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const time = (t) => new Date(t).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  function day(t) {
    const n = now();
    if (cal.startOfDay(t) === cal.startOfDay(n)) return new Date(t).getHours() >= 17 ? "Tonight" : "Today";
    if (cal.startOfDay(t) === cal.addDays(n, 1)) return "Tomorrow";
    return new Date(t).toLocaleDateString([], { weekday: "short" });
  }
  const dayTime = (t) => `${day(t)} ${time(t)}`;
  const lower = (s) => (/^(Today|Tonight|Tomorrow)/.test(s) ? s[0].toLowerCase() + s.slice(1) : s);
  const temp = (c) => (state.settings.usesF ? `${Math.round(c * 9 / 5 + 32)} °F` : `${Number.isInteger(c) ? c : c.toFixed(1)} °C`);
  const clockMin = (m) => time(cal.atMinute(now(), m));
  const WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const WDL = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  function weekdays(days) {
    const s = days.slice().sort().join(",");
    if (s === "1,2,3,4,5,6,7") return "Every day";
    if (s === "2,3,4,5,6") return "Weekdays";
    if (s === "1,7") return "Weekends";
    return days.slice().sort().map((d) => WD[d - 1]).join(", ");
  }
  const busyColor = (k) => (k === "sleep" ? "var(--night)" : k === "work" ? "var(--sage)" : "var(--plum)");
  const ICON = { feedStarter: "💧", starterRise: "⏳", mix: "✋", fold: "↻", bulk: "◷", shape: "◌", coldRetard: "❄", coldBulk: "❄", roomProof: "⌛", preheat: "♨", bake: "🔥" };

  // ---------- Domain helpers ----------
  const speedFactor = () => H.calibration.speedFactor(state.samples);
  const uncertainty = () => H.calibration.uncertainty(state.samples);
  const planningModel = () => ({}); // Pro applies calibration in the native app; the prototype shows free-tier behaviour.
  function insight() {
    const n = state.samples.length;
    if (!n) return null;
    const pct = Math.round((speedFactor() - 1) * 100);
    const bakes = n === 1 ? "1 bake" : `${n} bakes`;
    const dir = Math.abs(pct) < 5 ? "right in line with the textbook" : pct > 0 ? `about ${pct}% faster than the textbook` : `about ${-pct}% slower than the textbook`;
    if (n >= H.CAL.needed) return `Across ${bakes}, your dough has run ${dir}. Likely windows are now ±${Math.round(uncertainty() * 100)}%.`;
    const more = H.CAL.needed - n;
    return `After ${bakes}, your dough looks ${dir}. ${more} more “just right” ${more === 1 ? "bake" : "bakes"} before windows adjust.`;
  }
  function suggestions() {
    const n = now();
    const at = (off, h) => cal.atMinute(cal.addDays(n, off), h * 60);
    const oven = (H.PROCESS.preheatMinutes + H.PROCESS.bakeMinutes) * MIN;
    const tl = H.timeline(state.settings.blocks, n, n + 5 * DAY, cal);
    const seenDays = new Set();
    const list = [1, 2, 3, 4].flatMap((o) => [at(o, 10), at(o, 19), at(o, 12)])
      .filter((t) => t - n > 14 * HOUR && tl.isFree(t - oven, oven))
      .filter((t) => { const d = cal.startOfDay(t); if (seenDays.has(d)) return false; seenDays.add(d); return true; });
    return list.sort((a, b) => a - b).slice(0, 4);
  }
  const formula = () => state.formulas.find((f) => f.id === ui.formulaId) || state.formulas[0];

  function runPlan() {
    ui.planning = true; ui.showResult = true; ui.result = null; ui.selected = 0; render();
    setTimeout(() => {
      const s = state.settings;
      ui.result = H.plan({
        now: now(), readyBy: ui.readyBy, kitchenTempC: ui.tempC ?? s.kitchenTempC, formula: formula(),
        starterNeedsFeed: ui.feed ?? s.starterNeedsFeed, preferredFeedRatio: s.preferredFeedRatio,
        allowFeedRatioAdjustment: s.allowFeed, allowInoculationAdjustment: s.allowInoc, blocks: s.blocks, model: planningModel(),
      }, cal);
      ui.planning = false; render();
    }, 30);
  }

  // ---------- Components ----------
  function spanBar(start, end, blocks, steps, marker, tall) {
    const total = Math.max(end - start, 1);
    const pct = (t) => Math.min(Math.max((t - start) / total, 0), 1) * 100;
    const busy = H.intervals(blocks, start, end, cal).map((i) => `<span class="hatch" style="--c:${busyColor(i.kind)};left:${pct(i.start)}%;width:${pct(i.end) - pct(i.start)}%"></span>`).join("");
    const st = steps.map((s) => `<span class="step ${s.kind === "bake" || s.kind === "preheat" ? "oven" : ""}" style="left:${pct(s.start)}%;width:${pct(s.end) - pct(s.start)}%"></span>`).join("");
    const m = marker && marker > start && marker < end ? `<span class="now" style="left:${pct(marker)}%"></span>` : "";
    return `<div class="bar ${tall ? "tall" : ""}" aria-hidden="true">${busy}${st}${m}</div>`;
  }
  function weekRibbon(blocks) {
    const n = now();
    let rows = "";
    for (let i = 0; i < 7; i++) {
      const d0 = cal.addDays(n, i), d1 = cal.addDays(n, i + 1);
      rows += `<div class="row"><span class="day">${i === 0 ? "Today" : WD[cal.weekday(d0) - 1]}</span>${spanBar(d0, d1, blocks, [])}</div>`;
    }
    const summary = blocks.map((b) => `${b.label}, ${weekdays(b.weekdays)}, ${clockMin(b.startMinute)} to ${clockMin(b.endMinute)}`).join(". ");
    return `<div class="week" role="img" aria-label="Your busy week. ${esc(summary)}">${rows}<div class="axis"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>12a</span></div></div>`;
  }
  function dayRibbon(plan, marker) {
    return `<div class="card" role="img" aria-label="Timeline from ${dayTime(plan.firstStepAt)} to ${dayTime(plan.readyAt)}, ${plan.steps.filter((s) => s.attended).length} hands-on steps">
      ${spanBar(plan.firstStepAt, plan.readyAt, state.settings.blocks, plan.steps.filter((s) => s.attended), marker, true)}
      <div class="row between small muted" style="margin-top:6px"><span>${dayTime(plan.firstStepAt)}</span><span>${dayTime(plan.readyAt)}</span></div>
      <div class="legend"><span><i style="background:var(--crust)"></i>Hands on</span><span><i style="background:var(--ember)"></i>Oven</span><span><i class="hatch" style="--c:var(--night)"></i>Busy</span></div>
    </div>`;
  }
  function stepList(plan, session) {
    const items = plan.steps.map((s) => {
      const done = session && session.completed[s.id] != null;
      return `<li class="${s.attended ? "attended" : "passive"} ${done ? "done" : ""}">
        <span class="dot" aria-hidden="true">${done ? "✓" : ICON[s.kind]}</span>
        <div><div class="row between"><span class="title">${esc(s.title)}</span><span class="small muted clock">${dayTime(s.start)}</span></div>
        <p class="small muted">${esc(s.detail)}</p>${s.attended ? "" : `<p class="small muted">Passive · ${H.compact(Math.round((s.end - s.start) / MIN))}</p>`}
        <span class="sr-only">${done ? "Done." : ""} ${s.attended ? "Hands-on." : "Passive."}</span></div></li>`;
    }).join("");
    return `<div class="card"><ol class="steps">${items}</ol></div>`;
  }
  const stepper = (action, label, value) => `<div class="field"><span class="clock" style="font-size:22px">${value}</span><div class="stepper" role="group" aria-label="${label}"><button data-action="${action}" data-d="-1" aria-label="Decrease ${label}">−</button><button data-action="${action}" data-d="1" aria-label="Increase ${label}">+</button></div></div>`;
  const toggle = (action, label, on) => `<div class="field"><span>${label}</span><button class="switch" role="switch" aria-checked="${on}" aria-label="${label}" data-action="${action}"></button></div>`;
  const stateMessage = (icon, title, msg) => `<div style="text-align:center;padding:24px 8px"><div style="font-size:38px" aria-hidden="true">${icon}</div><h2>${title}</h2><p class="muted">${msg}</p></div>`;
  const logo = `<svg class="logo" viewBox="0 0 100 100" aria-hidden="true"><ellipse cx="50" cy="56" rx="40" ry="28" fill="var(--crust)"/><path d="M32 62 Q44 44 68 44" stroke="var(--flour)" stroke-width="5" fill="none" stroke-linecap="round"/><rect x="4" y="86" width="92" height="4" fill="var(--ember)"/></svg>`;

  // ---------- Screens ----------
  function onboarding() {
    const s = state.settings;
    const dots = `<div class="dots" role="img" aria-label="Step ${ui.page + 1} of 3">${[0, 1, 2].map((i) => `<span class="${i === ui.page ? "on" : ""}"></span>`).join("")}</div>`;
    let body = "";
    if (ui.page === 0) {
      body = `${logo}<h1>Sourdough that fits around your week.</h1>
        <p class="muted">Tell Hearthday when you’re asleep or at work. Pick when you want warm bread. It works backwards from there, and only asks for your hands when you’re free.</p>
        <p>🌙 No folds at 3 AM, no shaping during a meeting.</p><p>📏 Dough running fast or slow? A 10-second check-in re-plans the rest.</p><p>🔒 No account. Your bakes stay on this device.</p>
        <p class="small muted">Times are estimates. Dough is alive and kitchens vary; Hearthday shows a likely window and helps you adjust, but can’t promise the exact minute.</p>`;
    } else if (ui.page === 1) {
      body = `<h1>When are you busy?</h1><p class="muted">Hearthday won’t schedule hands-on steps in these times.</p>${weekRibbon(s.blocks)}${blockList()}`;
    } else {
      body = `<h1>Your kitchen and starter</h1>
        <div class="card"><h3>Usual kitchen temperature</h3>${stepper("temp", "kitchen temperature", temp(s.kitchenTempC))}${toggle("toggleF", "Show °F", s.usesF)}
        <p class="small muted">Temperature is the biggest driver of timing. A rough guess is fine.</p></div>
        <div class="card"><h3>Starter</h3><div class="segmented"><button data-action="starter" data-v="1" aria-pressed="${s.starterNeedsFeed}">Lives in the fridge</button><button data-action="starter" data-v="0" aria-pressed="${!s.starterNeedsFeed}">Active on the counter</button></div>
        <p class="small muted" style="margin-top:8px">${s.starterNeedsFeed ? "Hearthday will schedule a feed and choose a feed ratio so it peaks when you can mix." : "Hearthday will assume your starter is ready to use when you mix."}</p></div>`;
    }
    return `${dots}<div class="stack">${body}<button class="btn" data-action="obNext">${ui.page === 2 ? "Plan my first bake" : "Continue"}</button>${ui.page ? `<button class="btn-link" data-action="obBack">Back</button>` : ""}</div>`;
  }

  function blockList() {
    const b = state.settings.blocks;
    const rows = b.map((x, i) => `<button class="card row" style="text-align:left;width:100%" data-action="editBlock" data-i="${i}" aria-label="${esc(x.label)}, ${weekdays(x.weekdays)}, ${clockMin(x.startMinute)} to ${clockMin(x.endMinute)}. Edit">
      <span class="hatch" style="--c:${busyColor(x.kind)};width:10px;height:36px;border-radius:5px;flex:none"></span>
      <span style="flex:1"><strong>${esc(x.label)}</strong><br><span class="small muted">${weekdays(x.weekdays)} · ${clockMin(x.startMinute)}–${clockMin(x.endMinute)}</span></span><span class="muted" aria-hidden="true">›</span></button>`).join("");
    const empty = b.length ? "" : stateMessage("🗓", "No busy times", "Hearthday will happily schedule folds at 4 AM. Add when you sleep so it won’t.");
    return `<div class="stack">${empty}${rows}<button class="btn-secondary" data-action="addBlock">＋ Add busy time</button></div>`;
  }

  function home() {
    const s = state.settings;
    if (ui.readyBy == null) ui.readyBy = suggestions()[0] || now() + DAY;
    const chips = suggestions().map((t) => `<button class="chip" data-action="pick" data-t="${t}" aria-pressed="${Math.abs(t - ui.readyBy) < MIN}">${dayTime(t)}</button>`).join("");
    const f = formula();
    const ins = insight();
    const fsel = state.formulas.length > 1
      ? `<div class="field"><span class="muted">Formula</span><select data-action="formula" aria-label="Formula">${state.formulas.map((x) => `<option value="${x.id}" ${x.id === f.id ? "selected" : ""}>${esc(x.name)}</option>`).join("")}</select></div>`
      : `<div class="field"><span class="muted">Formula</span><span>${esc(f.name)}</span></div>`;
    const toLocalInput = (t) => { const d = new Date(t - new Date(t).getTimezoneOffset() * MIN); return d.toISOString().slice(0, 16); };
    return `<div class="stack">
      <div><h1>When do you want bread?</h1><p class="small muted">Out of the oven by</p>
        <div class="big-time clock" aria-live="polite">${dayTime(ui.readyBy)}</div></div>
      <div class="chips" role="group" aria-label="Suggested times">${chips}</div>
      <label class="field small"><span class="muted">Or choose</span><input type="datetime-local" data-action="custom" value="${toLocalInput(ui.readyBy)}" aria-label="Ready by"></label>
      <div class="card stack" style="gap:6px">${fsel}<hr>${stepper("ptemp", "kitchen temperature for this bake", temp(ui.tempC ?? s.kitchenTempC))}<hr>${toggle("pfeed", "Starter needs a feed first", ui.feed ?? s.starterNeedsFeed)}</div>
      <button class="btn" data-action="plan">Plan it</button>
      ${ins ? `<div class="card"><h3 style="color:var(--crust)">What your bakes say</h3><p>${ins}</p><p class="small muted">Hearthday Pro applies this to your plans.</p></div>`
        : `<div class="card row" style="align-items:flex-start"><span aria-hidden="true">✨</span><p class="muted small">After each bake, tell Hearthday whether the dough was ready at shaping. It learns how fast your kitchen really runs.</p></div>`}
      <div class="card"><h3>Your week</h3>${weekRibbon(s.blocks)}</div>
    </div>`;
  }

  function planResult() {
    const back = `<button class="btn-link" data-action="closeResult" style="color:var(--crust)">‹ Back</button>`;
    if (ui.planning || !ui.result) return `${back}<p class="muted" style="text-align:center;padding:80px 0" role="status">Finding a plan that fits…</p>`;
    const r = ui.result;
    if (r.invalid) {
      return `${back}<div class="card stack" data-testid="plan-invalid">${stateMessage("✎", "Something needs fixing first", "Hearthday won’t guess a plan from values it can’t trust.")}
        <ul class="problems">${r.invalid.map((c) => `<li>${esc(H.problemMessage(c))}</li>`).join("")}</ul>
        <button class="btn-secondary" data-action="closeResult">Change the details</button></div>`;
    }
    if (!r.feasible) {
      return `${back}<div class="card stack">${stateMessage("⚠︎", "That time doesn’t fit your week", esc(H.infeasibilityMessage(r)))}
        ${r.earliestFeasibleReadyAt ? `<button class="btn" data-action="earliest" data-t="${r.earliestFeasibleReadyAt}">Earliest that fits: ${dayTime(r.earliestFeasibleReadyAt)}</button>` : `<p class="muted small">No workable plan in the next three days. Try freeing up a busy time in Settings.</p>`}
        <p class="small muted" style="text-align:center">Hearthday never schedules hands-on steps during your busy times. It says no rather than hand you an alarm at 3 AM.</p></div>`;
    }
    const plans = [r.primary].concat(r.alternatives);
    const p = plans[Math.min(ui.selected, plans.length - 1)];
    const seg = plans.length > 1 ? `<div class="segmented" role="group" aria-label="Plan options">${plans.map((_, i) => `<button data-action="selectPlan" data-i="${i}" aria-pressed="${i === ui.selected}">${i ? `Option ${i + 1}` : "Best fit"}</button>`).join("")}</div>` : "";
    const handsOn = Math.round(p.steps.filter((s) => s.attended).reduce((a, s) => a + s.end - s.start, 0) / MIN);
    const f = p.formula;
    return `${back}<div class="stack">${seg}
      <div><h2>Start ${lower(dayTime(p.firstStepAt))}</h2><p class="muted">Bread out ${lower(dayTime(p.readyAt))} · about ${H.compact(handsOn)} hands-on</p>
      <div>${H.leverSummary(p).map((x) => `<span class="tag">${esc(x)}</span>`).join("")}</div>
      <p class="small muted">${f.flourGrams} g flour · ${Math.round(f.flourGrams * f.hydrationPercent / 100)} g water · ${Math.round(f.flourGrams * p.inoculationPercent / 100)} g starter · ${Math.round(f.flourGrams * f.saltPercent / 100)} g salt</p></div>
      ${dayRibbon(p)}${stepList(p)}
      <p class="small muted">ⓘ Bulk is estimated at ${H.halfHours(p.expectedBulkHours)} h, give or take ${Math.round(p.uncertainty * 100)}%. Flour, starter strength and a warm afternoon all shift it. A quick check-in during bulk re-plans the rest if it drifts.</p>
      <button class="btn" data-action="start">Start this bake</button></div>`;
  }

  function live() {
    const s = state.session, n = now();
    const conflicts = H.session.upcomingConflicts(s, n, state.settings.blocks, cal);
    const next = H.session.nextAttendedStep(s);
    const passive = H.session.passiveStep(s, n);
    const inBulk = H.session.isInBulk(s);
    let out = `<div class="row between"><h2>${esc(s.plan.formula.name)}</h2><button class="btn-link" data-action="endMenu" aria-label="More options">•••</button></div>`;
    if (conflicts.length) {
      out += `<div class="card banner-warn"><h3 style="color:var(--warning)">⚠︎ Heads up</h3>${conflicts.map((c) => `<p>${esc(c.step.title)} at ${lower(dayTime(c.step.start))} now overlaps “${esc(c.busyLabel)}”.</p>`).join("")}
        ${inBulk ? `<button class="btn-secondary" data-action="checkin">Check the dough and re-plan</button>` : ""}</div>`;
    }
    const status = H.session.status(s, n);
    if (status.kind === "baked") {
      out += `<div class="card">${stateMessage("🍞", "Bread’s out", "Let it cool at least an hour before slicing. Then tell Hearthday how it went.")}<button class="btn" data-action="finish">Log this bake</button></div>`;
    } else if (status.kind === "stale") {
      out += `<div class="card stack" data-testid="live-stale">${stateMessage("🕰", "Did this bake finish?", `It was planned to come out ${lower(dayTime(s.plan.readyAt))}. Log how it went, or abandon it to plan a new one.`)}
        <button class="btn" data-action="finish">Log this bake</button><button class="btn-secondary" style="color:var(--warning)" data-action="abandon">Abandon this bake</button></div>`;
    } else if (next) {
      const due = status.kind !== "upcoming";
      const late = status.kind === "overdue";
      const label = late ? `Was due ${lower(dayTime(next.start))} · ${H.compact(status.minutesLate)} ago` : due ? "Now" : `Next, in ${H.compact(Math.max(0, Math.round((next.start - n) / MIN)))}`;
      out += `<div class="card stack" style="gap:8px" ${late ? 'data-testid="live-overdue"' : ""}><span class="small" style="font-weight:600;color:${late ? "var(--warning)" : due ? "var(--ember)" : "var(--ash)"}">${label}</span>
        <h2>${esc(next.title)}</h2><p class="muted">${esc(next.detail)}</p>
        ${late && next.kind === "shape" && inBulk ? `<p class="small">The dough may have gone past its best while you were away. Check it before shaping; if it’s very slack, shape gently and fridge it.</p>` : ""}        ${next.likelyStart ? `<p class="small muted">👁 Likely ready ${time(next.likelyStart)}–${time(next.likelyEnd)}. Go by the dough, not the clock.</p>` : ""}
        <p class="clock" style="color:var(--crust)">${dayTime(next.start)} · ${H.compact(Math.round((next.end - next.start) / MIN))}</p>
        <button class="btn" data-action="done" data-id="${next.id}" aria-label="Mark ${esc(next.title)} done">${due ? "Done" : "Done early"}</button></div>`;
    }
    if (s.completed.shape != null && !s.shapeReadiness) {
      out += `<div class="card"><h3>When you shaped, the dough felt…</h3><div class="row">${[["under", "🐢 Under"], ["justRight", "✓ Just right"], ["over", "🐇 Over"]].map(([v, l]) => `<button class="btn-secondary" style="flex:1" data-action="ready" data-v="${v}">${l}</button>`).join("")}</div>
        <p class="small muted" style="margin-top:8px">Only “just right” bakes without a fridge pause teach Hearthday your kitchen’s speed; the others are noted in your journal.</p></div>`;
    }
    if (passive) {
      out += `<div class="card row"><span style="font-size:24px;color:var(--night)" aria-hidden="true">${passive.kind === "coldRetard" || passive.kind === "coldBulk" ? "❄" : "⏳"}</span><div><h3>${esc(passive.title)}</h3><p class="small muted">Until about ${dayTime(passive.end)} · ${H.compact(Math.max(0, Math.round((passive.end - n) / MIN)))} left</p></div></div>`;
    }
    if (inBulk) out += `<button class="btn-secondary" data-action="checkin">📏 Check the dough</button>`;
    out += dayRibbon(s.plan, n) + stepList(s.plan, s);
    if (s.replanCount) out += `<p class="small muted">Re-planned ${s.replanCount}× · originally ${lower(dayTime(s.originalReadyAt))}</p>`;
    return `<div class="stack">${out}</div>`;
  }

  function journal() {
    const n = state.samples.length;
    const ins = insight();
    const sorted = state.history.slice().sort((a, b) => b.finishedAt - a.finishedAt);
    const visible = sorted.slice(0, FREE_HISTORY);
    const hidden = sorted.length - visible.length;
    const bars = [0, 1, 2].map((i) => `<span style="flex:1;height:8px;border-radius:4px;background:${i < n ? "var(--crust)" : "var(--hairline)"}"></span>`).join("");
    const rows = visible.map((r) => {
      const held = r.replanCount === 0 && Math.abs(r.actualReadyAt - r.originalReadyAt) <= 30 * MIN;
      const tags = [held ? `<span class="tag sage">✓ Plan held</span>` : r.replanCount ? `<span class="tag plum">Re-planned ${r.replanCount}×</span>` : "",
        r.shapeReadiness ? `<span class="tag ${r.shapeReadiness === "justRight" ? "sage" : "warn"}">${{ under: "Under at shaping", justRight: "Just right", over: "Over at shaping" }[r.shapeReadiness]}</span>` : "",
        r.rating ? `<span class="tag" aria-label="${r.rating} stars">${"★".repeat(r.rating)}</span>` : ""].join("");
      return `<div class="card"><div class="row between"><h3>${esc(r.formulaName)}</h3><span class="small muted">${new Date(r.finishedAt).toLocaleDateString([], { month: "short", day: "numeric" })}</span></div>
        <div>${tags}</div><p class="small muted">${r.proofMode === "fridge" ? "Fridge proof" : "Room proof"} · ${Math.round(r.inoculationPercent)}% starter · ${temp(r.tempC)}${r.actualBulkHours ? ` · bulk ${H.halfHours(r.actualBulkHours)} h` : ""}</p>${r.notes ? `<p>${esc(r.notes)}</p>` : ""}</div>`;
    }).join("");
    return `<div class="stack"><h1>Journal</h1>
      <div class="card"><h3>Your kitchen’s speed</h3><div class="row" role="img" aria-label="${Math.min(n, 3)} of 3 calibration bakes" style="margin:8px 0">${bars}</div>
      <p class="${ins ? "" : "muted"}">${ins || "Log a bake where the dough felt “just right” at shaping and Hearthday starts learning how your starter, flour and kitchen compare to the textbook."}</p>
      ${ins ? `<p class="small muted">Plans use the textbook model until Pro is on. What’s learned is never locked away.</p>` : ""}</div>
      ${state.history.length ? rows : `<div class="card">${stateMessage("📖", "Your journal is empty", "Finished bakes land here with how close the plan came, how the dough felt at shaping, and your notes.")}</div>`}
      ${hidden > 0 ? `<button class="btn-link" data-action="pro">${hidden} older ${hidden === 1 ? "bake is" : "bakes are"} kept safely. Pro shows your full journal.</button>` : ""}</div>`;
  }

  function settings() {
    const s = state.settings;
    return `<div class="stack"><h1>Settings</h1>
      <h3>Busy times</h3>${weekRibbon(s.blocks)}${blockList()}<p class="small muted">Hands-on steps are never scheduled inside these.</p>
      <div class="card stack" style="gap:4px"><h3>Kitchen and starter</h3>${stepper("temp", "kitchen temperature", temp(s.kitchenTempC))}${toggle("toggleF", "Show °F", s.usesF)}${toggle("toggleFeed", "Starter usually needs a feed", s.starterNeedsFeed)}
        <label class="field"><span>Usual feed ratio</span><select data-action="ratio">${H.FEED_RATIOS.map((r) => `<option ${r === s.preferredFeedRatio ? "selected" : ""}>${r}</option>`).join("")}</select></label></div>
      <div class="card stack" style="gap:4px"><h3>Let Hearthday adjust</h3>${toggle("toggleInoc", "Adjust starter amount", s.allowInoc)}${toggle("toggleRatio", "Adjust feed ratio", s.allowFeed)}
        <p class="small muted">Less starter slows the dough; a leaner feed slows the starter. Both help a bake fit around a work day.</p></div>
      <div class="card"><h3>Formulas</h3>${state.formulas.map((f) => `<p>${esc(f.name)}<br><span class="small muted">${f.flourGrams} g · ${f.hydrationPercent}% water · ${f.starterPercent}% starter</span></p>`).join("")}
        <button class="btn-secondary" data-action="${state.formulas.length < FREE_FORMULAS ? "addFormula" : "pro"}">＋ Add formula${state.formulas.length < FREE_FORMULAS ? "" : " (Pro)"}</button></div>
      <button class="btn-secondary" data-action="pro">What Pro adds ›</button>
      <div class="card"><h3>Privacy</h3><p class="small muted">No account, no analytics, no tracking. Your schedule and bakes are stored only on the device.</p></div></div>`;
  }

  // ---------- Sheets ----------
  function sheet() {
    if (!ui.sheet) return "";
    let title = "", body = "", confirm = "";
    if (ui.sheet === "checkin") {
      const target = H.targetRisePercent(ui.ciTemp);
      const base = 0.35, per = (1 - base - 0.05) / 150;
      title = "Check the dough";
      body = `<div class="row" style="align-items:flex-end;gap:20px"><div class="jar" aria-hidden="true"><div class="fill" style="height:${(base + per * ui.rise) * 100}%"></div><div class="target" style="bottom:${(base + per * target) * 100}%"></div><div class="mark" style="bottom:${base * 100}%"></div></div>
        <div><div class="clock" style="font-size:34px">${ui.rise}%</div><p class="muted">rise since mixing</p><p class="small muted">Aim ≈ ${Math.round(target)}% at this temperature</p></div></div>
        <input type="range" min="0" max="150" step="5" value="${ui.rise}" data-action="rise" aria-label="Rise" aria-valuetext="${ui.rise} percent">
        <p class="small muted">Easiest in a straight-sided container: mark the level after mixing and compare. Rise targets are a guide from home-baker tables, not a rule; trust bubbles, jiggle and domed edges too.</p>
        <div class="card">${stepper("citemp", "dough temperature", temp(ui.ciTemp))}</div>
        <button class="btn" data-action="replan">${ui.ci ? "Update options" : "Re-plan from here"}</button>`;
      if (ui.ci) {
        if (ui.ci.problems && ui.ci.problems.length) {
          body += `<div class="card" data-testid="checkin-invalid"><h3>Check that reading</h3><ul class="problems">${ui.ci.problems.map((c) => `<li>${esc(H.problemMessage(c))}</li>`).join("")}</ul></div>`;
        } else body += `<h3 data-testid="checkin-summary">${esc(ui.ci.summary)}</h3>`;
        if (!ui.ci.options.length && !(ui.ci.problems && ui.ci.problems.length)) body += stateMessage("?", "No clean way to re-plan", "Every option would put a hands-on step in your busy times. Keep an eye on the dough; fridging it is almost always the safest pause.") + `<button class="btn-secondary" data-action="logCheckin">Log this check-in</button>`;
        body += ui.ci.options.map((o, i) => `<button class="option ${o.recommended ? "recommended" : ""}" data-action="choose" data-i="${i}">
          <div class="row between"><h3>${esc(o.title)}</h3>${o.recommended ? `<span class="tag">★ Suggested</span>` : ""}</div>
          <p class="small muted">${esc(o.detail)}</p><p class="small" style="color:var(--crust);font-weight:500">${o.shapeAt ? `Shape ${lower(dayTime(o.shapeAt))} · ` : ""}Bread ${lower(dayTime(o.readyAt))}</p>
          ${o.conflictLabel ? `<p class="small" style="color:var(--warning)">⚠︎ Needs you during “${esc(o.conflictLabel)}”</p>` : ""}</button>`).join("");
      }
    } else if (ui.sheet === "finish") {
      title = "Log this bake"; confirm = `<button data-action="saveFinish">Save</button>`;
      const s = state.session;
      body = `${s.completed.shape != null && !s.shapeReadiness ? `<div class="card"><h3>At shaping the dough was</h3><div class="segmented">${[["under", "Under"], ["justRight", "Just right"], ["over", "Over"]].map(([v, l]) => `<button data-action="ready" data-v="${v}" aria-pressed="false">${l}</button>`).join("")}</div></div>` : ""}
        <div class="card"><h3>How was it?</h3><div class="stars row" role="group" aria-label="Rating">${[1, 2, 3, 4, 5].map((i) => `<button data-action="star" data-i="${i}" aria-label="${i} star${i > 1 ? "s" : ""}" aria-pressed="${ui.rating === i}">${(ui.rating || 0) >= i ? "★" : "☆"}</button>`).join("")}</div></div>
        <div class="card"><h3>Notes</h3><input type="text" data-action="notes" value="${esc(ui.notes)}" placeholder="Crumb, crust, what you’d change…" style="width:100%" aria-label="Notes"></div>`;
    } else if (ui.sheet === "end") {
      title = "This bake";
      body = `<button class="btn-secondary" data-action="finish">Finish now and log it</button><button class="btn-secondary" style="color:var(--warning)" data-action="abandon">Abandon this bake</button><p class="small muted">Abandoning cancels reminders and adds nothing to your journal.</p>`;
    } else if (ui.sheet === "block") {
      const b = ui.editBlock;
      const blocking = H.blockProblems(b).filter((c) => c !== "busyLabelEmpty");
      title = b.isNew ? "New busy time" : "Edit busy time"; confirm = `<button data-action="saveBlock" ${blocking.length ? "disabled" : ""}>Save</button>`;
      const hm = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
      body = `<div class="card stack" style="gap:6px"><input type="text" data-action="blabel" value="${esc(b.label)}" placeholder="Label (e.g. School run)" aria-label="Label">
        <div class="segmented">${["sleep", "work", "other"].map((k) => `<button data-action="bkind" data-v="${k}" aria-pressed="${b.kind === k}">${k[0].toUpperCase() + k.slice(1)}</button>`).join("")}</div>
        <label class="field"><span>Starts</span><input type="time" data-action="bstart" value="${hm(b.startMinute)}"></label>
        <label class="field"><span>Ends</span><input type="time" data-action="bend" value="${hm(b.endMinute)}"></label>
        ${blocking.includes("busyZeroLength") ? `<p class="small" style="color:var(--warning)" role="alert">${H.problemMessage("busyZeroLength")}</p>`
          : `<p class="small muted">${b.endMinute < b.startMinute ? "Ends the next day. " : ""}Times follow your iPhone’s clock, including daylight-saving changes.</p>`}</div>
        <div class="card"><h3>Starts on</h3><div class="row" style="gap:4px">${[1, 2, 3, 4, 5, 6, 7].map((d) => `<button class="chip" style="flex:1;padding:0" data-action="bday" data-d="${d}" aria-pressed="${b.weekdays.includes(d)}" aria-label="${WDL[d - 1]}">${WD[d - 1][0]}</button>`).join("")}</div>
        ${b.weekdays.length ? "" : `<p class="small" style="color:var(--warning)" role="alert">${H.problemMessage("busyNoDays")}</p>`}</div>
        ${b.isNew ? "" : `<button class="btn-secondary" style="color:var(--warning)" data-action="deleteBlock">Delete busy time</button>`}`;
    } else if (ui.sheet === "pro") {
      title = "Hearthday Pro";
      body = `<p class="muted">Plans that learn your kitchen.</p>
        <div class="card"><p><strong>Personal timing.</strong> Your logged bakes adjust future plans and narrow the likely-ready window.</p><p><strong>Unlimited formulas.</strong> Free includes ${FREE_FORMULAS}.</p><p><strong>Full journal.</strong> Free shows your last ${FREE_HISTORY} bakes; older ones are kept, never deleted.</p></div>
        <p><strong>Always free:</strong> <span class="muted">planning around your busy times, live check-ins and re-planning, reminders, and seeing what calibration has learned.</span></p>
        <button class="btn" disabled>Unlock for $9.99 (proposed price)</button>
        <p class="small muted">One-time purchase, no subscription. In this prototype the button is disabled: purchases only happen through StoreKit in the native app, and nothing is sold here.</p>`;
    }
    return `<div class="sheet-backdrop" data-action="closeSheet"><div class="sheet" role="dialog" aria-modal="true" aria-label="${title}" data-stop>
      <div class="sheet-head"><button data-action="closeSheet">${confirm ? "Cancel" : "Close"}</button><strong>${title}</strong>${confirm || "<span style='width:44px'></span>"}</div>
      <div class="stack">${body}</div></div></div>`;
  }

  // ---------- Render ----------
  const screen = document.getElementById("screen");
  const tabs = document.getElementById("tabs");
  function render() {
    const focusedAction = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.action : null;
    let html;
    if (!state.settings.onboarded) html = onboarding();
    else if (ui.tab === "journal") html = journal();
    else if (ui.tab === "settings") html = settings();
    else if (state.session) html = live();
    else if (ui.showResult) html = planResult();
    else html = home();
    screen.innerHTML = html + sheet();
    tabs.hidden = !state.settings.onboarded;
    tabs.innerHTML = [["bake", "🔥", "Bake"], ["journal", "📖", "Journal"], ["settings", "⚙︎", "Settings"]]
      .map(([id, ico, label]) => `<button role="tab" data-tab="${id}" aria-selected="${ui.tab === id}"><span class="ico" aria-hidden="true">${ico}</span>${label}</button>`).join("");
    document.getElementById("simNow").textContent = `${dayTime(now())}${state.simOffset ? " (simulated)" : ""}`;
    renderReminders();
    if (loadNotice) { screen.insertAdjacentHTML("afterbegin", `<div class="card banner-warn" role="alert">${esc(loadNotice)}</div>`); }
    if (focusedAction === "rise") { const el = screen.querySelector('[data-action="rise"]'); if (el) el.focus(); }
  }

  let remindersChangedAt = null;
  function renderReminders() {
    const el = document.getElementById("reminders");
    if (!el) return;
    const s = state.session;
    const list = s ? H.session.reminders(s, now(), state.settings.blocks, cal) : [];
    if (!s) { el.innerHTML = `<p class="sim-help">No bake in progress, so nothing is scheduled.</p>`; return; }
    if (!list.length) { el.innerHTML = `<p class="sim-help">No reminders left for this bake.</p>`; return; }
    const changed = remindersChangedAt != null && now() - remindersChangedAt < 2 * MIN;
    el.innerHTML = `${changed ? `<p class="reminders-updated" data-testid="reminders-updated">Replaced for the re-planned bake</p>` : ""}
      <ol class="reminders" data-testid="reminders">${list.slice(0, 8).map((r) => `<li><span class="clock">${esc(dayTime(r.fireAt))}</span> ${esc(r.title)}</li>`).join("")}</ol>
      ${list.length > 8 ? `<p class="sim-help">and ${list.length - 8} more</p>` : ""}`;
  }

  function update(fn) { fn(); loadNotice = null; save(); render(); }

  function finishBake() {
    const s = state.session, n = now();
    if (s.completed.bake == null) H.session.complete(s, "bake", n);
    const sample = H.session.calibrationSample(s);
    if (sample) state.samples = H.calibration.record(state.samples, sample);
    state.history.push({
      formulaName: s.plan.formula.name, proofMode: s.plan.proofMode, inoculationPercent: s.plan.inoculationPercent, tempC: H.session.averageTempC(s),
      originalReadyAt: s.originalReadyAt, actualReadyAt: s.finishedAt || n, finishedAt: s.finishedAt || n, replanCount: s.replanCount,
      shapeReadiness: s.shapeReadiness, rating: ui.rating, notes: ui.notes, actualBulkHours: H.session.actualBulkHours(s),
    });
    state.session = null; ui.rating = null; ui.notes = ""; ui.showResult = false; ui.result = null;
  }

  // ---------- Events ----------
  document.addEventListener("click", (e) => {
    const tab = e.target.closest("[data-tab]");
    if (tab) { ui.tab = tab.dataset.tab; ui.sheet = null; render(); return; }
    const sim = e.target.closest("[data-sim]");
    if (sim) { simulate(sim.dataset.sim); return; }
    const el = e.target.closest("[data-action]");
    if (!el) return;
    if (el.classList.contains("sheet-backdrop") && e.target.closest("[data-stop]")) return;
    const a = el.dataset.action, s = state.settings;
    const tempStep = s.usesF ? 5 / 9 : 0.5;
    const clampT = (v) => Math.min(32, Math.max(14, Math.round(v * 100) / 100));
    switch (a) {
      case "obNext": if (ui.page < 2) { ui.page++; render(); } else update(() => { s.onboarded = true; }); break;
      case "obBack": ui.page--; render(); break;
      case "temp": update(() => { s.kitchenTempC = clampT(s.kitchenTempC + tempStep * +el.dataset.d); }); break;
      case "ptemp": ui.tempC = clampT((ui.tempC ?? s.kitchenTempC) + tempStep * +el.dataset.d); render(); break;
      case "citemp": ui.ciTemp = clampT(ui.ciTemp + tempStep * +el.dataset.d); ui.ci = null; render(); break;
      case "toggleF": update(() => { s.usesF = !s.usesF; }); break;
      case "toggleFeed": update(() => { s.starterNeedsFeed = !s.starterNeedsFeed; }); break;
      case "toggleInoc": update(() => { s.allowInoc = !s.allowInoc; }); break;
      case "toggleRatio": update(() => { s.allowFeed = !s.allowFeed; }); break;
      case "starter": update(() => { s.starterNeedsFeed = el.dataset.v === "1"; }); break;
      case "pfeed": ui.feed = !(ui.feed ?? s.starterNeedsFeed); render(); break;
      case "pick": ui.readyBy = +el.dataset.t; render(); break;
      case "plan": runPlan(); break;
      case "earliest": ui.readyBy = +el.dataset.t; runPlan(); break;
      case "closeResult": ui.showResult = false; render(); break;
      case "selectPlan": ui.selected = +el.dataset.i; render(); break;
      case "start": {
        const r = ui.result, p = [r.primary].concat(r.alternatives)[ui.selected];
        update(() => { state.session = H.newSession(p, now()); ui.showResult = false; });
        break;
      }
      case "done": update(() => H.session.complete(state.session, el.dataset.id, now())); break;
      case "ready": update(() => { state.session.shapeReadiness = el.dataset.v; }); break;
      case "checkin":
        ui.sheet = "checkin"; ui.ci = null;
        ui.ciTemp = state.session.checkIns.length ? state.session.checkIns[state.session.checkIns.length - 1].tempC : state.session.plan.kitchenTempC;
        render(); break;
      case "replan":
        ui.ci = H.checkIn(state.session, now(), ui.rise, ui.ciTemp, s.blocks, cal, planningModel());
        ui.ciAt = now(); render(); break;
      case "choose": {
        const o = ui.ci.options[+el.dataset.i];
        remindersChangedAt = now();
        update(() => { state.session.checkIns.push({ at: ui.ciAt, risePercent: ui.rise, tempC: ui.ciTemp }); H.session.apply(state.session, o); ui.sheet = null; ui.ci = null; });
        break;
      }
      case "logCheckin": update(() => { state.session.checkIns.push({ at: ui.ciAt, risePercent: ui.rise, tempC: ui.ciTemp }); ui.sheet = null; }); break;
      case "endMenu": ui.sheet = "end"; render(); break;
      case "finish": ui.sheet = "finish"; render(); break;
      case "abandon": if (confirm("Abandon this bake? Reminders are cancelled and nothing is added to your journal.")) update(() => { state.session = null; ui.sheet = null; }); break;
      case "star": ui.rating = ui.rating === +el.dataset.i ? null : +el.dataset.i; render(); break;
      case "saveFinish": update(() => { finishBake(); ui.sheet = null; }); break;
      case "pro": ui.sheet = "pro"; render(); break;
      case "addFormula": {
        const name = prompt("Formula name", "My loaf");
        if (name) update(() => state.formulas.push({ id: String(Date.now()), name, flourGrams: 500, hydrationPercent: 70, starterPercent: 20, saltPercent: 2 }));
        break;
      }
      case "editBlock": ui.editBlock = Object.assign({}, s.blocks[+el.dataset.i], { index: +el.dataset.i, weekdays: s.blocks[+el.dataset.i].weekdays.slice() }); ui.sheet = "block"; render(); break;
      case "addBlock": ui.editBlock = { label: "", kind: "other", weekdays: [2, 3, 4, 5, 6], startMinute: 15 * 60, endMinute: 16 * 60, isNew: true }; ui.sheet = "block"; render(); break;
      case "bkind": ui.editBlock.kind = el.dataset.v; render(); break;
      case "bday": { const d = +el.dataset.d, w = ui.editBlock.weekdays; ui.editBlock.weekdays = w.includes(d) ? w.filter((x) => x !== d) : w.concat([d]); render(); break; }
      case "saveBlock": update(() => {
        const b = ui.editBlock;
        if (H.blockProblems(b).some((c) => c !== "busyLabelEmpty")) return;
        const out = { label: b.label.trim() || { sleep: "Sleep", work: "Work", other: "Busy" }[b.kind], kind: b.kind, weekdays: b.weekdays.slice().sort(), startMinute: b.startMinute, endMinute: b.endMinute };
        if (b.isNew) s.blocks.push(out); else s.blocks[b.index] = out;
        ui.sheet = null;
      }); break;
      case "deleteBlock": update(() => { s.blocks.splice(ui.editBlock.index, 1); ui.sheet = null; }); break;
      case "closeSheet": ui.sheet = null; ui.ci = null; render(); break;
    }
  });

  document.addEventListener("input", (e) => {
    const el = e.target.closest("[data-action]");
    if (!el) return;
    const a = el.dataset.action;
    const mins = (v) => { const [h, m] = v.split(":").map(Number); return h * 60 + m; };
    if (a === "rise") { ui.rise = +el.value; ui.ci = null; render(); }
    else if (a === "notes") ui.notes = el.value;
    else if (a === "blabel") ui.editBlock.label = el.value;
    else if (a === "bstart" && el.value) { ui.editBlock.startMinute = mins(el.value); }
    else if (a === "bend" && el.value) { ui.editBlock.endMinute = mins(el.value); }
  });
  document.addEventListener("change", (e) => {
    const el = e.target.closest("[data-action]");
    if (!el) return;
    const a = el.dataset.action;
    if (a === "custom" && el.value) { const t = new Date(el.value).getTime(); if (Number.isFinite(t)) { ui.readyBy = t; render(); } }
    else if (a === "formula") { ui.formulaId = el.value; render(); }
    else if (a === "ratio") update(() => { state.settings.preferredFeedRatio = el.value; });
    else if (a === "bstart" || a === "bend") render();
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && ui.sheet) { ui.sheet = null; render(); } });

  function simulate(cmd) {
    if (cmd === "reset") {
      if (!confirm("Erase all prototype data in this browser?")) return;
      state = defaults(); Object.assign(ui, { page: 0, readyBy: null, result: null, showResult: false, sheet: null, tab: "bake" });
      save(); render(); return;
    }
    if (cmd === "real") state.simOffset = 0;
    else if (cmd === "next") {
      const s = state.session;
      const next = s && H.session.nextAttendedStep(s);
      if (next && next.start > now()) state.simOffset += next.start - now();
    } else state.simOffset += +cmd * MIN;
    save(); render();
  }

  setInterval(render_if_idle, 30 * 1000);
  function render_if_idle() { if (!ui.sheet && document.activeElement === document.body) render(); }
  render();
})();
