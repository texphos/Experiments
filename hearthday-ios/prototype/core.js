// Hearthday planning core, ported line-for-line from Core/Sources/HearthdayCore (Swift).
// The Swift package is the source of truth; `node parity.test.js` checks this port against
// fixtures.json, which the Swift executable `hearthday-fixtures` generates.
// Dates are epoch milliseconds throughout.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.HearthdayCore = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const DAY = 24 * HOUR;

  // ---------- Calendar (UTC for parity tests, local time in the browser) ----------
  function makeCalendar(utc) {
    const parts = (t) => {
      const d = new Date(t);
      return utc
        ? { y: d.getUTCFullYear(), m: d.getUTCMonth(), d: d.getUTCDate(), wd: d.getUTCDay() }
        : { y: d.getFullYear(), m: d.getMonth(), d: d.getDate(), wd: d.getDay() };
    };
    const make = (y, m, d, h, min) => (utc ? Date.UTC(y, m, d, h, min) : new Date(y, m, d, h, min).getTime());
    return {
      startOfDay(t) { const p = parts(t); return make(p.y, p.m, p.d, 0, 0); },
      /** 1 = Sunday … 7 = Saturday, like Foundation. */
      weekday(t) { return parts(t).wd + 1; },
      atMinute(day, minuteOfDay) { const p = parts(day); return make(p.y, p.m, p.d, Math.floor(minuteOfDay / 60), minuteOfDay % 60); },
      addDays(t, n) { const p = parts(t); return make(p.y, p.m, p.d + n, 0, 0); },
      minuteOfDay(t) { const d = new Date(t); return utc ? d.getUTCHours() * 60 + d.getUTCMinutes() : d.getHours() * 60 + d.getMinutes(); },
    };
  }

  // ---------- Availability ----------
  const EVERY_DAY = [1, 2, 3, 4, 5, 6, 7];
  const WEEKDAYS = [2, 3, 4, 5, 6];

  function blockDuration(b) {
    return b.endMinute > b.startMinute ? b.endMinute - b.startMinute : 1440 - b.startMinute + b.endMinute;
  }

  // ---------- Validation (mirrors Validation.swift) ----------
  const LIMITS = {
    tempC: [14, 32], risePercent: [0, 200], flourGrams: [200, 2000], hydrationPercent: [55, 95],
    starterPercent: [5, 40], saltPercent: [0, 3], maxDaysAhead: 7,
  };
  const within = (v, [lo, hi]) => typeof v === "number" && Number.isFinite(v) && v >= lo && v <= hi;
  const minuteOk = (m) => Number.isInteger(m) && m >= 0 && m < 1440;

  function blockIsValid(b) {
    return minuteOk(b.startMinute) && minuteOk(b.endMinute) && b.startMinute !== b.endMinute
      && Array.isArray(b.weekdays) && b.weekdays.length > 0 && b.weekdays.every((d) => d >= 1 && d <= 7);
  }

  function blockProblems(b) {
    const out = [];
    if (!String(b.label || "").trim()) out.push("busyLabelEmpty");
    if (!Array.isArray(b.weekdays) || !b.weekdays.length || !b.weekdays.every((d) => d >= 1 && d <= 7)) out.push("busyNoDays");
    if (!minuteOk(b.startMinute) || !minuteOk(b.endMinute)) out.push("busyTimeInvalid");
    else if (b.startMinute === b.endMinute) out.push("busyZeroLength");
    return out;
  }

  function formulaProblems(f) {
    const out = [];
    if (!String(f.name || "").trim()) out.push("formulaNameEmpty");
    if (!within(f.flourGrams, LIMITS.flourGrams)) out.push("flourOutOfRange");
    if (!within(f.hydrationPercent, LIMITS.hydrationPercent)) out.push("hydrationOutOfRange");
    if (!within(f.starterPercent, LIMITS.starterPercent)) out.push("starterOutOfRange");
    if (!within(f.saltPercent, LIMITS.saltPercent)) out.push("saltOutOfRange");
    return out;
  }

  function requestProblems(r) {
    const out = [];
    if (!within(r.kitchenTempC, LIMITS.tempC)) out.push("temperatureOutOfRange");
    if (!(r.readyBy > r.now)) out.push("readyTimeInPast");
    else if (r.readyBy - r.now > LIMITS.maxDaysAhead * DAY + HOUR) out.push("readyTimeTooFar");
    return out.concat(formulaProblems(r.formula));
  }

  function checkInProblems(risePercent, tempC) {
    const out = [];
    if (!within(risePercent, LIMITS.risePercent)) out.push("riseOutOfRange");
    if (!within(tempC, LIMITS.tempC)) out.push("temperatureOutOfRange");
    return out;
  }

  const PROBLEM_TEXT = {
    temperatureOutOfRange: `Enter a dough temperature between ${LIMITS.tempC[0]} and ${LIMITS.tempC[1]} °C. Outside that range Hearthday’s timing model isn’t reliable enough to plan with.`,
    riseOutOfRange: `Enter a rise between 0% and ${LIMITS.risePercent[1]}%.`,
    readyTimeInPast: "Pick a time in the future.",
    readyTimeTooFar: `Pick a time within the next ${LIMITS.maxDaysAhead} days.`,
    formulaNameEmpty: "Give the formula a name.",
    flourOutOfRange: `Flour should be between ${LIMITS.flourGrams[0]} and ${LIMITS.flourGrams[1]} g.`,
    hydrationOutOfRange: `Water should be between ${LIMITS.hydrationPercent[0]}% and ${LIMITS.hydrationPercent[1]}% of the flour.`,
    starterOutOfRange: `Starter should be between ${LIMITS.starterPercent[0]}% and ${LIMITS.starterPercent[1]}% of the flour.`,
    saltOutOfRange: `Salt should be between 0% and ${LIMITS.saltPercent[1]}% of the flour.`,
    busyLabelEmpty: "Give this busy time a name.",
    busyNoDays: "Choose at least one day.",
    busyTimeInvalid: "Choose a valid start and end time.",
    busyZeroLength: "Start and end can’t be the same time.",
  };
  const problemMessage = (code) => PROBLEM_TEXT[code] || "Something in that entry isn’t valid.";

  const typicalWeekdayWorker = () => [
    { label: "Sleep", kind: "sleep", weekdays: EVERY_DAY.slice(), startMinute: 23 * 60, endMinute: 7 * 60 },
    { label: "Work", kind: "work", weekdays: WEEKDAYS.slice(), startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30 },
  ];

  function intervals(blocks, start, end, cal) {
    if (end < start) return [];
    const result = [];
    let day = cal.startOfDay(cal.startOfDay(start) - 1.5 * DAY);
    const lastDay = cal.startOfDay(end);
    while (day <= lastDay) {
      const wd = cal.weekday(day);
      for (const b of blocks) {
        if (!b.weekdays.includes(wd) || !blockIsValid(b)) continue;
        // Wall-clock end on the correct local day, so a night spanning a DST change is 7 or 9 real hours.
        const s = cal.atMinute(day, b.startMinute);
        const e = cal.atMinute(b.endMinute > b.startMinute ? day : cal.addDays(day, 1), b.endMinute);
        if (!(e > s)) continue;
        if (s < end && start < e) result.push({ label: b.label, kind: b.kind, start: s, end: e });
      }
      day = cal.addDays(day, 1);
    }
    return result.sort((a, b) => a.start - b.start || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0));
  }

  class Timeline {
    constructor(list) { this.intervals = list; }
    conflict(start, duration) {
      const end = start + duration;
      return this.intervals.find((i) => i.start < end && start < i.end) || null;
    }
    isFree(start, duration) { return this.conflict(start, duration) === null; }
    earliestFreeStart(atOrAfter, duration, limit) {
      let t = atOrAfter;
      while (t <= limit) {
        const c = this.conflict(t, duration);
        if (c) t = c.end; else return t;
      }
      return null;
    }
  }
  const timeline = (blocks, start, end, cal) => new Timeline(intervals(blocks, start, end, cal));

  // ---------- Fermentation ----------
  const FEED_RATIOS = ["1:1:1", "1:2:2", "1:5:5", "1:10:10"];
  const PEAK_HOURS = { "1:1:1": 4.5, "1:2:2": 6.5, "1:5:5": 9, "1:10:10": 12 };

  function makeModel(overrides) {
    return Object.assign({
      referenceTempC: 21, referenceBulkHours: 7, referenceInoculationPercent: 20, q10: 2.6,
      inoculationExponent: 0.5, referenceRoomProofHours: 2, starterReferenceTempC: 24, speedFactor: 1, uncertainty: 0.2,
    }, overrides || {});
  }
  const rate = (m, t, ref) => Math.pow(m.q10, (t - ref) / 10);
  function bulkHours(m, tempC, inoc) {
    const i = Math.max(inoc, 2);
    return m.referenceBulkHours / (rate(m, tempC, m.referenceTempC) * Math.pow(i / m.referenceInoculationPercent, m.inoculationExponent) * m.speedFactor);
  }
  const roomProofHours = (m, tempC) => m.referenceRoomProofHours / (rate(m, tempC, m.referenceTempC) * m.speedFactor);
  const starterPeakHours = (m, ratio, tempC) => PEAK_HOURS[ratio] / rate(m, tempC, m.starterReferenceTempC);
  function targetRisePercent(t) {
    const table = [[18, 100], [20, 85], [21, 75], [22, 65], [24, 50], [27, 30]];
    if (t <= table[0][0]) return table[0][1];
    if (t >= table[table.length - 1][0]) return table[table.length - 1][1];
    for (let i = 0; i < table.length - 1; i++) {
      const [t0, r0] = table[i], [t1, r1] = table[i + 1];
      if (t >= t0 && t <= t1) return r0 + (r1 - r0) * (t - t0) / (t1 - t0);
    }
    return 75;
  }

  // ---------- Calibration ----------
  const CAL = { defaultU: 0.2, minU: 0.1, maxU: 0.3, prior: 2, maxSamples: 12, needed: 3 };
  const clampSpeed = (s) => Math.min(Math.max(s, 0.4), 2.5);
  const calibration = {
    record(samples, s) {
      if (!(s.actualHours > 0.5 && s.modelHours > 0.5)) return samples;
      return samples.concat([s]).slice(-CAL.maxSamples);
    },
    speedFactor(samples) {
      if (!samples.length) return 1;
      const sum = samples.reduce((a, s) => a + Math.log(clampSpeed(s.modelHours / s.actualHours)), 0);
      return Math.exp(sum / (samples.length + CAL.prior));
    },
    uncertainty(samples) {
      if (samples.length < CAL.needed) return CAL.defaultU;
      const k = Math.log(calibration.speedFactor(samples));
      const ms = samples.reduce((a, s) => { const r = Math.log(clampSpeed(s.modelHours / s.actualHours)) - k; return a + r * r; }, 0) / samples.length;
      return Math.min(Math.max(1.3 * Math.sqrt(ms) + 0.05, CAL.minU), CAL.maxU);
    },
  };

  // ---------- Text ----------
  function halfHours(h) {
    const v = Math.round(h * 2) / 2;
    const whole = Math.trunc(v);
    const half = v - whole >= 0.5;
    if (whole === 0 && half) return "½";
    return half ? `${whole}½` : `${whole}`;
  }
  function hoursRange(lo, hi) { const a = halfHours(lo), b = halfHours(hi); return a === b ? `about ${a} h` : `${a}–${b} h`; }
  function compact(minutes) { const h = Math.floor(minutes / 60), m = minutes % 60; return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${m} min`; }

  const PROCESS = {
    feedMinutes: 5, mixMinutes: 20, foldCount: 4, foldIntervalMinutes: 30, foldMinutes: 5, shapeMinutes: 20,
    preheatMinutes: 45, bakeMinutes: 45, retardMinHours: 8, retardMaxHours: 36, retardPreferredLowHours: 12,
    retardPreferredHighHours: 16, roomFinishSlackMinutes: 60, gridMinutes: 15,
  };

  const step = (id, kind, start, end, attended, title, detail, extra) =>
    Object.assign({ id, kind, start, end, attended, title, detail }, extra || {});
  const Steps = {
    feed: (s, min, ratio, peak) => step("feed", "feedStarter", s, s + min * MIN, true, "Feed starter", `Feed ${ratio}. It should peak in about ${halfHours(peak)} h — ratios are a rule of thumb, so glance at it before mixing.`),
    starterRise: (s, e) => step("starter-rise", "starterRise", s, e, false, "Starter rises", "Nothing to do. Your starter is getting ready."),
    mix: (s, min, inoc, f) => step("mix", "mix", s, s + min * MIN, true, "Mix dough", `${Math.round(f.flourGrams)} g flour, ${Math.round(f.flourGrams * f.hydrationPercent / 100)} g water, ${Math.round(f.flourGrams * inoc / 100)} g starter, ${Math.round(f.flourGrams * f.saltPercent / 100)} g salt. Mark the level on your container.`),
    fold: (n, count, s, min) => step(`fold-${n}`, "fold", s, s + min * MIN, true, `Fold ${n} of ${count}`, `One set of stretch-and-folds, about ${min} min.`),
    bulk: (s, e, lo, hi, rise) => step("bulk", "bulk", s, e, false, "Bulk ferment", `Likely ${hoursRange(lo, hi)} from mixing. Aim for about ${Math.round(rise)}% rise, a domed top and bubbles at the edges.`),
    shape: (s, min, ls, le, rise) => step("shape", "shape", s, s + min * MIN, true, "Shape", `Shape once the dough is up about ${Math.round(rise)}%. Check in first if it looks early or slow.`, { likelyStart: ls, likelyEnd: le }),
    coldRetard: (s, e, p) => step("cold-proof", "coldRetard", s, e, false, "Cold proof in fridge", `${halfHours((e - s) / HOUR)} h planned. ${p.retardPreferredLowHours}–${p.retardPreferredHighHours} h is typical; ${p.retardMinHours}–${p.retardMaxHours} h is workable.`),
    roomProof: (s, e, lo, hi) => step("room-proof", "roomProof", s, e, false, "Proof at room temperature", `Likely ${hoursRange(lo, hi)}. Bake when a floured poke springs back slowly.`),
    coldBulk: (s, e) => step("cold-bulk", "coldBulk", s, e, false, "Finish bulk in fridge", "The dough keeps rising slowly while it chills. Shape it straight from the fridge."),
    preheat: (s, min) => step("preheat", "preheat", s, s + min * MIN, true, "Preheat oven", `Oven and pot, about ${min} min.`),
    bake: (s, min) => step("bake", "bake", s, s + min * MIN, true, "Bake", `Score and bake, lid on for the first half, about ${min} min in total.`),
  };

  const STEP_ORDER = ["feedStarter", "starterRise", "mix", "fold", "bulk", "coldBulk", "shape", "coldRetard", "roomProof", "preheat", "bake"];
  const sortSteps = (steps) => steps.slice().sort((a, b) => a.start - b.start || STEP_ORDER.indexOf(a.kind) - STEP_ORDER.indexOf(b.kind));
  const ceilToGrid = (t, g) => Math.ceil(t / g) * g;
  const floorToMinute = (t) => Math.floor(t / MIN) * MIN;
  const distanceOutside = (v, lo, hi) => (v < lo ? lo - v : v > hi ? v - hi : 0);

  // ---------- Planner ----------
  const DEPTH = { notEnoughTime: 0, feedConflict: 1, mixConflict: 2, foldConflict: 3, shapeConflict: 4, retardOutOfRange: 5, bakeConflict: 7 };
  class Diagnostics {
    constructor() { this.reason = "notEnoughTime"; this.counts = {}; }
    note(r, label) {
      if (DEPTH[r] > DEPTH[this.reason]) { this.reason = r; this.counts = {}; }
      if (r === this.reason && label != null) this.counts[label] = (this.counts[label] || 0) + 1;
    }
    get label() {
      let best = null;
      for (const k of Object.keys(this.counts)) {
        if (best === null || this.counts[k] > this.counts[best] || (this.counts[k] === this.counts[best] && k < best)) best = k;
      }
      return best;
    }
  }

  const MAX_LEAD_HOURS = 72;

  /** request: { now, readyBy, kitchenTempC, formula, starterNeedsFeed, preferredFeedRatio, allowFeedRatioAdjustment,
   *  allowInoculationAdjustment, proofModes, blocks, model, process } */
  function normalize(r) {
    return Object.assign({
      formula: { name: "Everyday country loaf", flourGrams: 500, hydrationPercent: 72, starterPercent: 20, saltPercent: 2 },
      starterNeedsFeed: true, preferredFeedRatio: "1:2:2", allowFeedRatioAdjustment: true, allowInoculationAdjustment: true,
      proofModes: ["fridge", "room"], blocks: typicalWeekdayWorker(), process: PROCESS,
    }, r, { model: makeModel(r.model) });
  }

  function signature(p) { return `${p.proofMode}|${Math.round(p.inoculationPercent)}|${p.feedRatio || "-"}`; }

  function inoculationOptions(r) {
    const opts = [r.formula.starterPercent];
    if (r.allowInoculationAdjustment) for (const v of [10, 15, 20]) if (Math.abs(v - r.formula.starterPercent) > 0.01) opts.push(v);
    return opts;
  }

  function ovenSlotConflict(r, mode, tl) {
    const p = r.process;
    const attended = (p.preheatMinutes + p.bakeMinutes) * MIN;
    if (mode === "fridge") return tl.conflict(r.readyBy - attended, attended);
    const grid = p.gridMinutes * MIN;
    let end = r.readyBy - p.roomFinishSlackMinutes * MIN;
    let first = null;
    while (end <= r.readyBy) {
      const c = tl.conflict(end - attended, attended);
      if (!c) return null;
      first = first || c;
      end += grid;
    }
    return first;
  }

  function context(r, tl, mode, inoc, ratio) {
    const p = r.process, m = r.model, u = m.uncertainty;
    const bh = bulkHours(m, r.kitchenTempC, inoc);
    const ph = roomProofHours(m, r.kitchenTempC);
    const foldSpan = p.foldCount > 0 ? (p.foldCount * p.foldIntervalMinutes + p.foldMinutes) * MIN : p.mixMinutes * MIN;
    const tail = mode === "fridge" ? p.retardMinHours * HOUR : ph * HOUR * (1 - u);
    return {
      r, tl, mode, inoc, ratio, p, m, u, grid: p.gridMinutes * MIN,
      feedLead: ratio ? starterPeakHours(m, ratio, r.kitchenTempC) * HOUR : 0,
      bulkHours: bh,
      modelBulkHours: bulkHours(Object.assign({}, m, { speedFactor: 1 }), r.kitchenTempC, inoc),
      proofHours: ph, foldSpan,
      shapeDuration: p.shapeMinutes * MIN, bakeDuration: p.bakeMinutes * MIN, preheatDuration: p.preheatMinutes * MIN,
      minimumSpanFromMix: Math.max(bh * HOUR * (1 - u), foldSpan) + p.shapeMinutes * MIN + tail + p.bakeMinutes * MIN,
    };
  }

  function buildTail(shapeAt, ctx, diag) {
    const { r, p } = ctx;
    const shapeEnd = shapeAt + ctx.shapeDuration;
    if (ctx.mode === "fridge") {
      const bakeStart = r.readyBy - ctx.bakeDuration;
      const preheatStart = bakeStart - ctx.preheatDuration;
      const c = ctx.tl.conflict(preheatStart, ctx.preheatDuration + ctx.bakeDuration);
      if (c) { diag.note("bakeConflict", c.label); return null; }
      const retard = (bakeStart - shapeEnd) / HOUR;
      if (!(retard >= p.retardMinHours && retard <= p.retardMaxHours)) { diag.note("retardOutOfRange", null); return null; }
      return {
        steps: [Steps.coldRetard(shapeEnd, bakeStart, p), Steps.preheat(preheatStart, p.preheatMinutes), Steps.bake(bakeStart, p.bakeMinutes)],
        penalty: distanceOutside(retard, p.retardPreferredLowHours, p.retardPreferredHighHours) * 0.15,
      };
    }
    const proof = ctx.proofHours * HOUR;
    const expected = shapeEnd + proof;
    const low = Math.max(shapeEnd + proof * (1 - ctx.u), r.readyBy - p.roomFinishSlackMinutes * MIN - ctx.bakeDuration);
    const high = Math.min(shapeEnd + proof * (1 + ctx.u), r.readyBy - ctx.bakeDuration);
    if (low > high) return null;
    let best = null, conflictLabel = null;
    for (let bs = ceilToGrid(low, ctx.grid); bs <= high; bs += ctx.grid) {
      const c = ctx.tl.conflict(bs - ctx.preheatDuration, ctx.preheatDuration + ctx.bakeDuration);
      if (c) { conflictLabel = conflictLabel || c.label; continue; }
      const d = Math.abs(bs - expected) / HOUR;
      if (best === null || d < best.d - 1e-9) best = { d, bs };
    }
    if (!best) { if (conflictLabel) diag.note("bakeConflict", conflictLabel); return null; }
    return {
      steps: [
        Steps.roomProof(shapeEnd, best.bs, ctx.proofHours * (1 - ctx.u), ctx.proofHours * (1 + ctx.u)),
        Steps.preheat(best.bs - ctx.preheatDuration, p.preheatMinutes),
        Steps.bake(best.bs, p.bakeMinutes),
      ],
      penalty: best.d,
    };
  }

  function evaluate(mix, ctx, diag) {
    const { r, p } = ctx;
    const steps = [];
    if (ctx.ratio) {
      const feedAt = floorToMinute(mix - ctx.feedLead);
      if (feedAt < r.now) { diag.note("notEnoughTime", null); return null; }
      const c = ctx.tl.conflict(feedAt, p.feedMinutes * MIN);
      if (c) { diag.note("feedConflict", c.label); return null; }
      const feed = Steps.feed(feedAt, p.feedMinutes, ctx.ratio, starterPeakHours(ctx.m, ctx.ratio, r.kitchenTempC));
      steps.push(feed);
      if (feed.end < mix) steps.push(Steps.starterRise(feed.end, mix));
    }
    const mc = ctx.tl.conflict(mix, p.mixMinutes * MIN);
    if (mc) { diag.note("mixConflict", mc.label); return null; }
    steps.push(Steps.mix(mix, p.mixMinutes, ctx.inoc, r.formula));
    for (let i = 1; i <= p.foldCount; i++) {
      const s = mix + i * p.foldIntervalMinutes * MIN;
      const c = ctx.tl.conflict(s, p.foldMinutes * MIN);
      if (c) { diag.note("foldConflict", c.label); return null; }
      steps.push(Steps.fold(i, p.foldCount, s, p.foldMinutes));
    }
    const bulk = ctx.bulkHours * HOUR;
    const expected = mix + bulk;
    const likelyStart = mix + bulk * (1 - ctx.u);
    const likelyEnd = mix + bulk * (1 + ctx.u);
    const lastFoldEnd = mix + ctx.foldSpan;
    const rise = targetRisePercent(r.kitchenTempC);

    let best = null, sawFree = false;
    for (let shapeAt = ceilToGrid(Math.max(likelyStart, lastFoldEnd), ctx.grid); shapeAt <= likelyEnd; shapeAt += ctx.grid) {
      if (!ctx.tl.isFree(shapeAt, ctx.shapeDuration)) continue;
      sawFree = true;
      const tail = buildTail(shapeAt, ctx, diag);
      if (!tail) continue;
      const score = Math.abs(shapeAt - expected) / HOUR + tail.penalty;
      if (best === null || score < best.score - 1e-9) best = { score, shapeAt, tail };
    }
    if (!sawFree) {
      const c = ctx.tl.conflict(expected, ctx.shapeDuration) || ctx.tl.conflict(likelyStart, likelyEnd - likelyStart);
      diag.note("shapeConflict", c ? c.label : null);
      return null;
    }
    if (!best) return null;
    steps.push(Steps.bulk(lastFoldEnd, best.shapeAt, ctx.bulkHours * (1 - ctx.u), ctx.bulkHours * (1 + ctx.u), rise));
    steps.push(Steps.shape(best.shapeAt, p.shapeMinutes, likelyStart, likelyEnd, rise));
    steps.push(...best.tail.steps);
    const inocPenalty = Math.abs(ctx.inoc - r.formula.starterPercent) / 5 * 0.5;
    const ratioPenalty = ctx.ratio ? Math.abs(FEED_RATIOS.indexOf(ctx.ratio) - FEED_RATIOS.indexOf(r.preferredFeedRatio)) * 0.25 : 0;
    return makePlan({
      steps: sortSteps(steps), proofMode: ctx.mode, inoculationPercent: ctx.inoc, feedRatio: ctx.ratio,
      kitchenTempC: r.kitchenTempC, formula: r.formula, expectedBulkHours: ctx.bulkHours, modelBulkHours: ctx.modelBulkHours,
      uncertainty: ctx.u, score: best.score + inocPenalty + ratioPenalty,
    });
  }

  function makePlan(p) {
    p.mixAt = (p.steps.find((s) => s.kind === "mix") || p.steps[0]).start;
    p.readyAt = p.steps[p.steps.length - 1].end;
    p.firstStepAt = p.steps[0].start;
    return p;
  }
  const planStep = (plan, id) => plan.steps.find((s) => s.id === id) || null;

  function search(r, cal, diag) {
    const p = r.process, grid = p.gridMinutes * MIN;
    const tl = timeline(r.blocks, r.now - HOUR, r.readyBy + HOUR, cal);
    const ratios = r.starterNeedsFeed ? (r.allowFeedRatioAdjustment ? FEED_RATIOS : [r.preferredFeedRatio]) : [null];
    const results = [];
    let order = 0;
    for (const mode of r.proofModes) {
      const busy = ovenSlotConflict(r, mode, tl);
      if (busy) { diag.note("bakeConflict", busy.label); continue; }
      for (const inoc of inoculationOptions(r)) {
        for (const ratio of ratios) {
          order += 1;
          const ctx = context(r, tl, mode, inoc, ratio);
          const earliest = Math.max(ceilToGrid(r.now + ctx.feedLead, grid), ceilToGrid(r.readyBy - MAX_LEAD_HOURS * HOUR, grid));
          const latest = r.readyBy - ctx.minimumSpanFromMix;
          if (earliest > latest) { diag.note("notEnoughTime", null); continue; }
          for (let mix = earliest; mix <= latest; mix += grid) {
            const plan = evaluate(mix, ctx, diag);
            if (plan) results.push({ plan, order });
          }
        }
      }
    }
    results.sort((a, b) => (Math.abs(a.plan.score - b.plan.score) > 1e-9 ? a.plan.score - b.plan.score : a.plan.mixAt - b.plan.mixAt || a.order - b.order));
    return results.map((x) => x.plan);
  }

  function earliestFeasibleReadyTime(r, cal) {
    for (let h = 1; h <= 72; h++) {
      const first = search(Object.assign({}, r, { readyBy: r.readyBy + h * HOUR }), cal, new Diagnostics())[0];
      if (first) return first.readyAt;
    }
    return null;
  }

  function plan(request, cal) {
    const r = normalize(request);
    const problems = requestProblems(r);
    if (problems.length) return { feasible: false, invalid: problems };
    const diag = new Diagnostics();
    const candidates = search(r, cal, diag);
    if (candidates.length) {
      const seen = new Set([signature(candidates[0])]);
      const alternatives = [];
      for (const c of candidates.slice(1)) {
        if (alternatives.length >= 2) break;
        const s = signature(c);
        if (!seen.has(s)) { seen.add(s); alternatives.push(c); }
      }
      return { feasible: true, primary: candidates[0], alternatives };
    }
    return { feasible: false, reason: diag.reason, blockingLabel: diag.label, earliestFeasibleReadyAt: earliestFeasibleReadyTime(r, cal) };
  }

  function infeasibilityMessage(info) {
    const who = info.blockingLabel ? `“${info.blockingLabel}”` : "your busy times";
    return {
      notEnoughTime: "There isn’t enough time left for a full bake before then.",
      feedConflict: `Every workable plan needs a starter feed during ${who}.`,
      mixConflict: `Every workable plan needs you to mix during ${who}.`,
      foldConflict: `Every workable plan puts a set of folds during ${who}.`,
      shapeConflict: `The dough would most likely be ready to shape during ${who}.`,
      retardOutOfRange: "The fridge proof would be too short or too long to hit that time.",
      bakeConflict: `Baking at that time would clash with ${who}.`,
    }[info.reason];
  }

  function leverSummary(p) {
    const items = [];
    if (Math.abs(p.inoculationPercent - p.formula.starterPercent) > 0.01) items.push(`Starter ${Math.round(p.inoculationPercent)}% instead of ${Math.round(p.formula.starterPercent)}%`);
    if (p.feedRatio) items.push(`Feed ${p.feedRatio}`);
    items.push(p.proofMode === "fridge" ? "Cold proof overnight-style in the fridge" : "Same-day proof at room temperature");
    return items;
  }

  // ---------- Live session ----------
  function newSession(plan, startedAt) {
    return { id: `bake-${startedAt}`, plan: clonePlan(plan), originalReadyAt: plan.readyAt, startedAt, completed: {}, checkIns: [], shapeReadiness: null, finishedAt: null, replanCount: 0 };
  }
  function clonePlan(p) { return makePlan(Object.assign({}, p, { steps: p.steps.map((s) => Object.assign({}, s)) })); }

  const GRACE_MINUTES = 15;
  const STALE_AFTER_HOURS = 12;
  const session = {
    nextAttendedStep: (s) => s.plan.steps.find((x) => x.attended && s.completed[x.id] == null) || null,
    passiveStep: (s, now) => s.plan.steps.find((x) => !x.attended && x.start <= now && now < x.end && s.completed[x.id] == null) || null,
    bulkClockStart(s) {
      const mix = planStep(s.plan, "mix");
      if (!mix) return s.plan.firstStepAt;
      return s.completed.mix != null ? s.completed.mix - (mix.end - mix.start) : mix.start;
    },
    isInBulk: (s) => s.completed.mix != null && s.completed.shape == null,
    /** Mirrors BakeSession.status(now:): upcoming, due, overdue (with minutesLate), baked or stale. */
    status(s, now) {
      if (s.completed.bake != null) return { kind: "baked" };
      if (now - s.plan.readyAt > STALE_AFTER_HOURS * HOUR) return { kind: "stale" };
      const next = session.nextAttendedStep(s);
      if (!next) return { kind: "baked" };
      const late = now - next.start;
      if (late > GRACE_MINUTES * MIN) return { kind: "overdue", step: next, minutesLate: Math.floor(late / MIN) };
      return { kind: late >= -5 * MIN ? "due" : "upcoming", step: next };
    },
    /** Mirrors Reminders.specs(for:now:): what the native app hands to iOS after every change. */
    reminders(s, now, blocks, cal) {
      const out = [];
      const chilling = s.plan.steps.some((x) => x.kind === "coldBulk");
      for (const st of s.plan.steps) {
        if (!st.attended || s.completed[st.id] != null || !(st.start > now)) continue;
        out.push({ id: `${s.id}-${st.id}`, fireAt: st.start, title: st.title, body: st.detail });
        if (st.kind === "shape" && !chilling && st.likelyStart != null && st.likelyStart > now && st.start - st.likelyStart >= 20 * MIN) {
          if (blocks && !timeline(blocks, st.likelyStart - HOUR, st.likelyStart + HOUR, cal).isFree(st.likelyStart, MIN)) continue;
          out.push({ id: `${s.id}-check`, fireAt: st.likelyStart, title: "Check your dough", body: "It could be ready early. Compare the rise with your mark and do a quick check-in." });
        }
      }
      return out.sort((a, b) => a.fireAt - b.fireAt);
    },
    complete(s, id, now) {
      const st = planStep(s.plan, id);
      if (!st || s.completed[id] != null) return;
      s.completed[id] = now;
      if (id === "mix") { const d = now - st.end; if (Math.abs(d) >= MIN) shiftDough(s, d); }
      if (id === "shape") { const d = now - st.end; if (Math.abs(d) >= MIN) shiftAfterShape(s, d); }
      if (id === "bake") s.finishedAt = now;
      s.plan = makePlan(s.plan);
    },
    upcomingConflicts(s, now, blocks, cal) {
      const pending = s.plan.steps.filter((x) => x.attended && s.completed[x.id] == null && x.end > now);
      if (!pending.length) return [];
      const tl = timeline(blocks, now - HOUR, Math.max(...pending.map((x) => x.end)), cal);
      return pending.map((x) => { const c = tl.conflict(x.start, x.end - x.start); return c ? { step: x, busyLabel: c.label } : null; }).filter(Boolean);
    },
    actualBulkHours(s) {
      const done = s.completed.shape, sh = planStep(s.plan, "shape");
      if (done == null || !sh) return null;
      return (done - (sh.end - sh.start) - session.bulkClockStart(s)) / HOUR;
    },
    averageTempC(s) {
      if (!s.checkIns.length) return s.plan.kitchenTempC;
      const temps = [s.plan.kitchenTempC].concat(s.checkIns.map((c) => c.tempC));
      return temps.reduce((a, b) => a + b, 0) / temps.length;
    },
    calibrationSample(s) {
      const actual = session.actualBulkHours(s);
      if (s.shapeReadiness !== "justRight" || actual == null || s.plan.steps.some((x) => x.kind === "coldBulk")) return null;
      const t = session.averageTempC(s);
      return { date: s.completed.shape, tempC: t, inoculationPercent: s.plan.inoculationPercent, modelHours: bulkHours(makeModel(), t, s.plan.inoculationPercent), actualHours: actual };
    },
    apply(s, option) {
      const kept = s.plan.steps.filter((x) => ["feedStarter", "starterRise", "mix", "fold"].includes(x.kind));
      const bulk = planStep(s.plan, "bulk");
      if (bulk) kept.push(Object.assign({}, bulk, { end: option.bulkEndsAt }));
      s.plan.steps = sortSteps(kept.concat(option.steps.map((x) => Object.assign({}, x))));
      if (option.steps.some((x) => x.kind === "coldRetard")) s.plan.proofMode = "fridge";
      if (option.steps.some((x) => x.kind === "roomProof")) s.plan.proofMode = "room";
      s.plan = makePlan(s.plan);
      s.replanCount += 1;
    },
  };

  function shiftDough(s, d) {
    const room = s.plan.proofMode === "room";
    s.plan.steps = sortSteps(s.plan.steps.map((x) => {
      if (s.completed[x.id] != null) return x;
      const y = Object.assign({}, x);
      if (["fold", "bulk", "shape"].includes(x.kind) || (room && ["roomProof", "preheat", "bake"].includes(x.kind))) {
        y.start += d; y.end += d;
        if (y.likelyStart != null) y.likelyStart += d;
        if (y.likelyEnd != null) y.likelyEnd += d;
      } else if (x.kind === "coldRetard") y.start += d;
      return y;
    }));
  }
  function shiftAfterShape(s, d) {
    s.plan.steps = sortSteps(s.plan.steps.map((x) => {
      if (s.completed[x.id] != null) return x;
      const y = Object.assign({}, x);
      if (x.kind === "coldRetard") y.start += d;
      else if (["roomProof", "preheat", "bake"].includes(x.kind) && s.plan.proofMode === "room") { y.start += d; y.end += d; }
      return y;
    }));
  }

  // ---------- Live replanner ----------
  function tailInMode(shapeAt, ctx) {
    const p = ctx.process, grid = p.gridMinutes * MIN;
    const shapeEnd = shapeAt + p.shapeMinutes * MIN;
    const bake = p.bakeMinutes * MIN, preheat = p.preheatMinutes * MIN;
    const shape = Steps.shape(shapeAt, p.shapeMinutes, ctx.likelyStart, ctx.likelyEnd, ctx.targetRise);
    let low, high, target;
    if (ctx.mode === "fridge") {
      low = shapeEnd + p.retardMinHours * HOUR; high = shapeEnd + p.retardMaxHours * HOUR; target = ctx.originalReadyAt - bake;
    } else {
      const proof = roomProofHours(ctx.model, ctx.tempC) * HOUR;
      low = shapeEnd + proof * (1 - ctx.model.uncertainty); high = shapeEnd + proof * (1 + ctx.model.uncertainty); target = shapeEnd + proof;
    }
    const probe = ctx.mode === "fridge" && target >= low && target <= high ? [target] : [];
    for (let t = ceilToGrid(low, grid); t <= high; t += grid) probe.push(t);
    let best = null, bestD = Infinity;
    for (const st of probe) {
      if (st < low || st > high) continue;
      if (!ctx.timeline.isFree(st - preheat, preheat + bake)) continue;
      const d = Math.abs(st - target);
      if (d < bestD - 1e-6) { bestD = d; best = st; }
    }
    if (best == null) return null;
    let middle;
    if (ctx.mode === "fridge") middle = Steps.coldRetard(shapeEnd, best, p);
    else { const h = roomProofHours(ctx.model, ctx.tempC); middle = Steps.roomProof(shapeEnd, best, h * (1 - ctx.model.uncertainty), h * (1 + ctx.model.uncertainty)); }
    return [shape, middle, Steps.preheat(best - preheat, p.preheatMinutes), Steps.bake(best, p.bakeMinutes)];
  }
  function tail(shapeAt, ctx) {
    const steps = tailInMode(shapeAt, ctx);
    if (steps || ctx.mode !== "room") return steps;
    return tailInMode(shapeAt, Object.assign({}, ctx, { mode: "fridge" }));
  }

  function checkIn(s, now, risePercent, tempC, blocks, cal, modelOverrides, process) {
    const p = process || PROCESS;
    const model = makeModel(modelOverrides);
    const problems = checkInProblems(risePercent, tempC);
    if (problems.length) {
      return { progress: 0, targetRisePercent: 0, estimatedReadyAt: now, summary: problems.map(problemMessage).join(" "), options: [], problems };
    }
    const target = targetRisePercent(tempC);
    const elapsed = Math.max(now - session.bulkClockStart(s), 10 * MIN);
    const progress = Math.min(Math.max(risePercent / target, 0.02), 2);
    const remaining = progress >= 0.95 ? 0 : elapsed / progress - elapsed;
    const readyAt = now + remaining;
    const totalBulk = elapsed + remaining;
    const tolerance = Math.max(30 * MIN, 0.15 * totalBulk);
    const shapeDuration = p.shapeMinutes * MIN;
    const tl = timeline(blocks, now - HOUR, now + (p.retardMaxHours + 60) * HOUR, cal);
    const ctx = {
      mode: s.plan.proofMode, originalReadyAt: s.originalReadyAt, tempC, model, process: p, timeline: tl,
      likelyStart: readyAt - tolerance, likelyEnd: readyAt + tolerance, targetRise: target,
    };
    const options = [];
    const freeShape = tl.earliestFreeStart(Math.max(readyAt, now), shapeDuration, now + 48 * HOUR);
    if (freeShape != null && freeShape - readyAt <= tolerance) {
      const steps = tail(freeShape, ctx);
      if (steps) {
        const isNow = remaining === 0 && freeShape - now <= 5 * MIN;
        options.push({
          kind: isNow ? "shapeNow" : "shapeWhenReady",
          title: isNow ? "Shape now" : "Shape when it’s ready",
          detail: isNow ? "Your reading is at the target rise and you’re free. Confirm with a domed top and bubbles at the edges." : "You’re free when the dough is likely ready. Reminders move to match.",
          bulkEndsAt: freeShape, steps, conflictLabel: null, recommended: true,
        });
      }
    } else {
      const conflict = tl.conflict(readyAt, shapeDuration);
      const label = conflict ? conflict.label : null;
      const fridgeAt = conflict && conflict.start > now ? Math.max(now, conflict.start - 10 * MIN) : now;
      const progressAtFridge = Math.min(1, (elapsed + (fridgeAt - now)) / totalBulk);
      if (freeShape != null && progressAtFridge >= 0.35 && freeShape > fridgeAt) {
        const rest = tail(freeShape, ctx);
        if (rest) {
          const comfortable = progressAtFridge >= 0.5;
          const pctIn = Math.round(progressAtFridge * 100);
          options.push({
            kind: "fridgeNow",
            title: fridgeAt - now < 5 * MIN ? "Fridge the dough now" : `Fridge the dough before ${label || "then"}`,
            detail: progressAtFridge >= 0.95
              ? "It should be about ready by then. Chilling slows it right down so you can shape it cold when you’re free."
              : comfortable
              ? `It goes in about ${pctIn}% of the way through bulk and keeps fermenting slowly as it chills. Shape it cold when you’re free.`
              : `It would go in only about ${pctIn}% of the way through bulk. If it hasn’t risen much by morning, give it time at room temperature before shaping.`,
            bulkEndsAt: fridgeAt, steps: [Steps.coldBulk(fridgeAt, freeShape)].concat(rest), conflictLabel: null, recommended: comfortable,
          });
        }
      }
      const stay = tail(readyAt, ctx);
      if (stay) {
        options.push({
          kind: "stayUp", title: label ? `Shape during ${label}` : "Shape on time",
          detail: "Shapes at the likely-ready time, but you’d need to be around.",
          bulkEndsAt: readyAt, steps: stay, conflictLabel: label, recommended: !options.some((o) => o.recommended),
        });
      }
      if (freeShape != null && freeShape - readyAt <= 3 * tolerance && freeShape > readyAt) {
        const steps = tail(freeShape, ctx);
        if (steps) {
          options.push({
            kind: "waitLonger", title: "Leave it out and shape later",
            detail: `About ${halfHours((freeShape - readyAt) / HOUR)} h past the likely-ready point. Can work in a cool kitchen; risks over-proofing when it’s warm.`,
            bulkEndsAt: freeShape, steps, conflictLabel: null, recommended: false,
          });
        }
      }
    }
    const summary = remaining === 0
      ? `At ${Math.round(risePercent)}% rise your reading meets the target of about ${Math.round(target)}%. Go by the dough: a domed top and bubbles at the edges.`
      : `About ${Math.round(progress * 100)}% of the way to a ${Math.round(target)}% rise. Likely ready in about ${halfHours(remaining / HOUR)} h. That’s a straight-line estimate from one reading, so check again if you can.`;
    for (const o of options) { o.readyAt = o.steps.length ? o.steps[o.steps.length - 1].end : o.bulkEndsAt; const sh = o.steps.find((x) => x.kind === "shape"); o.shapeAt = sh ? sh.start : null; }
    return { progress, targetRisePercent: target, estimatedReadyAt: readyAt, summary, options, problems: [] };
  }

  return {
    MIN, HOUR, DAY, EVERY_DAY, WEEKDAYS, FEED_RATIOS, PROCESS, CAL,
    makeCalendar, typicalWeekdayWorker, intervals, timeline, blockDuration,
    LIMITS, blockIsValid, blockProblems, formulaProblems, requestProblems, checkInProblems, problemMessage,
    makeModel, bulkHours, roomProofHours, starterPeakHours, targetRisePercent, calibration,
    halfHours, hoursRange, compact,
    plan, infeasibilityMessage, leverSummary, planStep,
    newSession, session, checkIn,
  };
});
