# Experiments

A minimal full-stack app for tracking experiments — ideas, their hypotheses, and
their status. It serves as the baseline development experience for this
repository: a small Express JSON API with a static frontend.

## Requirements

- Node.js >= 20 (developed against Node 22)

## Getting started

```bash
npm ci        # install dependencies from the lockfile
npm run dev   # start the server with auto-reload on http://localhost:3000
```

Then open http://localhost:3000 and add an experiment.

## Scripts

| Command | Description |
| --- | --- |
| `npm start` | Run the server. |
| `npm run dev` | Run the server with file watching (auto-reload). |
| `npm test` | Run the API test suite (`node --test`). |

## API

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/health` | Health check. |
| `GET` | `/api/experiments` | List experiments (newest first). |
| `POST` | `/api/experiments` | Create an experiment (`{ title, hypothesis }`). |
| `PATCH` | `/api/experiments/:id` | Update status (`planned`, `running`, `done`). |

Data is stored in memory, so it resets when the server restarts.

## Project layout

```
src/        Express app, server entry point, and data store
public/     Static frontend (HTML, CSS, JS)
test/       API tests
```

## Cloud Agent environment

`.cursor/environment.json` configures the Cloud Agent environment: `npm ci`
installs dependencies and the `server` terminal runs `npm run dev` on port 3000.
