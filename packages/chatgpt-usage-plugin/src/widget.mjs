import { App, applyDocumentTheme, applyHostStyleVariables } from "@modelcontextprotocol/ext-apps";
import { OpenAIExtensions } from "@openai/mcp-extensions/app";
import { describeUsage, formatPercent, nextReset } from "./usage.mjs";

const app = new App({ name: "Usage Meter", version: "1.0.0" });
const extensions = new OpenAIExtensions(app);
const elements = Object.fromEntries(["refresh", "status", "updated", "error", "buckets", "pin", "pin-note"]
  .map(id => [id, document.getElementById(id)]));
let snapshot = null;
let lastError = null;
let contextError = null;
let connected = false;
let refreshing = false;
let pinned = false;
let contextBusy = false;
let contextQueued = false;
let contextTitle = "";
let lastResetRefresh = 0;
let stopped = false;
let pollTimer;
const now = () => Date.now() / 1000;
const dateTime = seconds => new Intl.DateTimeFormat(undefined, {
  month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short",
}).format(new Date(seconds * 1000));
const clockTime = seconds => new Intl.DateTimeFormat(undefined, {
  hour: "numeric", minute: "2-digit",
}).format(new Date(seconds * 1000));

function node(tag, className, text) {
  const result = document.createElement(tag);
  if (className) result.className = className;
  if (text !== undefined) result.textContent = text;
  return result;
}

