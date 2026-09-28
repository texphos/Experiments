// End-to-end test of the browser companion prototype in headless Chrome.
// Loads the single-file build over file:// (as a Windows user double-clicking it would) and walks the whole loop.
// Usage: npm ci && CHROME_PATH=/path/to/chrome node e2e.test.js
"use strict";
const path = require("path");
const fs = require("fs");
const puppeteer = require("puppeteer-core");

const FILE = "file://" + path.join(__dirname, "hearthday-prototype.html").replace(/\\/g, "/");
const OUT = process.env.SCREENSHOT_DIR || path.join(__dirname, "e2e-screenshots");
const CHROME = process.env.CHROME_PATH || "/usr/bin/google-chrome";
fs.mkdirSync(OUT, { recursive: true });

let passed = 0, failed = 0;
function check(name, cond, detail) {
  if (cond) { passed++; console.log(`  ok  ${name}`); } else { failed++; console.log(`  FAIL ${name}${detail ? `: ${detail}` : ""}`); }
}

(async () => {
  const browser = await puppeteer.launch({ executablePath: CHROME, args: ["--no-sandbox", "--allow-file-access-from-files"] });
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("dialog", (d) => d.accept());
  await page.setViewport({ width: 1100, height: 1000 });

  const pause = (ms = 60) => new Promise((r) => setTimeout(r, ms));
  const click = async (sel) => { await page.waitForSelector(sel, { timeout: 5000 }); await page.click(sel); await pause(); };
  const shot = (name) => page.screenshot({ path: path.join(OUT, `${name}.png`) });
  const text = () => page.$eval("#screen", (e) => e.innerText);
  const has = (sel) => page.$(sel).then(Boolean);
  const stored = () => page.evaluate(() => JSON.parse(localStorage.getItem("hearthday-prototype-v1") || "null"));
  const setCustomTime = (offsetMs) => page.$eval('[data-action="custom"]', (el, off) => {
    const s = JSON.parse(localStorage.getItem("hearthday-prototype-v1"));
    const t = new Date(Date.now() + (s ? s.simOffset : 0) + off);
    el.value = new Date(t - t.getTimezoneOffset() * 60e3).toISOString().slice(0, 16);
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }, offsetMs);
  const fresh = async () => { await page.goto(FILE); await page.evaluate(() => localStorage.clear()); await page.reload(); };
  const onboard = async () => { await click('[data-action="obNext"]'); await click('[data-action="obNext"]'); await click('[data-action="obNext"]'); };
  const planAndStart = async () => {
    await click('[data-action="plan"]');
    await page.waitForFunction(() => document.querySelector('[data-action="start"], [data-action="earliest"]'), { timeout: 20000 });
    if (await has('[data-action="earliest"]')) {
      await click('[data-action="earliest"]');
      await page.waitForSelector('[data-action="start"]', { timeout: 20000 });
    }
    await click('[data-action="start"]');
  };

  for (const scheme of ["light", "dark"]) {
    console.log(`Complete loop (${scheme})`);
    await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: scheme }]);
    await fresh();
    check("banner says this is not the iOS app", /not the native iOS app/.test(await page.$eval(".proto-banner", (e) => e.innerText)));
    await shot(`${scheme}-01-onboarding`);
    await click('[data-action="obNext"]');
    await shot(`${scheme}-02-busy-times`);
    await click('[data-action="obNext"]');
    await click('[data-action="obNext"]');
    await shot(`${scheme}-03-home`);
    await click('[data-action="plan"]');
    await page.waitForFunction(() => document.querySelector('[data-action="start"], [data-action="earliest"]'), { timeout: 20000 });
    if (await has('[data-action="earliest"]')) { await click('[data-action="earliest"]'); await page.waitForSelector('[data-action="start"]', { timeout: 20000 }); }
    await shot(`${scheme}-04-plan`);
    check("plan shows an estimate with its uncertainty", /give or take \d+%/.test(await text()));
    await click('[data-action="start"]');
    check("reminders are scheduled after starting", await has('[data-testid="reminders"]'));

    for (let i = 0; i < 8; i++) {
      await click('[data-sim="next"]');
      const label = await page.$eval('[data-action="done"]', (b) => b.getAttribute("aria-label"));
      await click('[data-action="done"]');
      if (/Mix dough/.test(label)) break;
    }
    check("bulk has started", await has('[data-action="checkin"]'));
    await click('[data-sim="60"]');
    await click('[data-sim="60"]');
    await shot(`${scheme}-05-live`);
    const before = await page.$eval('[data-testid="reminders"]', (e) => e.innerText).catch(() => "");

    await click('[data-action="checkin"]');
    await page.$eval('[data-action="rise"]', (el) => { el.value = "90"; el.dispatchEvent(new Event("input", { bubbles: true })); });
    await click('[data-action="replan"]');
    await page.waitForSelector('[data-action="choose"], [data-action="logCheckin"]');
    const sheetText = await page.$eval(".sheet", (e) => e.innerText);
    check("check-in summary is hedged, not certain", /Go by the dough|estimate|likely/i.test(sheetText) && !/guarantee|will be ready|perfect/i.test(sheetText), sheetText.slice(0, 200));
    await shot(`${scheme}-06-checkin`);
    if (await has('[data-action="choose"]')) {
      await click('[data-action="choose"]');
      const after = await page.$eval('[data-testid="reminders"]', (e) => e.innerText).catch(() => "");
      check("re-plan replaces the reminder list", await has('[data-testid="reminders-updated"]') && after !== before, `${before} -> ${after}`);
      check("session records the re-plan", (await stored()).session.replanCount === 1);
    } else {
      await click('[data-action="logCheckin"]');
      check("no clean re-plan was offered (logged instead)", true);
    }

    await page.reload();
    check("bake in progress survives a reload", /Check the dough|Re-planned/.test(await text()));

    for (let i = 0; i < 25; i++) {
      if (await has('[data-action="ready"]')) await click('[data-action="ready"][data-v="justRight"]');
      if (await has('.card [data-action="finish"].btn')) break;
      await click('[data-sim="next"]');
      if (await has('[data-action="done"]')) await click('[data-action="done"]');
    }
    check("bread's out state reached", /Bread’s out/.test(await text()));
    check("no reminders left once baked", !(await has('[data-testid="reminders"]')));
    await click('.card [data-action="finish"]');
    await click('[data-action="star"][data-i="4"]');
    await page.type('[data-action="notes"]', "Open crumb, a little pale.");
    await shot(`${scheme}-07-log`);
    await click('[data-action="saveFinish"]');
    await click('[data-tab="journal"]');
    await shot(`${scheme}-08-journal`);
    const journal = await text();
    check("journal lists the bake with notes", /Everyday country loaf/.test(journal) && /Open crumb/.test(journal));
    check("history persisted", (await stored()).history.length === 1 && (await stored()).session === null);
    await click('[data-tab="settings"]');
    await click('[data-action="pro"]');
    await shot(`${scheme}-09-pro`);
    check("prototype cannot take a purchase", await page.$eval('.sheet .btn[disabled]', (b) => /9\.99/.test(b.innerText)).catch(() => false));
  }

  await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: "light" }]);
  console.log("Invalid and infeasible input");
  await fresh(); await onboard();
  await setCustomTime(-2 * 3600e3);
  await click('[data-action="plan"]');
  await page.waitForSelector('[data-testid="plan-invalid"]', { timeout: 5000 }).catch(() => {});
  check("a past ready time is refused with a reason", /Pick a time in the future/.test(await text()));
  await shot("invalid-past-time");
  await click('[data-action="closeResult"]');
  await setCustomTime(20 * 24 * 3600e3);
  await click('[data-action="plan"]');
  await pause(200);
  check("a ready time weeks away is refused", /within the next 7 days/.test(await text()));
  await click('[data-action="closeResult"]');
  await setCustomTime(3 * 3600e3);
  await click('[data-action="plan"]');
  await page.waitForFunction(() => /doesn’t fit/.test(document.querySelector("#screen").innerText), { timeout: 20000 }).catch(() => {});
  check("an impossible time says no instead of scheduling at night", /doesn’t fit/.test(await text()));
  await shot("infeasible");

  console.log("Busy-time editor");
  await click('[data-tab="settings"]');
  await click('[data-action="addBlock"]');
  await page.$eval('[data-action="bend"]', (el) => { el.value = "15:00"; el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true })); });
  await pause();
  check("zero-length busy time cannot be saved", await page.$eval('[data-action="saveBlock"]', (b) => b.disabled) && /can’t be the same time/.test(await page.$eval(".sheet", (e) => e.innerText)));
  await page.$eval('[data-action="bend"]', (el) => { el.value = "07:00"; el.dispatchEvent(new Event("input", { bubbles: true })); el.dispatchEvent(new Event("change", { bubbles: true })); });
  await pause();
  check("overnight busy time explains next-day and daylight-saving handling", /Ends the next day\. Times follow your iPhone’s clock, including daylight-saving/.test(await page.$eval(".sheet", (e) => e.innerText)));
  for (const d of [2, 3, 4, 5, 6]) await click(`[data-action="bday"][data-d="${d}"]`);
  check("busy time with no days cannot be saved", await page.$eval('[data-action="saveBlock"]', (b) => b.disabled));
  await shot("busy-time-editor");
  await click('[data-action="closeSheet"]');

  console.log("Recovery after time away");
  await fresh(); await onboard(); await planAndStart();
  await click('[data-sim="next"]');
  await click('[data-sim="60"]');
  await page.reload();
  check("a missed step shows as overdue after reopening", await has('[data-testid="live-overdue"]') && /Was due .* ago/.test(await text()));
  await shot("overdue");
  for (let i = 0; i < 40 && !(await has('[data-testid="live-stale"]')); i++) await click('[data-sim="240"]');
  check("a long-abandoned bake asks whether it finished", await has('[data-testid="live-stale"]'));
  await shot("stale");
  await click('[data-testid="live-stale"] [data-action="abandon"]');
  check("abandoning clears the bake and its reminders", (await stored()).session === null && /nothing is scheduled/.test(await page.$eval("#reminders", (e) => e.innerText)));

  console.log("Fridge rescue and late shaping");
  // Built from the same core the page runs: a fridge-proof bake mixed 2 h ago, with bedtime 30 min away, so the
  // check-in offers "fridge before bed". Busy times are set to that bedtime so the page sees the same conflict.
  await fresh(); await onboard();
  const rescue = await page.evaluate(() => {
    const H = window.HearthdayCore, cal = H.makeCalendar(false), real = Date.now();
    const p = H.plan({ now: real, readyBy: real + 34 * H.HOUR, kitchenTempC: 21, blocks: [], proofModes: ["fridge"], starterNeedsFeed: false, allowInoculationAdjustment: false }, cal).primary;
    if (!p) return { error: "no plan" };
    const s = H.newSession(p, real);
    const mix = H.planStep(p, "mix");
    H.session.complete(s, "mix", mix.end, [], cal);
    const simNow = H.session.bulkClockStart(s) + 2 * H.HOUR;
    for (const st of s.plan.steps.slice()) if (st.kind === "fold") H.session.complete(s, st.id, st.end);
    const bed = new Date(simNow + 30 * H.MIN);
    const start = bed.getHours() * 60 + bed.getMinutes();
    const blocks = [{ label: "Sleep", kind: "sleep", weekdays: [1, 2, 3, 4, 5, 6, 7], startMinute: start, endMinute: (start + 9 * 60) % 1440 }];
    const r = H.checkIn(s, simNow, 40, 21, blocks, cal, {});
    const fridge = r.options.find((o) => o.kind === "fridgeNow");
    if (!fridge) return { error: `no fridge option: ${r.options.map((o) => o.kind).join(",")} ${r.summary}` };
    H.session.apply(s, fridge);
    const st = JSON.parse(localStorage.getItem("hearthday-prototype-v1"));
    st.settings.blocks = blocks;
    st.session = s;
    st.simOffset = simNow - real;
    localStorage.setItem("hearthday-prototype-v1", JSON.stringify(st));
    return { ok: true };
  });
  check("fridge rescue scenario could be built", rescue.ok, rescue.error);
  if (rescue.ok) {
    await page.reload();
    const live = await text();
    check("putting the dough in the fridge is a hands-on step with a reminder",
      /Next, in .*\n?.*Put the dough in the fridge/s.test(live) && /Put the dough in the fridge/.test(await page.$eval("#reminders", (e) => e.innerText)), live.slice(0, 300));
    check("check-ins stay available until the dough actually goes in", await has('[data-action="checkin"]'));
    await click('[data-sim="next"]');
    await click('[data-action="done"]');
    check("once chilled, check-ins are gone", !(await has('[data-action="checkin"]')));
    const chilledText = await text();
    check("the chilled dough shows as finishing bulk in the fridge", /Finish bulk in fridge/.test(chilledText));
    check("shaping chilled dough gives no room-temperature window and suggests no check-in",
      /Shape it straight from the fridge/.test(chilledText) && !/Likely ready/.test(chilledText) && !/Check in first/.test(chilledText), chilledText.slice(0, 400));
    await shot("fridge-chilled");
    await page.evaluate(() => {
      const st = JSON.parse(localStorage.getItem("hearthday-prototype-v1"));
      const bake = st.session.plan.steps.find((x) => x.id === "bake");
      st.simOffset = bake.start - 2 * 3600e3 - Date.now();
      localStorage.setItem("hearthday-prototype-v1", JSON.stringify(st));
    });
    await page.reload();
    const lateLabel = await page.$eval('[data-action="done"]', (b) => b.getAttribute("aria-label")).catch(() => "");
    check("shape is the overdue step", /Shape/.test(lateLabel), lateLabel);
    await click('[data-action="done"]');
    const note = await page.$eval('[data-testid="live-adjustment"]', (e) => e.innerText).catch(() => "");
    check("shaping late moves the bake and says why", /Shaping ran late, so the bake moved later to give the cold proof at least 8 h/.test(note), note);
    const after = (await stored()).session.plan.steps;
    const retard = after.find((x) => x.id === "cold-proof"), bakeStep = after.find((x) => x.id === "bake");
    check("the cold proof is never shorter than 8 h", retard.end - retard.start >= 8 * 3600e3 && retard.end === bakeStep.start);
    await shot("late-shape-adjusted");
  }

  console.log("Corrupt saved data");
  await page.evaluate(() => localStorage.setItem("hearthday-prototype-v1", "{not json"));
  await page.reload();
  check("unreadable data is set aside with a notice", /couldn’t be read/.test(await text()) && await page.evaluate(() => Object.keys(localStorage).some((k) => k.includes("unreadable"))));
  await page.evaluate(() => localStorage.setItem("hearthday-prototype-v1", JSON.stringify({ settings: { onboarded: true, kitchenTempC: 99, blocks: [{ label: "x", kind: "other", weekdays: [], startMinute: 5, endMinute: 5 }] }, formulas: [{ id: "a", name: "", flourGrams: -1 }] })));
  await page.reload();
  const repaired = await page.evaluate(() => { const s = window.localStorage.getItem("hearthday-prototype-v1"); return s; });
  check("out-of-range values are repaired, not trusted", /Plan it/.test(await text()) && !/99 °C/.test(await text()), repaired);

  console.log("Accessibility basics");
  const unnamed = await page.$$eval("button, input, select", (els) => els.filter((e) => !(e.getAttribute("aria-label") || e.innerText.trim() || (e.labels && e.labels.length) || e.getAttribute("title"))).map((e) => e.outerHTML.slice(0, 80)));
  check("every control has an accessible name", unnamed.length === 0, unnamed.join(" "));

  check("no script errors", errors.length === 0, errors.join(" | "));
  await browser.close();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error("E2E FAILED:", e); process.exit(1); });
