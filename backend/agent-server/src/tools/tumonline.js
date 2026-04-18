const BASE = 'https://campus.tum.de/tumonline/';

function urlFor(slug, params) {
  const u = new URL(slug, BASE);
  for (const [k, v] of Object.entries(params ?? {})) {
    if (v === undefined || v === null) continue;
    u.searchParams.set(k, String(v));
  }
  return u.toString();
}

async function fetchXml(slug, params) {
  const u = urlFor(slug, params);
  const resp = await fetch(u, {
    headers: {
      accept: 'text/xml,application/xml;q=0.9,*/*;q=0.8',
      'user-agent': 'campus-agent-server/0.1',
    },
  });

  const body = await resp.text().catch(() => '');
  if (!resp.ok) {
    throw new Error(`TUMonline error ${resp.status}: ${body.slice(0, 500)}`);
  }
  return { url: u, xml: body };
}

// For demo simplicity, we return raw XML and let the agent summarise.
// You can later parse XML server-side and return structured JSON.

export async function getGrades({ tumToken }) {
  return await fetchXml('wbservicesbasic.noten', { pToken: tumToken });
}

export async function getMyCourses({ tumToken }) {
  return await fetchXml('wbservicesbasic.veranstaltungenEigene', { pToken: tumToken });
}

