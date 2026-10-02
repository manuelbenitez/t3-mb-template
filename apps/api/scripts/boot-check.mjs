#!/usr/bin/env node
// boot-check: start the BUILT API (dist/main.js) and wait for Nest to report a
// successful boot. Typecheck, build and tests each resolve modules their own
// way; none of them proves the compiled app loads its dependency graph and
// starts. This does. Run after `pnpm --filter @acme/api build`.
//
// MongoDB: MONGODB_URI when set, else an in-memory server for the run.
// JWT_SECRET: the environment's when set, else a random one for the run.
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const API_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ENTRY = join(API_ROOT, "dist", "main.js");
// Nest's own line once every module resolved and the HTTP server is up.
const SUCCESS = /Nest application successfully started/;
const FATAL =
  /ERR_MODULE_NOT_FOUND|Cannot find module|ERR_REQUIRE_ESM|ERR_REQUIRE_ASYNC_MODULE|SyntaxError|Nest can't resolve dependencies|Invalid environment/;
const TIMEOUT_MS = Number(process.env.BOOT_CHECK_TIMEOUT_MS ?? 60_000);

if (!existsSync(ENTRY)) {
  console.error(
    `boot-check: FAIL, ${ENTRY} does not exist. Build first: pnpm --filter @acme/api build`,
  );
  process.exit(1);
}

let mongo = null;
let uri = process.env.MONGODB_URI;
if (!uri) {
  const { MongoMemoryServer } = await import("mongodb-memory-server");
  mongo = await MongoMemoryServer.create();
  uri = mongo.getUri();
}

const child = spawn(process.execPath, [ENTRY], {
  cwd: API_ROOT,
  env: {
    ...process.env,
    MONGODB_URI: uri,
    JWT_SECRET: process.env.JWT_SECRET ?? randomBytes(32).toString("base64"),
    // Port 0: any free port, so a running dev API is never in the way.
    PORT: "0",
    NODE_ENV: process.env.NODE_ENV ?? "development",
  },
  stdio: ["ignore", "pipe", "pipe"],
});

let output = "";
let settled = false;
const finish = async (code, message) => {
  if (settled) return;
  settled = true;
  clearTimeout(timer);
  child.kill("SIGTERM");
  setTimeout(() => child.kill("SIGKILL"), 3000).unref();
  if (mongo) await mongo.stop();
  if (message) console.error(message);
  process.exit(code);
};
const onData = (chunk) => {
  output += chunk.toString();
  if (SUCCESS.test(output)) void finish(0, "boot-check: OK, the API started.");
  else if (FATAL.test(output))
    void finish(1, `boot-check: FAIL\n${output.slice(-4000)}`);
};
child.stdout.on("data", onData);
child.stderr.on("data", onData);
child.on("exit", (code) => {
  void finish(
    1,
    `boot-check: FAIL, the API exited (code ${code}) before starting.\n${output.slice(-4000)}`,
  );
});
const timer = setTimeout(() => {
  void finish(
    1,
    `boot-check: FAIL, no successful boot within ${TIMEOUT_MS} ms.\n${output.slice(-4000)}`,
  );
}, TIMEOUT_MS);