function countdown(seconds) {
  if (seconds <= 0) return "Reset due";
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  if (minutes < 60) return `in ${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `in ${hours}h ${minutes % 60}m` : `in ${Math.floor(hours / 24)}d ${hours % 24}h`;
}

function stale() {
  return Boolean(lastError || !snapshot || now() - snapshot.fetchedAt > 120);
}

function renderWindow(label, window) {
  const card = node("section", "window");
  const top = node("div", "window-top");
  const percentage = node("div", window?.usedPercent == null ? "percent unknown" : "percent",
    formatPercent(window?.usedPercent ?? null));
  if (window?.usedPercent != null) percentage.append(node("span", "used", "used"));
  top.append(node("span", "window-title", label), percentage);
  card.append(top);
  if (window?.usedPercent != null) {
    const bar = node("div", "track");
    bar.dataset.high = String(window.usedPercent >= 85);
    bar.setAttribute("role", "progressbar");
    bar.setAttribute("aria-label", `${label.endsWith("usage") ? label : `${label} usage`}${stale() ? " (last reported)" : ""}`);
    bar.setAttribute("aria-valuemin", "0");
    bar.setAttribute("aria-valuemax", "100");
    bar.setAttribute("aria-valuenow", String(window.usedPercent));
    const fill = node("div");
    fill.style.width = `${window.usedPercent}%`;
    bar.append(fill);
    card.append(bar);
  }
  const detail = node("p", "window-detail");
  if (window?.usedPercent != null) detail.append(`${formatPercent(100 - window.usedPercent)} remaining`);
  if (window?.resetsAt) {
    if (detail.textContent) detail.append(node("br"));
    const due = window.resetsAt <= now();
    detail.append(node("span", due ? "due" : "", due
      ? "Reset due · awaiting an updated reading"
      : `Resets ${dateTime(window.resetsAt)} · ${countdown(window.resetsAt - now())}`));
  } else {
    if (detail.textContent) detail.append(node("br"));
    detail.append("Reset time not reported");
  }
  card.append(detail);
  return card;
}

function render() {
  const isStale = stale();
  elements.status.textContent = refreshing ? "Refreshing…" : !snapshot ? "Unavailable" : isStale ? "Out of date" : "Up to date";
  elements.status.dataset.state = snapshot && !isStale ? "fresh" : "stale";
  elements.updated.textContent = snapshot ? `As of ${clockTime(snapshot.fetchedAt)}` : "";
  elements.updated.title = snapshot ? dateTime(snapshot.fetchedAt) : "";
  elements.error.hidden = !lastError && !contextError;
  elements.error.textContent = lastError ?? contextError ?? "";
  elements.refresh.disabled = !connected || refreshing;
  elements.buckets.replaceChildren();
  if (snapshot?.buckets.length) {
    for (const bucket of snapshot.buckets) {
      const section = node("section", "bucket");
      if (snapshot.buckets.length > 1) section.append(node("h2", "bucket-name", bucket.name));
      if (bucket.fiveHour) section.append(renderWindow("5-hour limit", bucket.fiveHour));
      section.append(renderWindow("Weekly usage", bucket.weekly));
      const resetRow = node("div", "next-reset");
      const reset = nextReset(bucket);
      const due = [bucket.fiveHour, bucket.weekly].some(window => window?.resetsAt && window.resetsAt <= now());
      resetRow.append(node("strong", "", "Next reset"), node("span", due ? "due" : "",
        due ? "Reset due · refresh pending" : reset ? `${dateTime(reset)} · ${countdown(reset - now())}` : "Not reported"));
      section.append(resetRow);
      if (!bucket.fiveHour) section.append(node("p", "note", "A 5-hour window was not reported for this account."));
      elements.buckets.append(section);
    }
  } else {
    elements.buckets.append(node("p", "empty", snapshot
      ? "The account did not report usage windows. Refresh to check again."
      : "No current reading. Refresh to try again."));
  }
  elements.pin.disabled = !connected || !extensions.modelContext || (!snapshot && !pinned) || contextBusy;
  elements.pin.setAttribute("aria-pressed", String(pinned));
  elements.pin.textContent = pinned ? "Remove from conversation context" : "Show beside conversation context";
  if (connected && !extensions.modelContext) {
    elements["pin-note"].textContent = "This app version does not provide conversation context attachments.";
  } else {
    elements["pin-note"].textContent = pinned
      ? "The attached summary refreshes while this view is open. Its timestamp remains visible when closed."
      : "The summary includes its last update time.";
  }
}

function usageTitle() {
  const bucket = snapshot?.buckets[0];
  const parts = [stale() ? "Usage (out of date)" : "Usage"];
  if (bucket?.fiveHour) parts.push(`5h ${formatPercent(bucket.fiveHour.usedPercent)}`);
  parts.push(`Week ${formatPercent(bucket?.weekly?.usedPercent ?? null)}`);
  const reset = nextReset(bucket);
  const due = [bucket?.fiveHour, bucket?.weekly].some(window => window?.resetsAt && window.resetsAt <= now());
  if (due) parts.push("Reset due");
  else if (reset) parts.push(`Reset ${dateTime(reset)}`);
  if (snapshot) parts.push(`as of ${dateTime(snapshot.fetchedAt)}`);
  return parts.join(" · ");
}

async function syncContext(force = false) {
  if (!pinned || !extensions.modelContext || !snapshot) return;
  if (contextBusy) { contextQueued = true; return; }
  const title = usageTitle();
  if (!force && contextTitle === title) return;
  contextBusy = true;
  try {
    await extensions.modelContext.update({
      content: [{
        type: "text",
        text: `${stale() ? "This reading is out of date. " : ""}Usage snapshot as of ${dateTime(snapshot.fetchedAt)}.\n${describeUsage(snapshot)}`,
        _meta: { "openai/title": title, "openai/group": { title: "Account usage" } },
      }],
      structuredContent: { usageMeter: true, fetchedAt: snapshot.fetchedAt },
    });
    contextTitle = title;
    contextError = null;
  } catch {
    pinned = false;
    contextError = "The usage summary could not attach to this conversation. Try the context button again.";
  } finally {
    contextBusy = false;
    render();
    if (contextQueued) { contextQueued = false; void syncContext(); }
  }
}

function receive(result) {
  const value = result?.structuredContent;
  if (result?.isError || value?.error) {
    lastError = typeof value?.error?.message === "string" ? value.error.message : "Usage is unavailable. Refresh to try again.";
  } else if (value && Number.isFinite(value.fetchedAt) && Array.isArray(value.buckets)) {
    // Tool results are the only source of usage values; missing values stay unavailable.
    snapshot = value;
    lastError = null;
  } else lastError = "The account returned an unexpected response. Refresh to try again.";
  render();
  void syncContext();
}

async function refresh(force = false) {
  if (!connected || refreshing || stopped) return;
  refreshing = true;
  render();
  try { receive(await app.callServerTool({ name: "usage.read", arguments: { refresh: force } })); }
  catch { lastError = "Usage refresh failed. Check your connection and try again."; }
  finally { refreshing = false; render(); void syncContext(); }
}

function applyContext(context) {
  if (context?.theme) applyDocumentTheme(context.theme);
  if (context?.styles?.variables) applyHostStyleVariables(context.styles.variables);
}

elements.refresh.onclick = () => { void refresh(true); };
elements.pin.onclick = async () => {
  if (!extensions.modelContext) return;
  if (!pinned) { pinned = true; await syncContext(true); render(); return; }
  contextBusy = true;
  render();
  try {
    await extensions.modelContext.update({ content: [], structuredContent: {} });
    pinned = false;
    contextTitle = "";
    contextError = null;
  } catch { contextError = "The context summary could not be removed. Try again."; }
  finally { contextBusy = false; render(); }
};
app.ontoolresult = receive;
app.onhostcontextchanged = context => {
  applyContext(context);
  if (Object.hasOwn(context, "openai/modelContext") && context["openai/modelContext"] === null) {
    pinned = false;
    contextTitle = "";
    render();
  }
};
function stop() { stopped = true; clearInterval(pollTimer); clearInterval(tickTimer); }
app.onteardown = async () => { stop(); return {}; };
window.addEventListener("pagehide", stop, { once: true });
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && stale()) void refresh(true);
});
const tickTimer = setInterval(() => {
  if (!snapshot || stopped) return;
  render();
  void syncContext();
  const resetDue = snapshot.buckets.some(bucket => [bucket.fiveHour, bucket.weekly]
    .some(window => window?.resetsAt && window.resetsAt <= now()));
  if (resetDue && now() - lastResetRefresh >= 60) {
    lastResetRefresh = now();
    void refresh(true);
  }
}, 15000);

try {
  await app.connect();
  connected = true;
  applyContext(app.getHostContext());
  pinned = extensions.modelContext?.getCurrent()?.structuredContent?.usageMeter === true;
  render();
  if (!snapshot && !lastError) await refresh();
  else if (pinned) void syncContext(true);
  pollTimer = setInterval(() => { void refresh(); }, 60000);
} catch {
  lastError = "Open Usage Meter from ChatGPT's sidebar or a conversation panel to connect.";
  render();
}
