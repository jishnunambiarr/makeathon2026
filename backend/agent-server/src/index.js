import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { z } from 'zod';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { getElevenConversationToken } from './integrations/elevenlabs.js';
import { dispatchTool } from './tools/dispatch.js';
import { uploadMedia, sendFileMessage, sendTextMessage } from './integrations/matrix.js';
import { runMoodleFetch } from './moodle/runFetch.js';

const app = express();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

function guessMime(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.pdf') return 'application/pdf';
  return 'application/octet-stream';
}

/** Optional shared secret for webhook routes (Bearer or `x-webhook-secret`). */
function getWebhookSecret() {
  return (
    process.env.MATRIX_WEBHOOK_SECRET?.trim() ||
    process.env.MOODLE_MATRIX_WEBHOOK_SECRET?.trim() ||
    ''
  );
}

function requireWebhookSecret(req, res, next) {
  const secret = getWebhookSecret();
  if (!secret) return next();
  const auth = req.headers.authorization;
  const bearer = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  const header = req.headers['x-webhook-secret'];
  if (bearer === secret || header === secret) return next();
  return res.status(401).json({ error: 'unauthorized' });
}

function mergeWebhookBody(body) {
  const b = body ?? {};
  return {
    ...b,
    ...(typeof b.parameters === 'object' && b.parameters ? b.parameters : {}),
    ...(typeof b.parameter_input === 'object' && b.parameter_input ? b.parameter_input : {}),
  };
}

/** Hackathon demo: optional defaults so webhooks need no `courseUrl` / `match` in the tool body. */
function defaultDemoMoodleCourseUrl() {
  return process.env.DEMO_MOODLE_COURSE_URL?.trim() || '';
}

function defaultDemoMoodleMatch() {
  return process.env.DEMO_MOODLE_MATCH?.trim() || 'Blatt';
}

/** Comma-separated alternatives in `DEMO_MOODLE_MATCH` or request body, e.g. `Übungsblatt,Blatt,pdf`. */
function parseMatchAlternatives(matchStr) {
  const s = matchStr == null ? '' : String(matchStr).trim();
  if (!s) return [defaultDemoMoodleMatch()];
  const parts = s.split(',').map((p) => p.trim()).filter(Boolean);
  return parts.length > 0 ? parts : [defaultDemoMoodleMatch()];
}

/**
 * Static list for `POST /webhooks/matrix-demo-links` — no Playwright, no Moodle session.
 * JSON array, e.g. [{"label":"LA","url":"https://moodle.tum.de/course/view.php?id=…"}]
 */
function parseDemoAssignmentLinksFromEnv() {
  const raw = process.env.DEMO_ASSIGNMENT_LINKS?.trim();
  if (!raw) return null;
  try {
    const data = JSON.parse(raw);
    if (!Array.isArray(data) || data.length === 0) return null;
    return data;
  } catch {
    return null;
  }
}

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

/**
 * Server / webhook tool: run Moodle Playwright fetch, then post to Matrix.
 *
 * Default **`delivery`: `"link"`** — sends one text: assignment line + URL (no PDF upload).
 * Use **`delivery`: `"file"`** to download and send an `m.file` (slower; needs a real file URL).
 *
 * Body: `{ "courseUrl"?, "match"?, "delivery"?: "link" | "file" }`
 *
 * If `courseUrl` / `match` are omitted, uses `DEMO_MOODLE_COURSE_URL` and `DEMO_MOODLE_MATCH`
 * from `.env` (hackathon booth). ElevenLabs often cannot send a truly empty body — use
 * `{"demo": true}` (any extra keys are ignored).
 *
 * Env: MATRIX_HOMESERVER, MATRIX_ACCESS_TOKEN, MATRIX_ROOM_ID; optional MOODLE_STORAGE_PATH,
 * DEMO_MOODLE_COURSE_URL, DEMO_MOODLE_MATCH, MATRIX_WEBHOOK_SECRET or MOODLE_MATRIX_WEBHOOK_SECRET.
 */
