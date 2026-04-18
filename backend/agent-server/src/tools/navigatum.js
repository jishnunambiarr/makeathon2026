const BASE = 'https://nav.tum.de/api';

export async function searchRooms({ query }) {
  const u = new URL('/api/locations', BASE);
  u.searchParams.set('q', query);
  // Keep response small for agent
  u.searchParams.set('limit', '10');

  const resp = await fetch(u, {
    headers: { accept: 'application/json' },
  });
  const body = await resp.text().catch(() => '');
  if (!resp.ok) {
    throw new Error(`NavigaTUM error ${resp.status}: ${body.slice(0, 500)}`);
  }
  return JSON.parse(body);
}

