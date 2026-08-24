interface ImageLoaderParams {
  src: string;
  width: number;
  quality?: number;
}

// Custom Next.js image loader (wired up in next.config.ts as loader: "custom").
// EVERY <Image> in the dashboard passes through here.
//
// Upstream hardcoded `const CDN_URL = "https://midday.ai"` and rewrote every
// image URL to https://midday.ai/cdn-cgi/image/... — Midday's Cloudflare image
// proxy — unconditionally, including in local development. That routed avatars,
// uploaded document previews and file-proxy URLs through Midday's servers.
//
// Now: set NEXT_PUBLIC_CDN_URL to use your own Cloudflare-image-style proxy.
// Leave it unset (the default) and images are served directly from their origin
// with no proxy in the middle.
const CDN_URL = process.env.NEXT_PUBLIC_CDN_URL?.replace(/\/$/, "");

function isLocal(src: string): boolean {
  return src.includes("localhost") || src.includes("127.0.0.1");
}

export default function imageLoader({
  src,
  width,
  quality = 80,
}: ImageLoaderParams): string {
  // No proxy configured — serve the image from wherever it actually lives.
  if (!CDN_URL) {
    return src;
  }

  // Handle authenticated API URLs (preserve query parameters like fk token)
  if (src.includes("/files/proxy")) {
    try {
      const url = new URL(src);

      // Skip CDN optimization for localhost (local development)
      if (url.hostname === "localhost" || url.hostname === "127.0.0.1") {
        return src;
      }

      const params = url.searchParams.toString();
      const baseUrl = url.origin + url.pathname;
      return `${CDN_URL}/cdn-cgi/image/width=${width},quality=${quality}/${baseUrl}${params ? `?${params}` : ""}`;
    } catch {
      if (isLocal(src)) {
        return src;
      }
      return `${CDN_URL}/cdn-cgi/image/width=${width},quality=${quality}/${src}`;
    }
  }

  if (isLocal(src)) {
    return src;
  }

  if (src.startsWith("/_next")) {
    const origin = process.env.NEXT_PUBLIC_URL || "";
    return `${CDN_URL}/cdn-cgi/image/width=${width},quality=${quality}/${origin}${src}`;
  }

  return `${CDN_URL}/cdn-cgi/image/width=${width},quality=${quality}/${src}`;
}
