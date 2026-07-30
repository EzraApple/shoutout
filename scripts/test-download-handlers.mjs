import assert from "node:assert/strict";
import { createRequire } from "node:module";

import webHandler from "../apps/web/api/download.js";

const require = createRequire(import.meta.url);
const productionHandler = require("../api/download.js");

const DEFAULT_RELEASE_LOCATION =
  "https://xhahmepifrbmvgrg.public.blob.vercel-storage.com/releases/ShoutOut-0.1.11.dmg";
const ENV_KEYS = [
  "POSTHOG_PROJECT_API_KEY",
  "SHOUTOUT_DMG_URL",
  "SHOUTOUT_RELEASE_VERSION",
  "VITE_POSTHOG_KEY",
];

const invoke = async (handler, { method = "HEAD", url = "/download?source=test" } = {}) => {
  const savedEnvironment = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) {
    delete process.env[key];
  }

  const headers = new Map();
  const response = {
    body: "",
    statusCode: 200,
    setHeader(name, value) {
      headers.set(name.toLowerCase(), value);
    },
    end(body = "") {
      this.body = body;
    },
  };

  try {
    await handler({ headers: {}, method, url }, response);
  } finally {
    for (const key of ENV_KEYS) {
      const value = savedEnvironment[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }

  return { ...response, headers };
};

for (const [name, handler] of [
  ["production", productionHandler],
  ["web-root", webHandler],
]) {
  const headResponse = await invoke(handler);
  assert.equal(headResponse.statusCode, 302, `${name} HEAD status`);
  assert.equal(headResponse.headers.get("cache-control"), "no-store", `${name} cache policy`);
  assert.equal(
    headResponse.headers.get("location"),
    DEFAULT_RELEASE_LOCATION,
    `${name} default hosted release`,
  );

  const getResponse = await invoke(handler, { method: "GET" });
  assert.equal(getResponse.statusCode, 302, `${name} GET status`);
  assert.equal(getResponse.headers.get("location"), DEFAULT_RELEASE_LOCATION, `${name} GET release`);
  assert.match(getResponse.headers.get("set-cookie"), /^shoutout_download_id=/, `${name} cookie`);

  const rejectedResponse = await invoke(handler, { method: "POST" });
  assert.equal(rejectedResponse.statusCode, 405, `${name} rejects POST`);
  assert.equal(rejectedResponse.headers.get("allow"), "GET, HEAD", `${name} allowed methods`);
}

console.log("ok - both download handlers redirect to the hosted release");