app.post('/webhooks/moodle-to-matrix', requireWebhookSecret, async (req, res) => {
  const nested = mergeWebhookBody(req.body);

  const courseUrlMerged =
    nested.courseUrl ?? nested.course_url ?? defaultDemoMoodleCourseUrl();
  const matchMerged = (nested.match && String(nested.match).trim()) || defaultDemoMoodleMatch();

  if (!courseUrlMerged) {
    return res.status(400).json({
      error: 'courseUrl_required',
      hint:
        'Pass courseUrl in the webhook body or set DEMO_MOODLE_COURSE_URL in backend/agent-server/.env',
    });
  }

  const schema = z.object({
    courseUrl: z.string().url(),
    match: z.string().min(1),
    delivery: z.enum(['link', 'file']).optional().default('file'),
  });

  const parsed = schema.safeParse({
    courseUrl: courseUrlMerged,
    match: matchMerged,
    delivery: nested.delivery,
  });
  if (!parsed.success) return res.status(400).json({ error: parsed.error.format() });

  const matchList = parseMatchAlternatives(parsed.data.match);

  const homeserver = process.env.MATRIX_HOMESERVER?.trim();
  const accessToken = process.env.MATRIX_ACCESS_TOKEN?.trim();
  const roomId = process.env.MATRIX_ROOM_ID?.trim();

  if (!homeserver || !accessToken || !roomId) {
    return res.status(500).json({
      error: 'matrix_not_configured',
      hint: 'Set MATRIX_HOMESERVER, MATRIX_ACCESS_TOKEN, MATRIX_ROOM_ID in .env',
    });
  }

  const sendErr = async (msg) => {
    try {
      await sendTextMessage(homeserver, accessToken, roomId, msg);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('Matrix sendTextMessage failed', e);
    }
  };

  let downloadDir = null;
  try {
    if (parsed.data.delivery === 'link') {
      let lastJson = { ok: false, error: 'no_matching_link' };
      for (const m of matchList) {
        const { json } = await runMoodleFetch({
          courseUrl: parsed.data.courseUrl,
          match: m,
          linkOnly: true,
        });
        lastJson = json;
        if (json.ok && json.url) {
          const matrixBody = `Here are the assignments for this week:\n${json.url}`;
          const sent = await sendTextMessage(homeserver, accessToken, roomId, matrixBody);

          return res.status(200).json({
            ok: true,
            delivery: 'link',
            moodle: { title: json.title, url: json.url, matchUsed: m },
            matrix: { event_id: sent.event_id },
          });
        }
      }

      const detail = lastJson.error ? String(lastJson.error) : 'fetch_incomplete';
      await sendErr(`Moodle → Matrix: ${detail} (course: ${parsed.data.courseUrl})`);
      return res.status(200).json({ ok: false, moodle: lastJson, matrix: 'notified_room_text' });
    }

    let lastFileJson = { ok: false, error: 'no_matching_link' };
    for (const m of matchList) {
      downloadDir = fs.mkdtempSync(path.join(os.tmpdir(), 'moodle-mx-'));
      const { json } = await runMoodleFetch({
        courseUrl: parsed.data.courseUrl,
        match: m,
        downloadDir,
      });
      lastFileJson = json;
      if (json.ok && json.downloadedPath) {
        break;
      }
      if (downloadDir) fs.rmSync(downloadDir, { recursive: true, force: true });
      downloadDir = null;
    }

    const json = lastFileJson;
    if (!json.ok || !json.downloadedPath) {
      const detail = json.error ? String(json.error) : 'fetch_incomplete';
      await sendErr(`Moodle → Matrix: ${detail} (course: ${parsed.data.courseUrl})`);
      return res.status(200).json({ ok: false, moodle: json, matrix: 'notified_room_text' });
    }

    const localPath = json.downloadedPath;
    if (!path.isAbsolute(localPath) || !fs.existsSync(localPath)) {
      await sendErr(`Moodle → Matrix: missing file after download (${localPath})`);
      return res.status(200).json({ ok: false, moodle: json, matrix: 'notified_room_text' });
    }

    const buf = await readFile(localPath);
    const filename = path.basename(localPath);
    const mime = guessMime(localPath);
    const contentUri = await uploadMedia(homeserver, accessToken, buf, mime, filename);
    const sent = await sendFileMessage(
      homeserver,
      accessToken,
      roomId,
      contentUri,
      filename,
      buf.length,
      mime,
    );

    return res.status(200).json({
      ok: true,
      delivery: 'file',
      moodle: { title: json.title, url: json.url, filename },
      matrix: { event_id: sent.event_id },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    // eslint-disable-next-line no-console
    console.error('[moodle-to-matrix]', message);
    try {
      const homeserver2 = process.env.MATRIX_HOMESERVER?.trim();
      const accessToken2 = process.env.MATRIX_ACCESS_TOKEN?.trim();
      const roomId2 = process.env.MATRIX_ROOM_ID?.trim();
      if (homeserver2 && accessToken2 && roomId2) {
        await sendTextMessage(
          homeserver2,
          accessToken2,
          roomId2,
          `Moodle → Matrix failed: ${message.slice(0, 500)}`,
        );
      }
    } catch {
      /* ignore */
    }
    return res.status(500).json({ error: 'moodle_matrix_failed', message });
  } finally {
    if (downloadDir) fs.rmSync(downloadDir, { recursive: true, force: true });
  }
});

/**
 * Send an arbitrary plain-text message to `MATRIX_ROOM_ID` (mensa menu, links, summaries).
 * The agent composes `message` (e.g. after calling other tools); this only posts to Matrix.
 *
 * Body: `{ "message": "…" }` (also accepts `body` / `text` for ElevenLabs naming quirks).
 *
 * Same env as other Matrix webhooks; optional `MATRIX_WEBHOOK_SECRET` or `MOODLE_MATRIX_WEBHOOK_SECRET`.
 */
app.post('/webhooks/matrix-message', requireWebhookSecret, async (req, res) => {
  const nested = mergeWebhookBody(req.body);

  const schema = z.object({
    message: z.string().min(1).max(16_000),
  });

  const parsed = schema.safeParse({
    message: nested.message ?? nested.body ?? nested.text,
  });
  if (!parsed.success) return res.status(400).json({ error: parsed.error.format() });

  const homeserver = process.env.MATRIX_HOMESERVER?.trim();
  const accessToken = process.env.MATRIX_ACCESS_TOKEN?.trim();
  const roomId = process.env.MATRIX_ROOM_ID?.trim();

  if (!homeserver || !accessToken || !roomId) {
    return res.status(500).json({
      error: 'matrix_not_configured',
      hint: 'Set MATRIX_HOMESERVER, MATRIX_ACCESS_TOKEN, MATRIX_ROOM_ID in .env',
    });
  }

  try {
    const sent = await sendTextMessage(
      homeserver,
      accessToken,
      roomId,
      parsed.data.message,
    );
    return res.status(200).json({
      ok: true,
      matrix: { event_id: sent.event_id },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    // eslint-disable-next-line no-console
    console.error('[matrix-message]', message);
    return res.status(500).json({ error: 'matrix_message_failed', message });
  }
});

/**
 * Hackathon demo: post a fixed list of course / assignment URLs to Matrix — no Playwright, no Moodle session.
 *
 * Set `DEMO_ASSIGNMENT_LINKS` in `.env` (JSON array), or POST `{ "links": [{ "label"?, "url" }] }`.
 * ElevenLabs: if empty `{}` is not allowed, use `{ "demo": true }` — ignored by this handler.
 * Same Matrix env + optional webhook secret as other routes.
 */
app.post('/webhooks/matrix-demo-links', requireWebhookSecret, async (req, res) => {
  const nested = mergeWebhookBody(req.body ?? {});
  let links = null;
  if (Array.isArray(nested.links) && nested.links.length > 0) {
    links = nested.links;
  } else {
    links = parseDemoAssignmentLinksFromEnv();
  }

  if (!links || links.length === 0) {
    return res.status(400).json({
      error: 'links_required',
      hint:
        'Set DEMO_ASSIGNMENT_LINKS in .env (JSON array) or POST { "links": [{ "label": "LA", "url": "https://…" }] }',
    });
  }

  const itemSchema = z.object({
    label: z.string().optional(),
    url: z.string().url(),
  });

  const rows = [];
  for (let i = 0; i < links.length; i += 1) {
    const parsedItem = itemSchema.safeParse(links[i]);
    if (!parsedItem.success) {
      return res.status(400).json({ error: 'invalid_link_item', index: i, detail: parsedItem.error.format() });
    }
    rows.push(parsedItem.data);
  }

  const homeserver = process.env.MATRIX_HOMESERVER?.trim();
  const accessToken = process.env.MATRIX_ACCESS_TOKEN?.trim();
  const roomId = process.env.MATRIX_ROOM_ID?.trim();

  if (!homeserver || !accessToken || !roomId) {
    return res.status(500).json({
      error: 'matrix_not_configured',
      hint: 'Set MATRIX_HOMESERVER, MATRIX_ACCESS_TOKEN, MATRIX_ROOM_ID in .env',
    });
  }

  const bodyText = [
    'Assignment / course links (demo):',
    ...rows.map((r) => `${r.label ? `${r.label}: ` : ''}${r.url}`),
  ].join('\n');

  try {
    const sent = await sendTextMessage(homeserver, accessToken, roomId, bodyText);
    return res.status(200).json({
      ok: true,
      matrix: { event_id: sent.event_id },
      count: rows.length,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    // eslint-disable-next-line no-console
    console.error('[matrix-demo-links]', message);
    return res.status(500).json({ error: 'matrix_demo_links_failed', message });
  }
});

const port = Number(process.env.PORT ?? 8787);
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`agent-server listening on http://localhost:${port}`);
});

