import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { createInterface } from "node:readline";
import { normalizeUsage } from "./usage.mjs";

const APP_CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex";
const FALLBACK_CODEX = "/Applications/Codex.app/Contents/Resources/codex";

export class UsageError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

async function findCodex() {
  const configured = process.env.USAGE_CODEX_BIN;
  if (configured) return configured;
  for (const candidate of [APP_CODEX, FALLBACK_CODEX]) {
    try {
      await access(candidate, constants.X_OK);
      return candidate;
    } catch { /* Try the next installed location. */ }
  }
  return "codex";
}

export async function readAccountLimits({ executable, timeoutMs = 25000, spawnProcess = spawn } = {}) {
  const command = executable ?? await findCodex();
  return new Promise((resolve, reject) => {
    const child = spawnProcess(command, ["app-server", "--listen", "stdio://"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
      windowsHide: true,
    });
    const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
    let finished = false;
    let initialized = false;
    const timer = setTimeout(() => finish(new UsageError(
      "TIMEOUT", "Usage refresh timed out. Check your connection and try again.",
    )), timeoutMs);
    timer.unref();

    function finish(error, value) {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      lines.close();
      child.stdin.end();
      if (child.exitCode === null) {
        child.kill("SIGTERM");
        const killTimer = setTimeout(() => {
          if (child.exitCode === null) child.kill("SIGKILL");
        }, 2000);
        killTimer.unref();
        child.once("exit", () => clearTimeout(killTimer));
      }
      if (error) reject(error); else resolve(value);
    }

    function send(message) {
      if (!finished) child.stdin.write(`${JSON.stringify(message)}\n`);
    }

    // Drain diagnostics without retaining credentials, profile details, or raw errors.
    child.stderr.resume();
    child.stdin.on("error", () => finish(new UsageError(
      "CLIENT_UNAVAILABLE", "The local ChatGPT account service is unavailable. Reopen ChatGPT and try again.",
    )));
    child.on("error", error => finish(new UsageError(
      error.code === "ENOENT" ? "CLI_MISSING" : "CLIENT_UNAVAILABLE",
      error.code === "ENOENT"
        ? "The bundled Codex CLI was not found. Set USAGE_CODEX_BIN to its executable path."
        : "The local account service could not start. Reopen ChatGPT and try again.",
    )));
    child.on("exit", () => finish(new UsageError(
      "CLIENT_UNAVAILABLE", "The local account service stopped. Reopen ChatGPT and try again.",
    )));
    lines.on("line", line => {
      if (finished || line.length > 1048576) return;
      let message;
      try { message = JSON.parse(line); } catch { return; }
      if (message.id === 1 && !initialized) {
        if (message.error || !message.result) {
          finish(new UsageError("INITIALIZATION_FAILED", "The account service could not initialize."));
          return;
        }
        initialized = true;
        send({ method: "initialized" });
        send({ id: 2, method: "account/rateLimits/read" });
      } else if (message.id === 2 && initialized) {
        if (message.error || !message.result) {
          finish(new UsageError(
            "USAGE_UNAVAILABLE",
            "Usage is unavailable. Sign in to ChatGPT Work / Codex with your ChatGPT account, then refresh.",
          ));
        } else finish(null, message.result);
      } else if (message.id !== undefined && message.method) {
        // This reader never executes tools or responds to authentication challenges.
        send({ id: message.id, error: { code: -32601, message: "Unsupported by the usage reader" } });
      }
    });
    send({
      id: 1,
      method: "initialize",
      params: { clientInfo: { name: "chatgpt_usage_meter", title: "Usage Meter", version: "1.0.0" } },
    });
  });
}

export class UsageReader {
  constructor({ read = readAccountLimits, now = () => Date.now() / 1000, ttlSeconds = 45 } = {}) {
    this.read = read;
    this.now = now;
    this.ttlSeconds = ttlSeconds;
    this.cached = null;
    this.inFlight = null;
  }

  async get(refresh = false) {
    if (this.inFlight) return this.inFlight;
    if (!refresh && this.cached && this.now() - this.cached.fetchedAt < this.ttlSeconds) return this.cached;
    this.inFlight = this.read().then(raw => {
      this.cached = normalizeUsage(raw, this.now());
      return this.cached;
    }).catch(error => {
      this.cached = null;
      throw error;
    }).finally(() => { this.inFlight = null; });
    return this.inFlight;
  }
}
