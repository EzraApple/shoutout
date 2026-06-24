const { randomUUID } = require("node:crypto");

const DOWNLOAD_COOKIE = "shoutout_download_id";
const DEFAULT_RELEASE_VERSION = "0.1.5";
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

const normalizedPostHogHost = () => {
  const rawHost = process.env.POSTHOG_HOST || process.env.VITE_POSTHOG_HOST || DEFAULT_POSTHOG_HOST;

  return rawHost
    .trim()
    .replace(/\/+$/, "")
    .replace("https://us.posthog.com", "https://us.i.posthog.com")
    .replace("https://eu.posthog.com", "https://eu.i.posthog.com");
};

const getDistinctId = (req, res) => {
  const cookies = parseCookies(req.headers.cookie);
  const existingId = cookies[DOWNLOAD_COOKIE];

  if (existingId && /^[a-z0-9-]{12,80}$/i.test(existingId)) {
    return existingId;
  }

  const distinctId = randomUUID();
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
  return distinctId;
};

const captureDownloadStarted = async ({ distinctId, req, source, url, version }) => {
  const projectKey = process.env.POSTHOG_PROJECT_API_KEY || process.env.VITE_POSTHOG_KEY;

  if (!projectKey) {
    return;
  }

  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), 1_200);

  try {
    const payload = {
      api_key: projectKey,
      event: "download started",
      distinct_id: distinctId,
      properties: {
        source,
        release_version: version,
        platform: "macos",
        referrer: req.headers.referer || "",
        user_agent: req.headers["user-agent"] || "",
        $current_url: url.href,
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

module.exports = async function handler(req, res) {
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
    await captureDownloadStarted({
      distinctId: getDistinctId(req, res),
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
};
