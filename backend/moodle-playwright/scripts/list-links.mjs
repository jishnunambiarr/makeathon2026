/**
 * Debug helper: dump every link on a Moodle course page so you can pick the
 * right keyword for DEMO_MOODLE_MATCH. Uses the same saved session.
 *
 * Usage:
 *   node scripts/list-links.mjs --course-url "https://www.moodle.tum.de/course/view.php?id=116767"
 */
import { chromium } from 'playwright';
import fs from 'node:fs';

const storagePath = process.env.MOODLE_STORAGE_PATH || '.moodle-storage.json';

function parseArgs() {
  const argv = process.argv.slice(2);
  const out = { courseUrl: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--course-url' && argv[i + 1]) out.courseUrl = argv[++i];
  }
  return out;
}

const args = parseArgs();
if (!args.courseUrl) {
  console.error('Usage: node scripts/list-links.mjs --course-url <url>');
  process.exit(1);
}
if (!fs.existsSync(storagePath)) {
  console.error(`Missing ${storagePath}. Run: npm run save-session`);
  process.exit(1);
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ storageState: storagePath });
const page = await context.newPage();

try {
  await page.goto(args.courseUrl, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.waitForTimeout(1500);

  const finalUrl = page.url();
  const title = await page.title();

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

  console.log(`Final URL: ${finalUrl}`);
  console.log(`Page title: ${title}`);
  console.log(`Total links in #region-main / body: ${links.length}\n`);
  for (const l of links) {
    const shortHref = l.href.length > 120 ? l.href.slice(0, 120) + '…' : l.href;
    console.log(`- "${l.text}"\n    ${shortHref}`);
  }
} finally {
  await browser.close();
}
