const listEl = document.getElementById("list");
const emptyEl = document.getElementById("empty");
const countEl = document.getElementById("count");
const form = document.getElementById("new-experiment");
const errorEl = document.getElementById("form-error");

const STATUSES = ["planned", "running", "done"];

async function fetchJSON(url, options) {
  const res = await fetch(url, options);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.error || `Request failed (${res.status})`);
  }
  return data;
}

function render(experiments) {
  countEl.textContent = String(experiments.length);
  emptyEl.hidden = experiments.length > 0;
  listEl.innerHTML = "";

  for (const exp of experiments) {
    const li = document.createElement("li");
    li.className = "item";

    const left = document.createElement("div");
    const title = document.createElement("div");
    title.className = "item-title";
    title.textContent = exp.title;
    left.appendChild(title);
    if (exp.hypothesis) {
      const hyp = document.createElement("p");
      hyp.className = "item-hyp";
      hyp.textContent = exp.hypothesis;
      left.appendChild(hyp);
    }

    const select = document.createElement("select");
    select.className = "status badge";
    for (const status of STATUSES) {
      const option = document.createElement("option");
      option.value = status;
      option.textContent = status;
      option.selected = status === exp.status;
      select.appendChild(option);
    }
    select.addEventListener("change", async () => {
      await fetchJSON(`/api/experiments/${exp.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: select.value }),
      });
      await load();
    });

    li.appendChild(left);
    li.appendChild(select);
    listEl.appendChild(li);
  }
}

async function load() {
  const { experiments } = await fetchJSON("/api/experiments");
  render(experiments);
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorEl.hidden = true;
  const title = document.getElementById("title").value;
  const hypothesis = document.getElementById("hypothesis").value;
  try {
    await fetchJSON("/api/experiments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, hypothesis }),
    });
    form.reset();
    await load();
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.hidden = false;
  }
});

load().catch((err) => {
  errorEl.textContent = err.message;
  errorEl.hidden = false;
});
