// Bank institution logos.
//
// Upstream hardcoded https://cdn-engine.midday.ai/ here, which meant every
// dashboard render sent the viewer's IP plus the institution IDs of their
// connected banks to Midday's CDN.
//
// The prefix is now env-driven. Leave BANK_LOGO_CDN_URL unset and logos resolve
// to a local path served from the dashboard's own public/ directory — nothing
// leaves the machine. Missing files 404 and BankLogo falls back to initials.
//
// To self-host the logos, point BANK_LOGO_CDN_URL at your own R2/S3 bucket and
// run syncInstitutionLogos() (see ../sync-logos.ts), which downloads them from
// the banking providers and uploads them to that bucket.

export const LOGO_CDN_PREFIX = process.env.BANK_LOGO_CDN_URL
  ? `${process.env.BANK_LOGO_CDN_URL.replace(/\/$/, "")}/`
  : "/bank-logos/";

export function getLogoURL(id: string, ext?: string) {
  return `${LOGO_CDN_PREFIX}${id}.${ext || "jpg"}`;
}

export function getFileExtension(url: string) {
  return url.split(".").at(-1);
}
