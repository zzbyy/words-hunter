/**
 * Shared discovery file for bidirectional config between the Words Hunter
 * macOS app and the OpenClaw plugin.
 *
 * Path: ~/Library/Application Support/WordsHunter/discovery.json
 *
 * Both the Swift app and this plugin read and write the same file.
 * Atomic temp+rename on both sides prevents partial reads.
 * Last writer wins — single-user desktop tool, no locking needed.
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

export interface DiscoveryConfig {
  version: number;
  words_directory: string;
  words_folder: string;
  updated_by: string;
  updated_at: string;
}

const DISCOVERY_DIR = path.join(os.homedir(), 'Library', 'Application Support', 'WordsHunter');
export const DISCOVERY_PATH = path.join(DISCOVERY_DIR, 'discovery.json');

/**
 * Read the shared discovery file.
 * Returns null if the file is missing, invalid, or the directory no longer exists on disk.
 */
export async function readDiscovery(): Promise<DiscoveryConfig | null> {
  try {
    const raw = await fs.readFile(DISCOVERY_PATH, 'utf8');
    const parsed = JSON.parse(raw) as DiscoveryConfig;
    if (parsed.version !== 1 || !parsed.words_directory) return null;
    // Validate the words directory still exists
    await fs.access(parsed.words_directory);
    return parsed;
  } catch {
    return null;
  }
}

/**
 * Write the shared discovery file atomically.
 * Called when the plugin resolves a vault path so the macOS app can find it.
 */
export async function writeDiscovery(wordsDirectory: string, wordsFolder: string): Promise<void> {
  const config: DiscoveryConfig = {
    version: 1,
    words_directory: wordsDirectory,
    words_folder: wordsFolder,
    updated_by: 'plugin',
    updated_at: new Date().toISOString(),
  };
  try {
    await fs.mkdir(DISCOVERY_DIR, { recursive: true });
    const tmp = path.join(DISCOVERY_DIR, `.discovery-${Date.now()}-${Math.random().toString(36).slice(2)}.json.tmp`);
    await fs.writeFile(tmp, JSON.stringify(config, null, 2), 'utf8');
    await fs.rename(tmp, DISCOVERY_PATH);
  } catch {
    // Best effort — don't fail the plugin if we can't write discovery
  }
}
