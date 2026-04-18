const XI_API_KEY = process.env.XI_API_KEY;
const ELEVEN_AGENT_ID = process.env.ELEVEN_AGENT_ID;

/**
 * Mints a short-lived token for starting a WebRTC conversation session.
 * Docs: https://elevenlabs.io/docs/api-reference/conversations/get-webrtc-token
 */
export async function getElevenConversationToken() {
  if (!XI_API_KEY) throw new Error('XI_API_KEY is not set');
  if (!ELEVEN_AGENT_ID) throw new Error('ELEVEN_AGENT_ID is not set');

  const url = new URL('https://api.elevenlabs.io/v1/convai/conversation/token');
  url.searchParams.set('agent_id', ELEVEN_AGENT_ID);

  const resp = await fetch(url, {
    method: 'GET',
    headers: {
      'xi-api-key': XI_API_KEY,
      'accept': 'application/json',
    },
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => '');
    throw new Error(`ElevenLabs token error: ${resp.status} ${body}`.trim());
  }

  const data = await resp.json();
  if (!data?.token) throw new Error('ElevenLabs response missing token');
  return data.token;
}

