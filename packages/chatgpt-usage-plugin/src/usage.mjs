const WINDOW_MINUTES = { fiveHour: 300, weekly: 10080 };

function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function normalizeWindow(value) {
  if (!value || typeof value !== "object") return null;
  const duration = finiteNumber(value.windowDurationMins);
  if (duration === null || duration <= 0) return null;
  const percent = finiteNumber(value.usedPercent);
  const reset = finiteNumber(value.resetsAt);
  return {
    windowDurationMins: duration,
    usedPercent: percent === null ? null : Math.max(0, Math.min(100, percent)),
    resetsAt: reset !== null && reset > 0 && reset < 8640000000000 ? reset : null,
  };
}

export function normalizeUsage(raw, fetchedAt = Date.now() / 1000) {
  if (!raw || typeof raw !== "object") throw new Error("Invalid usage response.");
  const mapped = raw.rateLimitsByLimitId;
  let entries = mapped && typeof mapped === "object" && !Array.isArray(mapped)
    ? Object.entries(mapped).filter(([, bucket]) => bucket && typeof bucket === "object")
    : [];
  if (entries.length === 0 && raw.rateLimits && typeof raw.rateLimits === "object") {
    entries = [[raw.rateLimits.limitId || "default", raw.rateLimits]];
  }
  const buckets = entries.map(([id, bucket]) => {
    const windows = [bucket.primary, bucket.secondary].map(normalizeWindow).filter(Boolean);
    return {
      id,
      name: typeof bucket.limitName === "string" && bucket.limitName.trim()
        ? bucket.limitName.trim() : id === "codex" ? "Work / Codex" : id,
      planType: typeof bucket.planType === "string" ? bucket.planType : null,
      fiveHour: windows.find(window => window.windowDurationMins === WINDOW_MINUTES.fiveHour) ?? null,
      weekly: windows.find(window => window.windowDurationMins === WINDOW_MINUTES.weekly) ?? null,
    };
  });
  buckets.sort((a, b) => Number(b.id === "codex") - Number(a.id === "codex"));
  return { fetchedAt, source: "Local ChatGPT Work / Codex account", buckets };
}

export function formatPercent(percent) {
  return percent === null ? "Not reported" : `${Math.round(percent * 10) / 10}%`;
}

export function nextReset(bucket, now = Date.now() / 1000) {
  const resets = [bucket?.fiveHour, bucket?.weekly]
    .map(window => window?.resetsAt).filter(value => typeof value === "number" && value > now);
  return resets.length ? Math.min(...resets) : null;
}

export function describeUsage(snapshot) {
  if (!snapshot.buckets.length) return "Usage limits are not reported by the local account.";
  return snapshot.buckets.map(bucket => {
    const parts = [bucket.name];
    for (const [key, label] of [["fiveHour", "5-hour"], ["weekly", "Weekly"]]) {
      const window = bucket[key];
      if (!window) {
        if (key === "weekly") parts.push("Weekly usage not reported");
        continue;
      }
      parts.push(`${label}: ${formatPercent(window.usedPercent)} used${window.resetsAt
        ? `, resets ${new Date(window.resetsAt * 1000).toISOString()}` : ", reset not reported"}`);
    }
    return parts.join(". ");
  }).join("\n");
}
