/**
 * Minimal Matrix Client-Server API helpers (file + text).
 * Use a long-lived access token (not Element debug token). See TUM challenge brief.
 */

/**
 * @param {string} homeserver e.g. https://matrix.cit.tum.de (no trailing slash preferred)
 * @param {string} accessToken
 * @param {Buffer} buffer
 * @param {string} contentType
 * @param {string} filename
 * @returns {Promise<string>} mxc:// URI
 */
export async function uploadMedia(homeserver, accessToken, buffer, contentType, filename) {
  const base = homeserver.replace(/\/$/, '');
  const q = new URLSearchParams({ filename });
  const url = `${base}/_matrix/media/v3/upload?${q}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': contentType,
    },
    body: buffer,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Matrix upload failed ${res.status}: ${text.slice(0, 500)}`);
  }
  const data = JSON.parse(text);
  if (!data.content_uri) throw new Error('Matrix upload missing content_uri');
  return data.content_uri;
}

/**
 * @param {string} roomId e.g. !abc:example.org
 */
export async function sendFileMessage(
  homeserver,
  accessToken,
  roomId,
  contentUri,
  filename,
  size,
  mime,
) {
  const base = homeserver.replace(/\/$/, '');
  const txnId = `campus${Date.now()}${Math.random().toString(36).slice(2, 10)}`;
  const url = `${base}/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${txnId}`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      msgtype: 'm.file',
      body: filename,
      filename,
      url: contentUri,
      info: {
        mimetype: mime,
        size,
      },
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Matrix send failed ${res.status}: ${text.slice(0, 500)}`);
  }
  return JSON.parse(text);
}

export async function sendTextMessage(homeserver, accessToken, roomId, body) {
  const base = homeserver.replace(/\/$/, '');
  const txnId = `campus${Date.now()}${Math.random().toString(36).slice(2, 10)}`;
  const url = `${base}/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${txnId}`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      msgtype: 'm.text',
      body,
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Matrix text send failed ${res.status}: ${text.slice(0, 500)}`);
  }
  return JSON.parse(text);
}
