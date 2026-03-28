/**
 * Type shims for the OpenClaw SDK.
 * Replace with actual @openclaw/sdk package imports when available on ClawHub.
 */

export interface Logger {
  info: (msg: string) => void;
  warn: (msg: string) => void;
  error: (msg: string) => void;
}

export interface ChannelAPI {
  sendToPrimary: (msg: string) => void;
  labelFor: (channelId: string) => string | undefined;
  onFirstInteraction: (cb: (channelId: string) => void) => void;
}

export interface PluginContext {
  /** Absolute path to the vault root (from plugin config or auto-detected). */
  vaultRoot: string;
  logger: Logger;
  channel: ChannelAPI;
  registerTool: (name: string, handler: (params: unknown) => Promise<unknown>) => void;
  registerCron: (schedule: string, handler: () => Promise<void>) => void;
  registerHook: (event: string, handler: (data: unknown) => Promise<void>) => void;
  onUnload: (fn: () => void) => void;
}
