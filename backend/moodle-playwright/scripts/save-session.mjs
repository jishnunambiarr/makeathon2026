/**
 * One-time (or occasional) headed login: complete TUM SSO in the browser,
 * then press Enter here to save cookies/localStorage to MOODLE_STORAGE_PATH.
 *
 * Usage:
 *   npm install && npx playwright install chromium
 *   npm run save-session
 */
import { chromium } from 'playwright';
import * as readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';

const storagePath = process.env.MOODLE_STORAGE_PATH || '.moodle-storage.json';
const startUrl = process.env.MOODLE_START_URL || 'https://moodle.tum.de/';

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext();
const page = await context.newPage();

await page.goto(startUrl, { waitUntil: 'domcontentloaded' });

const rl = readline.createInterface({ input, output });
console.log('\nComplete TUM / Moodle login in the browser window.');
console.log('When you see your dashboard or a course list, return here.\n');
await rl.question('Press Enter to save session state… ');
await rl.close();

await context.storageState({ path: storagePath });
console.log(`Saved session to ${storagePath} (add to .gitignore — do not commit).`);
await browser.close();
