import { App } from "@modelcontextprotocol/ext-apps";

const button = document.querySelector("button");
const status = document.querySelector("#status");
const app = new App({ name: "SSH Connections", version: "1.0.2" });

function render(result) {
  const data = result.structuredContent;
  status.textContent = typeof data?.message === "string"
    ? data.message
    : "Use Settings to enable or disable each SSH host.";
  status.dataset.error = String(Boolean(result.isError));
}

app.ontoolresult = render;
button.addEventListener("click", async () => {
  button.disabled = true;
  status.textContent = "Opening SSH settings...";
  try {
    render(await app.callServerTool({ name: "open_ssh_settings", arguments: {} }));
  } catch {
    status.textContent = "Open ChatGPT and choose Settings > Connections > SSH.";
    status.dataset.error = "true";
  } finally {
    button.disabled = false;
  }
});

app.connect().then(() => {
  button.disabled = false;
}).catch(() => {
  status.textContent = "Open this shortcut from the ChatGPT sidebar, or choose Settings > Connections > SSH.";
  status.dataset.error = "true";
});
