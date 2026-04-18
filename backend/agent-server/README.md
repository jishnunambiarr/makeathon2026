# campus-agent-server

Minimal Node.js backend for the hackathon agent demo:

- Mints ephemeral ElevenLabs conversation tokens (WebRTC) for the client
- Exposes a small set of **read-only** tools that fetch data from TUM services

## Setup

Create `backend/agent-server/.env`:

```bash
PORT=8787
XI_API_KEY=...
ELEVEN_AGENT_ID=...
```

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

## Notes

- For the demo, TUMonline tool results return raw XML (`wbservicesbasic.*`). You can parse these into structured JSON later.
- Do not log or persist user tokens in production.

