/**
 * Open a Moodle course page and find a resource link matching --match.
 * Optionally download the file into --download-dir.
 *
 * Usage:
 *   npm run fetch -- --course-url "https://moodle.tum.de/course/view.php?id=123" --match "Tutorial"
 *   npm run fetch -- --course-url "..." --match "Blatt" --download-dir ./downloads
 *   npm run fetch -- --course-url "..." --match "Blatt" --link-only   # JSON url only, no download
 *
 * Requires: npm run save-session first (see README).
 */
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const storagePath = process.env.MOODLE_STORAGE_PATH || '.moodle-storage.json';
const delayMs = Number(process.env.MOODLE_ACTION_DELAY_MS || 1500);

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/** True if this href is already a Moodle file endpoint (not an HTML activity wrapper). */
function isLikelyDirectFileHref(href) {
  const h = href.toLowerCase();
  if (h.includes('pluginfile.php')) return true;
  if (h.includes('forcedownload=1') || h.includes('forcedownload=2')) return true;
  if (h.includes('.pdf') && !h.includes('/mod/')) return true;
  return false;
}

/** Activity pages that wrap the real file behind an HTML view. */
function isMoodleFileActivityWrapper(href) {
  const h = href.toLowerCase();
  return (
    h.includes('/mod/resource/view.php') ||
    h.includes('/mod/url/view.php') ||
    h.includes('/mod/folder/view.php') ||
    h.includes('/mod/assign/view.php')
  );
}

/**
 * Open a resource/url/folder view page and find the actual download URL (usually pluginfile.php).
 * @param {import('playwright').Page} page
 * @param {string} activityHref
 * @param {string} needleLower
 * @returns {Promise<{ url: string; linkText: string } | null>}
 */
