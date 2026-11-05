import { formatPercent } from "./usage.mjs";

function xml(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;",
  })[character]);
}

function resetTime(seconds) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short",
  }).format(new Date(seconds * 1000));
}

function readingTime(seconds) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short",
  }).format(new Date(seconds * 1000));
}

function shortResetDate(seconds) {
  if (!seconds) return "--";
  const date = new Date(seconds * 1000);
  return `${date.getMonth() + 1}.${date.getDate()}`;
}

function ring(window, key, radius, width = 8, trackWidth = 4) {
  const known = window?.usedPercent != null;
  const angle = 35 * Math.PI / 180;
  const dx = (radius * Math.cos(angle)).toFixed(3);
  const y = (30.5 + radius * Math.sin(angle)).toFixed(3);
  const path = `M ${(32 - Number(dx)).toFixed(3)} ${y} A ${radius} ${radius} 0 1 1 ${(32 + Number(dx)).toFixed(3)} ${y}`;
  const outline = `<path d="${path}" fill="none" stroke="#fff" stroke-width="${trackWidth + 2}" stroke-linecap="round"/>`;
  const track = `${outline}<path d="${path}" fill="none" stroke="#000" stroke-width="${trackWidth}" stroke-linecap="round"${known ? "" : ' pathLength="100" stroke-dasharray="3 5"'}/>`;
  if (!known) return track;
  const progress = window.usedPercent === 0 ? "" : `<path d="${path}" fill="none" stroke="#fff" stroke-width="${width + 2}" pathLength="100" stroke-dasharray="${window.usedPercent} ${100 - window.usedPercent}" stroke-linecap="round"/>`;
  return `${track}${progress}<path data-window="${key}" d="${path}" fill="none" stroke="#000" stroke-width="${width}" pathLength="100" stroke-dasharray="${window.usedPercent} ${100 - window.usedPercent}" stroke-linecap="${window.usedPercent === 0 ? "butt" : "round"}"/>`;
}

export function createIndicator(snapshot, { now = Date.now() / 1000, error = false } = {}) {
  const bucket = snapshot?.buckets.find(value => value.id === "codex") ?? snapshot?.buckets[0];
  const main = bucket?.weekly ?? bucket?.fiveHour ?? null;
  const mainKey = bucket?.weekly ? "weekly" : "five-hour";
  const stale = Boolean(error || snapshot && now - snapshot.fetchedAt > 120);
  const title = [stale ? "Usage Meter (out of date)" : "Usage Meter"];
  for (const [key, label] of [["fiveHour", "5h"], ["weekly", "Week"]]) {
    const window = bucket?.[key];
    if (!window) continue;
    const due = window.resetsAt != null && window.resetsAt <= now;
    title.push(`${label}: ${formatPercent(window.usedPercent)} used; ${window.resetsAt
      ? `${due ? "reset due" : "resets"} ${resetTime(window.resetsAt)}` : "reset not reported"}`);
  }
  if (!main) title.push("Quota not reported");
  if (snapshot) title.push(`As of ${readingTime(snapshot.fetchedAt)}`);
  const tooltip = title.join("\n");
  const hasInner = Boolean(bucket?.weekly && bucket?.fiveHour);
  const center = main?.usedPercent == null ? "?" : String(Math.round(main.usedPercent));
  const fontSize = hasInner ? center.length > 2 ? 18 : 26 : center.length > 2 ? 23 : 29;
  const date = shortResetDate(main?.resetsAt);
  // Black geometry survives the host's inverted luminance mask at full strength.
  // White keylines keep the same asset legible when a host shows original colors.
  const text = (label, x, y, size, extra = "") => `<text ${extra} x="${x}" y="${y}" font-size="${size}">${xml(label)}</text>`;
  const centerText = text(center, 32, 30, fontSize, 'dominant-baseline="middle"');
  const dateText = text(date, 32, 63, 19.5, 'data-label="reset-date"');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-label="${xml(tooltip)}"><title>${xml(tooltip)}</title>${ring(main, mainKey, 25.5)}${hasInner ? ring(bucket.fiveHour, "five-hour", 19, 5.5, 2.5) : ""}<g fill="#000" stroke-linejoin="round" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-weight="900" text-anchor="middle"><g stroke="#fff" stroke-width="2.4" paint-order="stroke fill">${centerText}${dateText}</g><g stroke="#000" stroke-width=".55">${centerText}${dateText}</g></g>${stale ? '<circle cx="59" cy="6" r="4" fill="#000" stroke="#fff" stroke-width="1.5"/>' : ""}</svg>`;
  return {
    title: tooltip,
    svg,
    icons: [{ src: `data:image/svg+xml,${encodeURIComponent(svg)}`, mimeType: "image/svg+xml", sizes: ["any"] }],
  };
}
