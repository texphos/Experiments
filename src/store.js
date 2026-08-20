// In-memory data store for experiments. Kept separate from the HTTP layer so it
// can be unit-tested without starting a server.

let nextId = 1;
const experiments = [];

export function listExperiments() {
  return experiments.slice().sort((a, b) => b.createdAt - a.createdAt);
}

export function addExperiment({ title, hypothesis }) {
  const cleanTitle = typeof title === "string" ? title.trim() : "";
  if (!cleanTitle) {
    const err = new Error("title is required");
    err.status = 400;
    throw err;
  }

  const experiment = {
    id: nextId++,
    title: cleanTitle,
    hypothesis: typeof hypothesis === "string" ? hypothesis.trim() : "",
    status: "planned",
    createdAt: Date.now(),
  };
  experiments.push(experiment);
  return experiment;
}

export function updateStatus(id, status) {
  const allowed = ["planned", "running", "done"];
  if (!allowed.includes(status)) {
    const err = new Error(`status must be one of: ${allowed.join(", ")}`);
    err.status = 400;
    throw err;
  }

  const experiment = experiments.find((e) => e.id === Number(id));
  if (!experiment) {
    const err = new Error("experiment not found");
    err.status = 404;
    throw err;
  }
  experiment.status = status;
  return experiment;
}

// Test hook to keep state isolated between test cases.
export function _reset() {
  experiments.length = 0;
  nextId = 1;
}
