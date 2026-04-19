# Moodle automation (Playwright)

Small helper for **moodle.tum.de** when there is no student API: save a browser session after TUM SSO, then open a **course URL** and resolve a **resource link** (e.g. tutorial PDF) by substring match. Respect the hackathon **Code of Conduct**: rate-limit via delays, do not hammer servers, **never commit** session files or credentials.

## Setup

```bash
cd backend/moodle-playwright
npm install
npx playwright install chromium
```

Optional: copy `.env.example` to `.env` and set `MOODLE_STORAGE_PATH` if you want a path outside this folder.

## 1. Save session (headed login)

Run once (or when SSO session expires):

```bash
npm run save-session
```

1. A Chromium window opens on `https://moodle.tum.de/`.
2. Complete **TUM SSO** (2FA if prompted).
3. When you are logged in, return to the terminal and **press Enter**.

This writes **`MOODLE_STORAGE_PATH`** (default: `.moodle-storage.json`). That file is **gitignored** — **never commit it**.

## 2. Fetch a tutorial / resource link

Use the **course main page** URL (from the browser address bar), e.g. `https://moodle.tum.de/course/view.php?id=…`.

```bash
npm run fetch -- --course-url "https://moodle.tum.de/course/view.php?id=YOUR_ID" --match "Tutorial"
```

- **`--match`**: case-insensitive substring matched against link **text** or **URL** (default: `tutorial`).
- **`--download-dir ./downloads`**: save the file (PDF, etc.) into that folder.
- **`--headed`**: show the browser (debugging).

Stdout is one JSON object, e.g.:

```json
{"ok":true,"title":"Tutorial 3","url":"https://...","downloadedPath":"./downloads/..."}
```

## Environment

| Variable | Default | Meaning |
|----------|---------|--------|
| `MOODLE_STORAGE_PATH` | `.moodle-storage.json` | Playwright storage state file |
| `MOODLE_START_URL` | `https://moodle.tum.de/` | URL opened in `save-session` |
| `MOODLE_ACTION_DELAY_MS` | `1500` | Pause after navigation (be kind to servers) |

## Limitations

- Moodle themes and course layouts differ; if nothing matches, try a more specific `--match` or use `--headed` to inspect.
- **Copyright / licensing**: use only materials you are allowed to access; this tool is for **personal** workflow automation.
- Session cookies expire; re-run `save-session` when fetches start failing with login pages.

## Agent integration (later)

You can wrap `fetch-resource.mjs` in a small HTTP endpoint or subprocess from `agent-server` **on your machine only**, passing course URL and match from the LLM — keep tokens and storage files off public repos.
