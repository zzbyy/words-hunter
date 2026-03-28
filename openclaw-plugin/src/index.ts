/**
 * Words Hunter OpenClaw Plugin
 *
 * Registers 6 tools, 2 crons, and 1 message hook for vocabulary mastery.
 * All state is in {vault}/.wordshunter/mastery.json.
 * Word .md pages are display/content layer.
 */

// NOTE: These imports use the OpenClaw SDK shape documented in SCHEMA.md Appendix A.
// Replace with actual SDK imports when the package is available on ClawHub.
import type { PluginContext } from './sdk-shim.js';
import { loadVaultConfig, masteryJsonPath, nudgeQueuePath, readNudgeQueue, writeNudgeQueue } from './vault.js';
import { importUntracked } from './importer.js';
import { scanVault } from './tools/scan-vault.js';
import { loadWord } from './tools/load-word.js';
import { recordMastery } from './tools/record-mastery.js';
import { updatePage } from './tools/update-page.js';
import { recordSighting } from './tools/record-sighting.js';
import { vaultSummary } from './tools/vault-summary.js';
import { onOutgoingMessage } from './hooks/sighting-hook.js';
import { startWatcher } from './watcher.js';
import { todayString } from './srs/scheduler.js';

export async function onLoad(ctx: PluginContext): Promise<void> {
  // Load vault config (P1 blocker — plugin is inert if config.json absent)
  const configResult = await loadVaultConfig(ctx.vaultRoot);
  if (!configResult.ok) {
    ctx.logger.error(`Words Hunter: ${configResult.error.message}`);
    return;
  }
  const config = configResult.data;

  // One-time import: bring untracked words into mastery.json
  const { imported } = await importUntracked(config);
  if (imported.length > 0) {
    ctx.logger.info(`Words Hunter: imported ${imported.length} untracked word(s): ${imported.join(', ')}`);
  }

  // Start file watcher for 24h capture nudges
  const stopWatcher = await startWatcher(config, ctx.logger, {
    sendWarning: (msg) => ctx.channel.sendToPrimary(msg),
  });
  ctx.onUnload(stopWatcher);

  // Store primary channel on first interaction
  ctx.channel.onFirstInteraction((channelId) => {
    // Persist primary_channel to config.json for routing nudges + recap
    void persistPrimaryChannel(config, channelId);
  });

  // Register tools
  // params are typed as unknown at the SDK boundary; cast inside each handler
  ctx.registerTool('scan_vault', async (params: unknown) => {
    const p = params as { filter?: string };
    const filter = (p.filter ?? 'all') as 'all' | 'due' | 'new';
    return scanVault(config, filter);
  });

  ctx.registerTool('load_word', async (params: unknown) => {
    const p = params as { word: string };
    return loadWord(config, p.word);
  });

  ctx.registerTool('record_mastery', async (params: unknown) => {
    const p = params as { word: string; score: number; best_sentence?: string; failure_note?: string };
    return recordMastery(config, p);
  });

  ctx.registerTool('update_page', async (params: unknown) => {
    const p = params as { word: string; best_sentence?: string; graduation_sentence?: string; content_hash?: string };
    return updatePage(config, p);
  });

  ctx.registerTool('record_sighting', async (params: unknown) => {
    const p = params as { word: string; sentence: string; channel?: string };
    return recordSighting(config, p);
  });

  ctx.registerTool('vault_summary', async (_params: unknown) => {
    return vaultSummary(config);
  });

  // Cron: every 15 minutes — fire overdue nudges
  ctx.registerCron('*/15 * * * *', async () => {
    await fireOverdueNudges(config, ctx);
  });

  // Cron: Sunday 9am — weekly vocab recap
  ctx.registerCron('0 9 * * 0', async () => {
    const result = await vaultSummary(config);
    if (!result.ok) return;
    const s = result.data;
    const msg =
      `Weekly vocab recap:\n` +
      `📚 ${s.total} words total — ${s.mastered} mastered, ${s.reviewing} reviewing, ${s.learning} learning\n` +
      `Today: ${s.due_today} due\n` +
      (s.last_session ? `Last session: ${s.last_session}` : 'No sessions yet — start with /vocab');
    ctx.channel.sendToPrimary(msg);
  });

  // Message hook: detect captured words in outgoing messages
  ctx.registerHook('message:outgoing', async (data: unknown) => {
    const message = data as { text: string; channelId: string };
    const label = ctx.channel.labelFor(message.channelId);
    await onOutgoingMessage(config, message.text, label);
  });
}

import type { VaultConfig } from './types.js';

async function fireOverdueNudges(
  config: VaultConfig,
  ctx: PluginContext,
): Promise<void> {
  const queuePath = nudgeQueuePath(config);
  const queue = await readNudgeQueue(queuePath);
  if (queue.nudges.length === 0) return;

  const now = new Date();
  const toFire = queue.nudges.filter(n => new Date(n.nudge_due_at) <= now);
  if (toFire.length === 0) return;

  // Read mastery to check if word was already practiced
  const { readMasteryStore, masteryJsonPath } = await import('./vault.js');
  const jsonPath = masteryJsonPath(config);
  const storeResult = await readMasteryStore(jsonPath);
  const store = storeResult.ok ? storeResult.data : null;

  for (const nudge of toFire) {
    // Skip if word already has mastery state (user already reviewed)
    if (store?.words[nudge.word]?.sessions && store.words[nudge.word].sessions > 0) continue;
    ctx.channel.sendToPrimary(
      `You just captured "${nudge.word}" yesterday — want to spend 2 minutes on it? Type /vocab to start.`,
    );
  }

  // Remove fired nudges
  queue.nudges = queue.nudges.filter(n => new Date(n.nudge_due_at) > now);
  await writeNudgeQueue(queuePath, queue);
}

async function persistPrimaryChannel(
  config: { vault_path: string; words_folder: string },
  channelId: string,
): Promise<void> {
  // Merge primary_channel into config.json (not overwriting vault_path/words_folder)
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const configPath = path.join(config.vault_path, '.wordshunter', 'config.json');
  try {
    const raw = await fs.readFile(configPath, 'utf8');
    const obj = JSON.parse(raw);
    if (!obj.primary_channel) {
      obj.primary_channel = channelId;
      await fs.writeFile(configPath, JSON.stringify(obj, null, 2), 'utf8');
    }
  } catch { /* best effort */ }
}
