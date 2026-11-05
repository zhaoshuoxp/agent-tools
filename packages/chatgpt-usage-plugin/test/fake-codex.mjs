#!/usr/bin/env node
import { createInterface } from "node:readline";
import { readFileSync } from "node:fs";

const mode = process.argv[2];
const lines = createInterface({ input: process.stdin });
let initialized = false;
const reply = message => process.stdout.write(`${JSON.stringify(message)}\n`);
lines.on("line", line => {
  const message = JSON.parse(line);
  if (mode === "timeout") return;
  if (mode === "exit") { process.exit(1); return; }
  if (message.method === "initialize") {
    if (message.params.clientInfo.name !== "chatgpt_usage_meter") process.exit(2);
    reply({ id: message.id, result: { userAgent: "test" } });
  } else if (message.method === "initialized") initialized = true;
  else if (message.method === "account/rateLimits/read" && initialized) {
    const state = process.env.USAGE_FIXTURE_STATE_FILE
      ? JSON.parse(readFileSync(process.env.USAGE_FIXTURE_STATE_FILE, "utf8")) : {};
    reply(mode === "error" || state.error
      ? { id: message.id, error: { code: -32000, message: "Private diagnostic: SECRET_SENTINEL" } }
      : { id: message.id, result: { rateLimits: {
        limitId: "codex", primary: {
          usedPercent: state.usedPercent ?? 23, windowDurationMins: 10080,
          resetsAt: state.resetsAt ?? 1794094781,
        },
      } } });
  } else process.exit(3);
});
