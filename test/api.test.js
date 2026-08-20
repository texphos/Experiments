import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { _reset } from "../src/store.js";

async function start() {
  const server = createApp().listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;
  return {
    base,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

beforeEach(() => _reset());

test("health endpoint responds ok", async () => {
  const { base, close } = await start();
  try {
    const res = await fetch(`${base}/api/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: "ok" });
  } finally {
    await close();
  }
});

test("create and list experiments", async () => {
  const { base, close } = await start();
  try {
    const create = await fetch(`${base}/api/experiments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Cache warmup", hypothesis: "Faster boot" }),
    });
    assert.equal(create.status, 201);
    const { experiment } = await create.json();
    assert.equal(experiment.title, "Cache warmup");
    assert.equal(experiment.status, "planned");

    const list = await fetch(`${base}/api/experiments`);
    const { experiments } = await list.json();
    assert.equal(experiments.length, 1);
    assert.equal(experiments[0].title, "Cache warmup");
  } finally {
    await close();
  }
});

test("rejects empty title", async () => {
  const { base, close } = await start();
  try {
    const res = await fetch(`${base}/api/experiments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "   " }),
    });
    assert.equal(res.status, 400);
  } finally {
    await close();
  }
});

test("update experiment status", async () => {
  const { base, close } = await start();
  try {
    const create = await fetch(`${base}/api/experiments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Index tuning" }),
    });
    const { experiment } = await create.json();

    const patch = await fetch(`${base}/api/experiments/${experiment.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "running" }),
    });
    assert.equal(patch.status, 200);
    const updated = await patch.json();
    assert.equal(updated.experiment.status, "running");

    const bad = await fetch(`${base}/api/experiments/${experiment.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "nope" }),
    });
    assert.equal(bad.status, 400);
  } finally {
    await close();
  }
});
