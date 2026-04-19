import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** Root of `backend/moodle-playwright` (`src/moodle` → `agent-server` → `backend`). */
export const MOODLE_ROOT = path.join(__dirname, '..', '..', '..', 'moodle-playwright');
export const FETCH_SCRIPT = path.join(MOODLE_ROOT, 'scripts', 'fetch-resource.mjs');
