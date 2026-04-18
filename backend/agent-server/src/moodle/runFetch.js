import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import { MOODLE_ROOT, FETCH_SCRIPT } from './paths.js';

/**
 * Run moodle-playwright fetch-resource.mjs; return parsed JSON line from stdout.
 * @param {{ courseUrl: string, match: string, downloadDir?: string | null, linkOnly?: boolean }} opts
 */
export function runMoodleFetch({ courseUrl, match, downloadDir = null, linkOnly = false }) {
  const storagePath =
    process.env.MOODLE_STORAGE_PATH || path.join(MOODLE_ROOT, '.moodle-storage.json');

  if (!fs.existsSync(FETCH_SCRIPT)) {
    return Promise.reject(new Error(`Missing ${FETCH_SCRIPT} — clone includes backend/moodle-playwright`));
  }
  if (!fs.existsSync(storagePath)) {
    return Promise.reject(
      new Error(
        `Missing Moodle session file ${storagePath}. Run: cd backend/moodle-playwright && npm run save-session`,
      ),
    );
  }

  return new Promise((resolve, reject) => {
    const argv = [FETCH_SCRIPT, '--course-url', courseUrl, '--match', match];
    if (linkOnly) argv.push('--link-only');
    if (downloadDir) argv.push('--download-dir', downloadDir);

    const child = spawn(process.execPath, argv, {
      cwd: MOODLE_ROOT,
      env: {
        ...process.env,
        MOODLE_STORAGE_PATH: storagePath,
      },
    });

    let out = '';
    let err = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (c) => {
      out += c;
    });
    child.stderr.on('data', (c) => {
      err += c;
    });
    child.on('error', reject);
    child.on('close', (code) => {
      const trimmed = out.trim();
      const lastLine = trimmed.includes('\n') ? trimmed.split('\n').pop() : trimmed;
      try {
        const json = JSON.parse(lastLine || '{}');
        if (err.trim()) {
          // eslint-disable-next-line no-console
          console.error('[moodle-fetch stderr]', err.trim().slice(0, 2000));
        }
        resolve({ code, json });
      } catch (e) {
        reject(
          new Error(
            `Invalid fetch output (exit ${code}): ${(lastLine || err).slice(0, 400)}`,
          ),
        );
      }
    });
  });
}
