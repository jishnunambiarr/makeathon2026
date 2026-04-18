# Voice agent – quick setup

You only need **your own ElevenLabs API key** and **a copy of our agent** (tools + prompt come along with the copy). You do **not** have to recreate every client tool by hand.

## 1. ElevenLabs (two things)

1. **Duplicate (or import) our Conversational AI agent** in [ElevenLabs Agents](https://elevenlabs.io/app/agents) so you get the same tools and prompt. After duplicating, open the new agent and copy its **Agent ID** (`agent_...`) — it is different from ours.
2. **Create an API key** in your ElevenLabs account (profile / API keys). This is only for the token server, not for the Flutter app.

If your workspace shares a **template link** or **agent ID to duplicate**, use that; otherwise ask a maintainer for the canonical agent to copy.

## 2. Token server (keeps the API key off the phone)

```bash
cd backend/agent-server
cp .env.example .env
```

Edit `.env`:

- `XI_API_KEY` = your key  
- `ELEVEN_AGENT_ID` = **your** duplicated agent’s ID (not the original)

```bash
npm install
npm run dev
```

Check: `http://127.0.0.1:8787/healthz` → `{"ok":true}`

## 3. Run Flutter

Point the app at the machine running the server (`AGENT_BACKEND_URL`):

| Device | Example |
|--------|---------|
| Android emulator | `http://10.0.2.2:8787` |
| iOS Simulator | `http://127.0.0.1:8787` |
| Physical phone | `http://<your computer’s LAN IP>:8787` (firewall open on port 8787) |

```bash
flutter run --dart-define=AGENT_BACKEND_URL=http://10.0.2.2:8787
```

Open the **Agent** tab → **Connect** → allow the microphone. Log in to TUM in the app if you want calendar / grades tools.

## Troubleshooting

- **Token errors:** wrong `XI_API_KEY` or `ELEVEN_AGENT_ID`, or server not running.  
- **Unhandled client tool:** duplicated agent is missing a tool or was edited; re-duplicate or compare to the reference agent.  
- **Can’t hear you:** mic permission; on Android emulator, enable host microphone in extended controls.

---

### Advanced: agent from scratch

Only if you are **not** duplicating our agent: client tool **names** in ElevenLabs must match what the app registers (see `AgentClientTools` in `lib/agentComponent/tools/agent_client_tools.dart`). See [ElevenLabs client tools](https://elevenlabs.io/docs/eleven-agents/customization/tools/client-tools).
