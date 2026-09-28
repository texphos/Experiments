// Checks that the browser prototype's JS port produces the same plans and check-in options as the Swift core.
// Run: node parity.test.js   (regenerate fixtures with `swift run hearthday-fixtures > ../prototype/fixtures.json` in Core/)
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const H = require("./core.js");

const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures.json"), "utf8"));
const cal = H.makeCalendar(true);
const t = (iso) => Date.parse(iso);
const iso = (ms) => new Date(ms).toISOString().replace(".000Z", "Z");

function requestFrom(input) {
  return {
    now: t(input.now),
    readyBy: t(input.readyBy),
    kitchenTempC: input.tempC,
    starterNeedsFeed: input.starterNeedsFeed,
    allowInoculationAdjustment: input.allowInoculationAdjustment,
    allowFeedRatioAdjustment: input.allowFeedRatioAdjustment,
    proofModes: input.proofModes,
    blocks: input.blocks,
    model: { speedFactor: input.speedFactor, uncertainty: input.uncertainty },
  };
}

const stepsView = (steps) => steps.map((s) => ({ id: s.id, start: iso(s.start), end: iso(s.end), attended: s.attended }));
const planView = (p) => ({ proofMode: p.proofMode, inoculation: p.inoculationPercent, feedRatio: p.feedRatio || null, steps: stepsView(p.steps) });

let passed = 0;
let failed = 0;
function check(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ok  ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL ${name}\n       ${e.message.split("\n").slice(0, 12).join("\n       ")}`);
  }
}

console.log("Plan scenarios");
const planByName = {};
for (const s of fixtures.planScenarios) {
  planByName[s.name] = s;
  check(s.name, () => {
    const r = H.plan(requestFrom(s.input), cal);
    assert.strictEqual(r.feasible, s.expected.feasible, "feasibility");
    if (r.feasible) {
      assert.deepStrictEqual(planView(r.primary), s.expected.primary);
      assert.deepStrictEqual(r.alternatives.map(planView), s.expected.alternatives);
    } else {
      assert.strictEqual(r.reason, s.expected.reason);
      assert.strictEqual(r.blockingLabel, s.expected.blockingLabel);
      assert.strictEqual(r.earliestFeasibleReadyAt == null ? null : iso(r.earliestFeasibleReadyAt), s.expected.earliestFeasibleReadyAt);
    }
  });
}

console.log("Check-in scenarios");
for (const c of fixtures.checkInScenarios) {
  check(c.name, () => {
    const ps = planByName[c.planScenario];
    const req = requestFrom(ps.input);
    const plan = H.plan(req, cal).primary;
    const s = H.newSession(plan, plan.firstStepAt);
    for (const st of plan.steps) if (st.attended && st.end <= plan.mixAt + 1000) H.session.complete(s, st.id, st.end);
    const mix = H.planStep(plan, "mix");
    H.session.complete(s, "mix", mix.end + c.mixLateMinutes * H.MIN);
    const now = H.session.bulkClockStart(s) + c.hoursAfterMix * H.HOUR;
    for (const st of s.plan.steps.slice()) if (st.kind === "fold" && st.end <= now) H.session.complete(s, st.id, st.end);
    const r = H.checkIn(s, now, c.rise, c.tempC, ps.input.blocks, cal, req.model);
    assert.strictEqual(iso(now), c.expected.now, "now");
    assert.strictEqual(iso(Math.round(r.estimatedReadyAt / 1000) * 1000), c.expected.estimatedReadyAt, "estimatedReadyAt");
    assert.ok(Math.abs(r.targetRisePercent - c.expected.targetRisePercent) < 1e-9, "target rise");
    assert.deepStrictEqual(
      r.options.map((o) => ({ kind: o.kind, recommended: o.recommended, bulkEndsAt: iso(Math.round(o.bulkEndsAt / 1000) * 1000), conflictLabel: o.conflictLabel, steps: stepsView(o.steps.map((x) => Object.assign({}, x, { start: Math.round(x.start / 1000) * 1000, end: Math.round(x.end / 1000) * 1000 }))) })),
      c.expected.options
    );
  });
}

console.log("Calibration");
check("prior keeps one odd bake from swinging the model", () => {
  const one = H.calibration.record([], { modelHours: 6, actualHours: 3 });
  const k = H.calibration.speedFactor(one);
  assert.ok(k > 1.2 && k < 1.35, `speed ${k}`);
  assert.strictEqual(H.calibration.uncertainty(one), 0.2);
});

check("a fridge-paused bulk is not used for calibration (same rule as Swift)", () => {
  const ps = planByName["Friday morning → Saturday 10:00"];
  const plan = H.plan(requestFrom(ps.input), cal).primary;
  const s = H.newSession(plan, plan.firstStepAt);
  H.session.complete(s, "mix", H.planStep(plan, "mix").end);
  H.session.complete(s, "shape", H.planStep(s.plan, "shape").end);
  s.shapeReadiness = "justRight";
  assert.ok(H.session.calibrationSample(s), "room-temperature bulk yields a sample");
  s.plan.steps.push({ id: "cold-bulk", kind: "coldBulk", start: 0, end: 0, attended: false });
  assert.strictEqual(H.session.calibrationSample(s), null);
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
