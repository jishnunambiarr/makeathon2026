# campus-agent-server

ElevenLabs conversation tokens, TUMonline read tools, and Matrix/Moodle **webhooks**. High-level Coco setup and env overview: [repository README](../../README.md). **Step-by-step** (duplicate agent, tool names, Flutter): [docs/AGENT_SETUP.md](../../docs/AGENT_SETUP.md).

- Mints ephemeral ElevenLabs conversation tokens (WebRTC) for the client
- Exposes **read-only** TUM tools and **webhook** routes for Matrix / Moodle demos

## Setup

Copy [`.env.example`](.env.example) to `.env` and fill in values (do not commit `.env`).

## Run

```bash
cd backend/agent-server
npm install
npm run dev
```

Health check:

- `GET /healthz`

## API

### `POST /agent/session`

Returns a short-lived token to start an ElevenLabs realtime session.

Response:

```json
{ "elevenConversationToken": "..." }
```

### `POST /agent/tool`

Dispatch a read-only tool call.

Request:

```json
{ "tumToken": "…", "tool": "get_grades", "args": {} }
```

Tools implemented:

- `get_my_courses` `{}`
- `get_grades` `{}`
- `search_rooms` `{ query: string }`

### `POST /webhooks/moodle-to-matrix`

Server / webhook tool for ElevenLabs (or any HTTP client): runs `backend/moodle-playwright/scripts/fetch-resource.mjs` with the saved Moodle session,
then posts to Matrix. For demos, prefer `delivery: "link"` (more robust across Moodle course layouts).

Request body:

```json
{
  "courseUrl": "https://moodle.tum.de/course/view.php?id=12345",
  "match": "Tutorial",
  "delivery": "link"
}
```

- **`delivery`** (optional, default **`"link"`**): `"link"` sends a Matrix text: *Here are the assignments for this week:* plus the resolved URL. **`"file"`** downloads and uploads an `m.file` (slower).

Nested `parameters` / `parameter_input` objects are merged the same way ElevenLabs may send them.

Requires:

- `MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN`, `MATRIX_ROOM_ID` in `.env`
- A valid `backend/moodle-playwright/.moodle-storage.json` from `npm run save-session` there
  (override path with `MOODLE_STORAGE_PATH` if needed)

Optional: set `MATRIX_WEBHOOK_SECRET` (or legacy `MOODLE_MATRIX_WEBHOOK_SECRET`) and call with
`Authorization: Bearer <secret>` or header `x-webhook-secret`.

**Hackathon booth (optional):** set `DEMO_MOODLE_COURSE_URL` and `DEMO_MOODLE_MATCH` in `.env` so the ElevenLabs
webhook can use **`{}`** or **`{"demo": true}`** (ElevenLabs often cannot use a completely empty body) — the server fills in the course page URL and substring match
(Playwright still resolves one matching resource link on that page; tune `DEMO_MOODLE_MATCH` to your sheet name,
e.g. `Blatt`, `Übung`, `Assignment`).

### `POST /webhooks/matrix-demo-links`

No Moodle session and no browser: posts a **fixed list** of URLs you configure for the demo.

- Set **`DEMO_ASSIGNMENT_LINKS`** in `.env` to a JSON array: `[{"label":"LA","url":"https://moodle.tum.de/course/view.php?id=…"}, …]`
- Or POST `{ "links": [ … ] }` with the same shape.

Use this when you only need “here are our course pages / assignment links” in Matrix without scraping.

### `POST /webhooks/matrix-message`

Server / webhook tool: posts **plain text** to `MATRIX_ROOM_ID`. Use it when the agent should
push **mensa menus**, **formatted links**, or any short summary it built from other tools.

Request body:

```json
{ "message": "Mensa today:\n• Dish A\n• Dish B\n\nhttps://…" }
```

Also accepts `body` or `text` instead of `message` (some tool UIs use different names).
Same Matrix env vars and optional webhook secret as above.

**ElevenLabs:** register webhooks pointing at your public base URL, e.g.
`…/webhooks/matrix-message` (POST, field `message`, shorter timeout) and
`…/webhooks/moodle-to-matrix` (POST, `courseUrl` + `match`, **long** timeout for Playwright).
The agent host must be reachable from ElevenLabs (deploy or tunnel).

#### Android emulator note

If you're testing the app on the Android emulator, set:

- `AGENT_BACKEND_URL=http://10.0.2.2:8787`

`localhost` in the emulator does **not** point at your host machine.

Use a **non-encrypted** Matrix room (or a bot setup that supports your homeserver’s file flow)
for reliable `m.file` delivery in the hackathon demo.

## Notes

- For the demo, TUMonline tool results return raw XML (`wbservicesbasic.*`). You can parse these into structured JSON later.
- Do not log or persist user tokens in production.
