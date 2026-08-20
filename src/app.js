import express from "express";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { addExperiment, listExperiments, updateStatus } from "./store.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  app.get("/api/experiments", (_req, res) => {
    res.json({ experiments: listExperiments() });
  });

  app.post("/api/experiments", (req, res, next) => {
    try {
      const experiment = addExperiment(req.body ?? {});
      res.status(201).json({ experiment });
    } catch (err) {
      next(err);
    }
  });

  app.patch("/api/experiments/:id", (req, res, next) => {
    try {
      const experiment = updateStatus(req.params.id, (req.body ?? {}).status);
      res.json({ experiment });
    } catch (err) {
      next(err);
    }
  });

  app.use(express.static(path.join(__dirname, "..", "public")));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    res.status(err.status ?? 500).json({ error: err.message });
  });

  return app;
}
