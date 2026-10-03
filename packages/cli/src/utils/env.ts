export function isTTY(): boolean {
  return Boolean(process.stdout.isTTY);
}

export function isCI(): boolean {
  return Boolean(
    process.env.CI || process.env.GITHUB_ACTIONS || process.env.GITLAB_CI,
  );
}

export function hasNoColor(): boolean {
  return Boolean(process.env.NO_COLOR);
}

export function isAgentMode(flags: {
  json?: boolean;
  agent?: boolean;
  quiet?: boolean;
}): boolean {
  if (flags.agent || flags.json) return true;
  if (!isTTY()) return true;
  return false;
}

export function shouldShowUI(flags: {
  json?: boolean;
  agent?: boolean;
  quiet?: boolean;
}): boolean {
  if (flags.quiet || flags.agent || flags.json) return false;
  if (!isTTY()) return false;
  if (isCI()) return false;
  return true;
}

export function getApiUrl(): string {
  // Was hardcoded to https://api.midday.ai, so an unconfigured CLI would
  // authenticate against Midday's hosted API. Points at a local instance now —
  // set MIDDAY_API_URL to target your own deployment.
  return process.env.MIDDAY_API_URL || "http://localhost:3002";
}

export function getDashboardUrl(): string {
  if (process.env.MIDDAY_DASHBOARD_URL) {
    return process.env.MIDDAY_DASHBOARD_URL;
  }
  const apiUrl = getApiUrl();
  if (apiUrl.includes("localhost") || apiUrl.includes("127.0.0.1")) {
    return "http://localhost:3000";
  }
  return apiUrl.replace("api.", "app.");
}
