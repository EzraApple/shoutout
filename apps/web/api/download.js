import { randomUUID } from "node:crypto";

const DOWNLOAD_COOKIE = "shoutout_download_id";
const DEFAULT_RELEASE_VERSION = "0.1.7";
const DEFAULT_POSTHOG_HOST = "https://us.i.posthog.com";

const parseCookies = (cookieHeader = "") =>
  Object.fromEntries(
    cookieHeader
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const separatorIndex = part.indexOf("=");
        if (separatorIndex === -1) {
          return [part, ""];
        }

        return [part.slice(0, separatorIndex), decodeURIComponent(part.slice(separatorIndex + 1))];
      }),
  );

const sanitizeSource = (source) => {
  if (typeof source !== "string" || !/^[a-z0-9_-]{1,64}$/i.test(source)) {
    return "unknown";
  }

  return source;
};

const sanitizeDistinctId = (distinctId) => {
  if (typeof distinctId !== "string" || !/^[a-z0-9._:$-]{8,200}$/i.test(distinctId)) {
    return "";
  }

  return distinctId;
};

const normalizedPostHogHost = () => {
  const rawHost = process.env.POSTHOG_HOST || process.env.VITE_POSTHOG_HOST || DEFAULT_POSTHOG_HOST;

  return rawHost
    .trim()
    .replace(/\/+$/, "")
    .replace("https://us.posthog.com", "https://us.i.posthog.com")
    .replace("https://eu.posthog.com", "https://eu.i.posthog.com");
};

const setDownloadCookie = (req, res, distinctId) => {
  const cookieParts = [
    `${DOWNLOAD_COOKIE}=${encodeURIComponent(distinctId)}`,
    "Path=/",
    "Max-Age=31536000",
    "SameSite=Lax",
    "HttpOnly",
  ];

  if (process.env.VERCEL === "1" || req.headers["x-forwarded-proto"] === "https") {
    cookieParts.push("Secure");
  }

  res.setHeader("Set-Cookie", cookieParts.join("; "));
};

const getDistinctId = (req, res, url) => {
  const posthogDistinctId = sanitizeDistinctId(url.searchParams.get("ph_distinct_id"));

  if (posthogDistinctId) {
    setDownloadCookie(req, res, posthogDistinctId);
    return { distinctId: posthogDistinctId, source: "posthog" };
  }

  const cookies = parseCookies(req.headers.cookie);
  const existingId = sanitizeDistinctId(cookies[DOWNLOAD_COOKIE]);

  if (existingId) {
    return { distinctId: existingId, source: "download_cookie" };
  }

  const distinctId = randomUUID();
  setDownloadCookie(req, res, distinctId);
  return { distinctId, source: "generated" };
};

const captureDownloadStarted = async ({ distinctId, distinctIdSource, releaseLocation, req, source, url, version }) => {
  const projectKey = process.env.POSTHOG_PROJECT_API_KEY || process.env.VITE_POSTHOG_KEY;

  if (!projectKey) {
    return;
  }

  const analyticsUrl = new URL(url.href);
  analyticsUrl.searchParams.delete("ph_distinct_id");

  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), 1_200);

  try {
    const payload = {
      api_key: projectKey,
      event: "download started",
      distinct_id: distinctId,
      properties: {
        analytics_surface: "website",
        app: "shoutout",
        product_area: "website",
        event_source: "download_redirect",
        download_id: randomUUID(),
        distinct_id_source: distinctIdSource,
        source,
        release_version: version,
        platform: "macos",
        release_location: releaseLocation,
        release_location_type: /^https?:\/\//i.test(releaseLocation) ? "external" : "site",
        referrer: req.headers.referer || "",
        user_agent: req.headers["user-agent"] || "",
        $current_url: analyticsUrl.href,
        $host: url.host,
      },
    };

    await fetch(`${normalizedPostHogHost()}/i/v0/e/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: abortController.signal,
    });
  } catch {
    // Analytics should never block the download.
  } finally {
    clearTimeout(timeout);
  }
};

export default async function handler(req, res) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET, HEAD");
    res.end("Method Not Allowed");
    return;
  }

  const host = req.headers.host || "shoutout.sh";
  const url = new URL(req.url || "/download", `https://${host}`);
  const version = process.env.SHOUTOUT_RELEASE_VERSION || DEFAULT_RELEASE_VERSION;
  const releaseLocation = process.env.SHOUTOUT_DMG_URL || `/releases/ShoutOut-${version}.dmg`;

  if (req.method === "GET") {
    const { distinctId, source: distinctIdSource } = getDistinctId(req, res, url);

    await captureDownloadStarted({
      distinctId,
      distinctIdSource,
      releaseLocation,
      req,
      source: sanitizeSource(url.searchParams.get("source")),
      url,
      version,
    });
  }

  res.statusCode = 302;
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Location", releaseLocation);
  res.end();
}
