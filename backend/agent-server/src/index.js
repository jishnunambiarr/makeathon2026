import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { z } from 'zod';
import { getElevenConversationToken } from './integrations/elevenlabs.js';
import { dispatchTool } from './tools/dispatch.js';

const app = express();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/healthz', (_req, res) => res.json({ ok: true }));

/**
 * Mint an ephemeral token for the client to start an ElevenLabs realtime session.
 *
 * This endpoint MUST be called from your app/backend only (never expose XI_API_KEY).
 *
 * Env:
 * - XI_API_KEY
 * - ELEVEN_AGENT_ID
 */
app.post('/agent/session', async (req, res) => {
  const schema = z.object({
    // For demo simplicity we accept the app's TUM token, but we do not store it.
    // The realtime voice session itself does not need it; tools do.
    tumToken: z.string().min(1).optional(),
  });

  const parsed = schema.safeParse(req.body ?? {});
  if (!parsed.success) return res.status(400).json({ error: parsed.error.format() });

  try {
    const token = await getElevenConversationToken();
    return res.json({ elevenConversationToken: token });
  } catch (e) {
    return res.status(500).json({
      error: 'failed_to_mint_eleven_token',
      message: e instanceof Error ? e.message : String(e),
    });
  }
});

/**
 * Read-only tool dispatcher for the agent.
 * Body: { tumToken, tool, args }
 */
app.post('/agent/tool', async (req, res) => {
  const schema = z.object({
    tumToken: z.string().min(1),
    tool: z.string().min(1),
    args: z.record(z.any()).default({}),
  });

  const parsed = schema.safeParse(req.body ?? {});
  if (!parsed.success) return res.status(400).json({ error: parsed.error.format() });

  try {
    const result = await dispatchTool({
      tumToken: parsed.data.tumToken,
      tool: parsed.data.tool,
      args: parsed.data.args,
    });
    return res.json({ result });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return res.status(500).json({ error: 'tool_failed', message });
  }
});

const port = Number(process.env.PORT ?? 8787);
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`agent-server listening on http://localhost:${port}`);
});

