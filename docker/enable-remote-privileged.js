"use strict";

const fs = require("node:fs");
const path = require("node:path");

const roots = ["/usr/lib/node_modules", "/usr/local/lib/node_modules"];

function locate(relativeTarget) {
  const target = roots
    .map((root) => path.join(root, relativeTarget))
    .find((candidate) => fs.existsSync(candidate));
  if (target === undefined) {
    throw new Error(`package file not found at ${relativeTarget}`);
  }
  return target;
}

function replaceExactly(relativeTarget, oldText, newText, expected) {
  const target = locate(relativeTarget);
  const source = fs.readFileSync(target, "utf8");
  const occurrences = source.split(oldText).length - 1;
  if (occurrences !== expected) {
    throw new Error(`expected ${expected} matches in ${relativeTarget}, found ${occurrences}`);
  }
  fs.writeFileSync(target, source.split(oldText).join(newText));
  console.log(`patched ${target}`);
}

replaceExactly(
  path.join(
    "@deepseek-ai",
    "dsh",
    "node_modules",
    "@deepseek-ai",
    "dsh-client-connection",
    "lib",
    "index.js",
  ),
  'if (method !== void 0 && PRIVILEGED_METHODS.has(method) && !isTrustedApiRequest(request, [])) return new Response("forbidden", { status: 403 });',
  'if (method !== void 0 && PRIVILEGED_METHODS.has(method) && !isTrustedApiRequest(request, trustedHosts)) return new Response("forbidden", { status: 403 });',
  1,
);

replaceExactly(
  path.join(
    "@deepseek-ai",
    "dsh",
    "node_modules",
    "@deepseek-ai",
    "dsh-client-ui-settings",
    "lib",
    "client.js",
  ),
  'connection.isLoopback ? "host" : "memory"',
  '"host"',
  2,
);