async function resolveActivityToFileUrl(page, activityHref, needleLower) {
  await page.goto(activityHref, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await sleep(delayMs);

  const found = await page.evaluate(() => {
    const root =
      document.querySelector('#region-main') ||
      document.querySelector('#page-content') ||
      document.body;
    const links = [];
    for (const a of root.querySelectorAll('a[href]')) {
      const href = a.href;
      if (!href || href.startsWith('javascript:')) continue;
      const text = (a.textContent || '').replace(/\s+/g, ' ').trim();
      links.push({ href, text });
    }
    return links;
  });

  let best = null;
  let bestScore = -1;
  for (const l of found) {
    const h = l.href.toLowerCase();
    const t = l.text.toLowerCase();
    let s = 0;
    if (h.includes('pluginfile.php')) s += 6;
    // Assignment intro PDFs: …/pluginfile.php/…/mod_assign/introattachment/…/ue01.pdf
    if (h.includes('introattachment')) s += 8;
    if (h.includes('mod_assign') && h.includes('pluginfile.php')) s += 4;
    if (h.includes('.pdf')) s += 4;
    if (h.includes('forcedownload')) s += 2;
    if (needleLower && (t.includes(needleLower) || h.includes(needleLower))) s += 3;
    if (h.includes('/mod/resource/view.php') || h.includes('/mod/assign/view.php')) s -= 5;
    if (s > bestScore) {
      bestScore = s;
      best = l;
    }
  }

  if (best && bestScore >= 6) {
    return { url: best.href, linkText: best.text };
  }

  const pluginOnly = found.filter((l) => l.href.toLowerCase().includes('pluginfile.php'));
  if (pluginOnly.length === 1) {
    const l = pluginOnly[0];
    return { url: l.href, linkText: l.text };
  }
  if (pluginOnly.length > 1 && needleLower) {
    const byNeedle = pluginOnly.find(
      (l) =>
        l.text.toLowerCase().includes(needleLower) || l.href.toLowerCase().includes(needleLower),
    );
    if (byNeedle) return { url: byNeedle.href, linkText: byNeedle.text };
    const intro = pluginOnly.find((l) => l.href.toLowerCase().includes('introattachment'));
    if (intro) return { url: intro.href, linkText: intro.text };
    const pdf = pluginOnly.find((l) => l.href.toLowerCase().includes('.pdf'));
    if (pdf) return { url: pdf.href, linkText: pdf.text };
  }

  const introOnly = pluginOnly.find((l) => l.href.toLowerCase().includes('introattachment'));
  if (introOnly) return { url: introOnly.href, linkText: introOnly.text };

  const pdfDirect = found.find((l) => /\.pdf(\?|#|$)/i.test(l.href));
  if (pdfDirect) return { url: pdfDirect.href, linkText: pdfDirect.text };

  return null;
}

function parseArgs() {
  const argv = process.argv.slice(2);
  const out = {
    courseUrl: null,
    match: 'tutorial',
    downloadDir: null,
    linkOnly: false,
    headless: true,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--course-url' && argv[i + 1]) out.courseUrl = argv[++i];
    else if (a === '--match' && argv[i + 1]) out.match = argv[++i];
    else if (a === '--download-dir' && argv[i + 1]) out.downloadDir = argv[++i];
    else if (a === '--link-only') out.linkOnly = true;
    else if (a === '--headed') out.headless = false;
  }
  return out;
}

const args = parseArgs();
if (!args.courseUrl) {
  console.error(
    'Usage: node scripts/fetch-resource.mjs --course-url <url> [--match <substring>] [--download-dir <dir>] [--link-only] [--headed]',
  );
  process.exit(1);
}

if (!fs.existsSync(storagePath)) {
  console.error(
    `Missing ${storagePath}. Run: npm run save-session\n(Never commit the storage file.)`,
  );
  process.exit(1);
}

const needle = args.match.toLowerCase();

const browser = await chromium.launch({ headless: args.headless });
const context = await browser.newContext({ storageState: storagePath });
const page = await context.newPage();

try {
  await page.goto(args.courseUrl, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await sleep(delayMs);

  /** @type {{ href: string; text: string }[]} */
  const links = await page.evaluate(() => {
    const root =
      document.querySelector('#region-main') ||
      document.querySelector('#page-content') ||
      document.body;
    const out = [];
    for (const a of root.querySelectorAll('a[href]')) {
      const href = a.href;
      const text = (a.textContent || '').replace(/\s+/g, ' ').trim();
      if (!href || href.startsWith('javascript:')) continue;
      out.push({ href, text });
    }
    return out;
  });

  const candidates = links.filter(
    (l) => l.text.toLowerCase().includes(needle) || l.href.toLowerCase().includes(needle),
  );

  const scored = candidates.map((l) => {
    let score = 0;
    const h = l.href.toLowerCase();
    const t = l.text.toLowerCase();
    if (h.includes('.pdf')) score += 4;
    if (h.includes('pluginfile.php')) score += 3;
    if (h.includes('introattachment')) score += 6;
    if (h.includes('/mod/resource/')) score += 2;
    if (h.includes('/mod/url/')) score += 1;
    if (t.includes(needle)) score += 2;
    // Prefer direct files / intro PDFs over plain assignment activity links when both match.
    if (h.includes('/mod/assign/view.php')) score -= 2;
    if (h.includes('/mod/forum/')) score -= 4;
    if (h.includes('/mod/quiz/')) score -= 4;
    return { ...l, score };
  });

  scored.sort((a, b) => b.score - a.score);
  const best = scored[0];

  if (!best) {
    console.log(
      JSON.stringify({
        ok: false,
        error: 'no_matching_link',
        hint: `No link matched "${args.match}". Try a substring from the assignment/resource title or PDF filename (e.g. ue01).`,
        linkCount: links.length,
      }),
    );
    process.exitCode = 2;
  } else {
    let downloadedPath = null;
    let resultTitle = best.text;
    let downloadUrl = best.href;
    let activityUrl = best.href;

    const mustResolve =
      isMoodleFileActivityWrapper(best.href) && !isLikelyDirectFileHref(best.href);

    if (mustResolve && (args.downloadDir || args.linkOnly)) {
      const resolved = await resolveActivityToFileUrl(page, best.href, needle);
      if (!resolved) {
        console.log(
          JSON.stringify({
            ok: false,
            error: 'could_not_resolve_file_url',
            hint:
              'Opened the Moodle activity page but found no pluginfile.php / PDF link. Try --headed or another --match.',
            url: best.href,
            title: best.text,
          }),
        );
        process.exitCode = 3;
      } else {
        downloadUrl = resolved.url;
        activityUrl = best.href;
        if (resolved.linkText) resultTitle = resolved.linkText;
      }
    }

    if (args.downloadDir && !process.exitCode) {
      fs.mkdirSync(args.downloadDir, { recursive: true });
      const res = await context.request.get(downloadUrl, { timeout: 120_000 });
      if (!res.ok()) {
        console.log(
          JSON.stringify({
            ok: false,
            error: 'download_failed',
            status: res.status(),
            url: downloadUrl,
            title: resultTitle,
            ...(activityUrl !== downloadUrl ? { activityUrl } : {}),
          }),
        );
        process.exitCode = 3;
      } else {
        const cd = res.headers()['content-disposition'];
        let filename = 'resource';
        if (cd) {
          const m = /filename\*?=(?:UTF-8'')?["']?([^"';]+)/i.exec(cd);
          if (m) filename = decodeURIComponent(m[1].trim());
        }
        if (filename === 'resource') {
          try {
            const u = new URL(downloadUrl);
            const base = path.basename(u.pathname);
            if (base && base !== '/') filename = base.split('?')[0];
          } catch {
            /* ignore */
          }
        }
        const safe = filename.replace(/[^a-zA-Z0-9._-]+/g, '_');
        downloadedPath = path.join(args.downloadDir, safe);
        const buf = await res.body();
        fs.writeFileSync(downloadedPath, buf);
      }
    }

    const errored = process.exitCode === 2 || process.exitCode === 3;
    if (!errored) {
      const payload = {
        ok: true,
        title: resultTitle,
        url: downloadUrl,
        downloadedPath,
      };
      if (activityUrl !== downloadUrl) payload.activityUrl = activityUrl;
      console.log(JSON.stringify(payload));
    }
  }
} finally {
  await browser.close();
}
