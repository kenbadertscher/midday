// URL resolution for self-hosting.
//
// Upstream defaulted these to Midday's production hosts (app.midday.ai,
// api.midday.ai, cdn.midday.ai, midday.ai) whenever NODE_ENV was "production"
// and no override was set — so a misconfigured self-hosted deploy would quietly
// point at Midday's infrastructure. Every fallback now resolves locally.
//
// Set DASHBOARD_URL, API_URL, EMAIL_URL and CDN_URL for a real deployment.

const LOCAL_DASHBOARD_URL = "http://localhost:3001";
const LOCAL_API_URL = "http://localhost:3002";
const LOCAL_WEBSITE_URL = "http://localhost:3000";

function warnMissing(name: string, fallback: string) {
  if (process.env.NODE_ENV === "production") {
    console.warn(
      `[midday] ${name} is not set in a production build — falling back to ${fallback}. ` +
        "Set it explicitly; this no longer defaults to Midday-operated hosts.",
    );
  }
}

export function getAppUrl() {
  if (process.env.DASHBOARD_URL) {
    return process.env.DASHBOARD_URL;
  }

  // Railway (or any platform) exposing its own public domain
  if (process.env.RAILWAY_PUBLIC_DOMAIN) {
    return `https://${process.env.RAILWAY_PUBLIC_DOMAIN}`;
  }

  warnMissing("DASHBOARD_URL", LOCAL_DASHBOARD_URL);
  return LOCAL_DASHBOARD_URL;
}

export function getEmailUrl() {
  if (process.env.EMAIL_URL) {
    return process.env.EMAIL_URL;
  }

  warnMissing("EMAIL_URL", LOCAL_WEBSITE_URL);
  return LOCAL_WEBSITE_URL;
}

export function getCdnUrl() {
  if (process.env.CDN_URL) {
    return process.env.CDN_URL;
  }

  warnMissing("CDN_URL", LOCAL_WEBSITE_URL);
  return LOCAL_WEBSITE_URL;
}

export function getApiUrl() {
  if (process.env.API_URL) {
    return process.env.API_URL;
  }

  warnMissing("API_URL", LOCAL_API_URL);
  return LOCAL_API_URL;
}
