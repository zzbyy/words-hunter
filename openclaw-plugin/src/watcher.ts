/**
 * watcher.ts — fs.watch on the words folder using chokidar.
 *
 * On new .md file creation: enqueues a nudge in pending-nudges.json
 * (nudge_due_at = now + 24h). A separate 15-min cron fires overdue nudges.
 *
 * Error handling:
 * - chokidar errors → logged, restart attempted with exponential backoff
 * - 3 consecutive restart failures → persistent warning logged to channel
 *
 * One nudge per file. No deduplication needed (two captures of the same
 * word create two files with different paths — two nudges is expected behavior).
 */

import type { FSWatcher } from 'chokidar';
import path from 'node:path';
import { VaultConfig } from './types.js';
import { nudgeQueuePath, wordsFolderPath, readNudgeQueue, writeNudgeQueue } from './vault.js';

const MAX_RESTART_ATTEMPTS = 3;
const BACKOFF_BASE_MS = 5_000;  // 5s, 10s, 20s

type WatcherLogger = {
  warn: (msg: string) => void;
  error: (msg: string) => void;
};

type ChannelNotifier = {
  sendWarning: (msg: string) => void;
};

export async function startWatcher(
  config: VaultConfig,
  logger: WatcherLogger,
  channel: ChannelNotifier,
): Promise<() => void> {
  // Dynamic import so tests can mock chokidar without the binary
  const chokidar = await import('chokidar');
  let restartCount = 0;
  let watcher: FSWatcher | null = null;
  let stopped = false;

  function launchWatcher(): void {
    if (stopped) return;
    const wordsDir = wordsFolderPath(config);
    watcher = chokidar.watch(wordsDir, {
      ignoreInitial: true,
      depth: 0,
      persistent: true,
    });

    watcher.on('add', (filePath: string) => {
      if (!filePath.endsWith('.md')) return;
      const word = path.basename(filePath, '.md').toLowerCase();
      enqueueNudge(config, word).catch(e => {
        logger.warn(`Failed to enqueue nudge for '${word}': ${String(e)}`);
      });
    });

    watcher.on('error', (error: unknown) => {
      logger.error(`Watcher error: ${String(error)}`);
      void handleCrash();
    });

    // Reset restart counter only after 30s of stable operation
    // (immediate-crash loop would reset it at call-start before any events)
    setTimeout(() => { restartCount = 0; }, 30_000);
  }

  async function handleCrash(): Promise<void> {
    if (stopped) return;
    try { await watcher?.close(); } catch { /* best effort */ }
    watcher = null;

    restartCount++;
    if (restartCount > MAX_RESTART_ATTEMPTS) {
      channel.sendWarning(
        'Word watcher stopped after 3 failed restarts — nudges paused. Restart the OpenClaw plugin to resume.',
      );
      return;
    }

    const backoffMs = BACKOFF_BASE_MS * Math.pow(2, restartCount - 1);
    logger.warn(`Watcher restarting in ${backoffMs}ms (attempt ${restartCount}/${MAX_RESTART_ATTEMPTS})`);
    setTimeout(launchWatcher, backoffMs);
  }

  launchWatcher();

  return function stop(): void {
    stopped = true;
    watcher?.close().catch(() => { /* best effort */ });
  };
}

async function enqueueNudge(config: VaultConfig, word: string): Promise<void> {
  const queuePath = nudgeQueuePath(config);
  const queue = await readNudgeQueue(queuePath);

  const now = new Date();
  const nudgeDue = new Date(now.getTime() + 24 * 60 * 60 * 1000);

  queue.nudges.push({
    word,
    nudge_due_at: nudgeDue.toISOString(),
    created_at: now.toISOString(),
  });

  await writeNudgeQueue(queuePath, queue);
}
