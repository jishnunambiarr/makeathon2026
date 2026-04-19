# Coco — voice agent for TUM Campus (demo fork)

## Extension of the original project

This repo is an **extension** of the open-source [TUM Campus Flutter](https://github.com/TUM-Dev/campus_flutter) app. Upstream is the full student client (calendar, grades, search, maps, cafeterias, MVV, …). We **add** a voice tab (**Coco**), ElevenLabs integration, client tools under `lib/agentComponent/`, `backend/agent-server/` (tokens + webhooks), and optional Moodle/Playwright demos. New code sits alongside the original layout.

**Official upstream app:** https://github.com/TUM-Dev/campus_flutter

## Coco — what we added (Makeathon fork)

A **voice co-pilot** drives the real app through **ElevenLabs client tools** (navigation, search, calendar, Mensa, study rooms, and other reads where APIs already exist). The agent is meant to **act** (screens + tools), not only chat.

**Problem:** workflows are fragmented across tabs. **Approach:** voice + whitelisted tools in `lib/agentComponent/tools/agent_client_tools.dart`. **Outcome:** hands-free use of the same campus data paths as the rest of the app.

- Voice: [`elevenlabs_agents`](https://pub.dev/packages/elevenlabs_agents) + WebRTC, token from `backend/agent-server`.
- Client tools on device; Node `POST /agent/tool` for optional TUMonline reads.
- Rive avatar / lip-sync: `lib/ui/coco_avatar.dart`.
- **Moodle:** no API we could rely on for the demo; `backend/moodle-playwright/` is browser automation only (see server webhooks in [`backend/agent-server/README.md`](backend/agent-server/README.md)).
- **Personalization:** e.g. `get_user_status` returns small JSON from local/session for a better opening line; same pattern can extend to more read/write tools.

## Features (from upstream)

- [x] Calendar Access
- [x] Lecture Details
- [x] Grades
- [x] Tuition Fees Information
- [x] Study Room Availability
- [x] Cafeteria Menus
- [x] Room Maps
- [x] Universal Search: Room
- [x] [TUM.sexy](https://tum.sexy) Redirects

<!--
## Screenshots
| | | | |
|-|-|-|-|
|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 07 47](https://user-images.githubusercontent.com/7985149/107104416-d9125980-6821-11eb-8c06-bc26512e65fb.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 08 14](https://user-images.githubusercontent.com/7985149/107104419-da438680-6821-11eb-83ad-d0cd16c3fe33.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 09 44](https://user-images.githubusercontent.com/7985149/107104428-e3345800-6821-11eb-9169-7e76459a096c.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 09 51](https://user-images.githubusercontent.com/7985149/107104433-e7f90c00-6821-11eb-8e2b-42d21b2ced66.png)|
-->

<!--
## Contributing
You're welcome to contribute to this app!
Check out our detailed information at [CONTRIBUTING.md](https://github.com/TCA-Team/iOS/blob/master/CONTRIBUTING.md)!
-->

## ElevenLabs: how it fits together

| Piece | Role |
|--------|------|
| ElevenLabs agent | Voice + tools; client tool **names/schemas** must match the dashboard. |
| `backend/agent-server` | `XI_API_KEY`, `ELEVEN_AGENT_ID`, Matrix/Moodle env (see `.env.example`); mints **conversation token**; serves webhooks. |
| Flutter | `AgentBackendService` + `ConversationClient` in `lib/agentComponent/screen/agent_screen.dart`. |

**Session flow:** `POST /agent/session` → `elevenConversationToken` → SDK opens the session; tools → `ClientTool.execute` in Dart → JSON back to the model.

**Hands-on checklist:** [docs/AGENT_SETUP.md](docs/AGENT_SETUP.md) (duplicate agent, keys, `AGENT_BACKEND_URL`, troubleshooting).

### Client tools vs webhooks

**Client tools** run in the app (no TUM token to ElevenLabs for those). **Webhooks** hit your HTTP server; ElevenLabs calls from the cloud — use **ngrok** (or deploy) so URLs resolve.

### Client tools (dashboard / `agent_client_tools.dart`)

| Tool | Role |
|------|------|
| `navigate` | Whitelisted in-app route. |
| `open_search` | Search (general / room / person), optional query + tab. |
| `trigger_shortcut` | Quick navigation preset. |
| `open_navigatum_room` | NavigaTUM detail by id. |
| `open_person_details` | Person by obfuscated id. |
| `focus_calendar_range` | Calendar focused date/view. |
| `get_schedule_range` | Schedule by day for a range (logged in). |
| `create_calendar_event` | New event when user confirms; ISO-8601 `from` / `to`; login required. |
| `get_cafeteria_menu` | Mensa; map “tomorrow” etc. to `dayOffset`; fix `cafeteriaId` using tool error hints if needed. |
| `get_free_study_rooms` | Free / light-load study rooms. |
| `get_user_status` | Signed-in profile snippet; we instruct the agent to call once at session start. |

More tools exist in code (news, MVV, room search, grades, courses, …) — same JSON-in/JSON-out pattern.

### Server webhooks (Matrix / Moodle)

Implemented on **`backend/agent-server`** (paths and bodies: [`backend/agent-server/README.md`](backend/agent-server/README.md)).

| Webhook | Purpose |
|---------|---------|
| `moodle_to_matrix` | Moodle course URL + substring → this week’s resource → Matrix (demo; no official Moodle API). |
| `matrix_message` | Plain text to a Matrix room. |

Register the public `https://…/webhooks/…` URLs in ElevenLabs (ngrok while developing). Don’t commit rotating tunnel URLs.

### Memory (personalization)

No embeddings. “Memory” = optional client tools reading/writing small facts in **local storage** (`SharedPreferences` / existing prefs). Keep writes clearable. Fast reads like `get_user_status` can skip the heavy thinking animation — `_toolsWithoutThinkingIndicator` in `agent_screen.dart`.

## Moodle and Playwright

Moodle is mostly **web UI** here. Playwright under `backend/moodle-playwright/` drives a logged-in browser; run `npm run save-session` there so `.moodle-storage.json` exists (**gitignored**). See webhook section in [`backend/agent-server/README.md`](backend/agent-server/README.md).

## Run Coco locally

1. **ElevenLabs** — duplicate or import the reference agent, create an API key, put `ELEVEN_AGENT_ID` and `XI_API_KEY` in `.env`. Details: [docs/AGENT_SETUP.md](docs/AGENT_SETUP.md).

2. **`.env`** in `backend/agent-server/` — copy [`.env.example`](backend/agent-server/.env.example). Minimum for the token server:

```bash
PORT=8787
XI_API_KEY=...
ELEVEN_AGENT_ID=agent_...
```

Add Matrix / demo fields from `.env.example` when using webhooks (`MATRIX_*`, optional `DEMO_*`, etc.).

3. **Start the Node server** — commands, health check, webhook API: [`backend/agent-server/README.md`](backend/agent-server/README.md).

4. **Flutter** — set `AGENT_BACKEND_URL` for your target:

| Target | `AGENT_BACKEND_URL` |
|--------|---------------------|
| Android emulator | `http://10.0.2.2:8787` |
| iOS Simulator | `http://127.0.0.1:8787` |
| Physical device | `http://<your PC LAN IP>:8787` |

```bash
flutter run --dart-define=AGENT_BACKEND_URL=http://10.0.2.2:8787
```

5. **Ngrok** — expose the same host/port you run `agent-server` on so ElevenLabs can reach `/webhooks/…`.

### Permissions

- Android: `RECORD_AUDIO` (for voice)
- iOS: `NSMicrophoneUsageDescription`

### Tool calling (ElevenLabs UI)

Enable **client tools**; names must match the app (see table above).

## Agent-related paths

| Path | Purpose |
|------|---------|
| `lib/agentComponent/screen/agent_screen.dart` | Session + UI |
| `lib/agentComponent/tools/agent_client_tools.dart` | Client tools |
| `lib/agentComponent/services/agent_backend_service.dart` | Token client |
| `backend/agent-server/` | Tokens + `/agent/tool` + webhooks |
| `backend/moodle-playwright/` | Browser session + scripts |

## Security (short)

- Do not commit `.env` or API keys. Use `.env.example` as a template.
- Webhook URLs are public once in ElevenLabs; protect endpoints beyond a demo.
- Don’t store real secrets in agent “memory” fields.

## Development (Flutter)

You need these **dependencies** installed. If something fails, open an issue.

| Dependency | Usage | Where to get it |
|------------|--------|-----------------|
| `Flutter` (includes `Dart`) | SDK for this app | https://docs.flutter.dev/get-started/install |

### Updating the `.proto` files

Install `protoc`, activate the Dart plugin, then:

```bash
dart pub global activate protoc_plugin
export PATH="$PATH:$HOME/.pub-cache/bin"
curl -o protos/tumdev/campus_backend.proto https://raw.githubusercontent.com/TUM-Dev/Campus-Backend/main/server/api/tumdev/campus_backend.proto
protoc --dart_out=grpc:lib/base/networking/apis -I./protos google/protobuf/timestamp.proto google/protobuf/empty.proto tumdev/campus_backend.proto
```

### Currently needed forks

| Package | Reason | Link |
|---------|--------|------|
| gRPC | Caching | https://github.com/jakobkoerber/grpc-dart |
| Xml2Json | XML → JSON | https://github.com/jakobkoerber/xml2json |
| flutter_linkify | Selection / scaling | https://github.com/jakobkoerber/flutter_linkify |
