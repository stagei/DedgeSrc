import { initAliasSelect, setAliasInLink } from "./shared.js";

function getAuthHeaders() {
  return typeof DedgeAuthUserMenu !== "undefined" ? DedgeAuthUserMenu.getAuthHeaders() : {};
}

function formatDuration(startIso) {
  const ms = Date.now() - new Date(startIso).getTime();
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h ${m % 60}m ${s % 60}s`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}

async function pollJobStatus(jobId, out) {
  const headers = { ...getAuthHeaders() };
  let interval = 3000;

  const poll = async () => {
    try {
      const resp = await fetch(`api/job/${jobId}/status`, { headers });
      if (!resp.ok) return;
      const status = await resp.json();

      if (status.status === "running") {
        const elapsed = formatDuration(status.startedAt);
        out.textContent = `Job ${status.jobId.substring(0, 8)}... running (${elapsed})\nAlias: ${status.alias}\nStatus: running`;
        interval = Math.min(interval * 1.2, 15000);
        setTimeout(poll, interval);
      } else {
        const elapsed = status.completedAt
          ? formatDuration(status.startedAt)
          : "unknown";
        const icon = status.status === "completed" ? "OK" : "FAILED";
        out.textContent = `[${icon}] Job ${status.status} in ${elapsed}\nAlias: ${status.alias}\nExit code: ${status.exitCode ?? "N/A"}`;
        if (status.error) out.textContent += `\nError: ${status.error}`;
        if (status.status === "completed") {
          out.textContent += "\n\nReloading analysis list...";
          setTimeout(() => window.location.reload(), 2000);
        }
      }
    } catch {
      setTimeout(poll, interval);
    }
  };

  setTimeout(poll, interval);
}

async function init() {
  const alias = await initAliasSelect("aliasSelect");
  setAliasInLink("viewerLink", "viewer.html", alias);
  setAliasInLink("graphLink", "graph.html", alias);

  const fileInput = document.getElementById("allJsonFile");
  const fileLabel = document.getElementById("fileLabel");
  const pathInput = document.getElementById("allJsonPath");
  const startBtn = document.getElementById("startBtn");
  const picker = fileInput?.closest(".file-picker");

  fileInput?.addEventListener("change", () => {
    const file = fileInput.files[0];
    if (file) {
      fileLabel.textContent = file.name;
      picker?.classList.add("has-file");
      pathInput.value = "";
      pathInput.disabled = true;
    } else {
      fileLabel.textContent = "Choose file...";
      picker?.classList.remove("has-file");
      pathInput.disabled = false;
    }
  });

  pathInput?.addEventListener("input", () => {
    if (pathInput.value.trim()) {
      fileInput.value = "";
      fileLabel.textContent = "Choose file...";
      picker?.classList.remove("has-file");
    }
  });

  startBtn?.addEventListener("click", async () => {
    const newAlias = document.getElementById("newAlias").value?.trim();
    const out = document.getElementById("jobResult");
    const file = fileInput?.files[0];
    let allJsonPath = pathInput?.value?.trim();

    if (!newAlias) {
      out.textContent = "Alias is required.";
      return;
    }
    if (!file && !allJsonPath) {
      out.textContent = "Provide a server path or select a local file.";
      return;
    }

    startBtn.disabled = true;

    try {
      if (file) {
        out.textContent = `Uploading ${file.name} (${(file.size / 1024).toFixed(1)} KB)...`;
        const form = new FormData();
        form.append("alias", newAlias);
        form.append("file", file);

        const uploadResp = await fetch("api/job/upload", {
          method: "POST",
          headers: getAuthHeaders(),
          body: form
        });
        if (!uploadResp.ok) {
          const err = await uploadResp.json().catch(() => ({ error: uploadResp.statusText }));
          out.textContent = `Upload failed: ${err.error || uploadResp.statusText}`;
          startBtn.disabled = false;
          return;
        }
        const uploadResult = await uploadResp.json();
        allJsonPath = uploadResult.path;
        out.textContent = `Uploaded to server. Starting analysis...`;
      } else {
        out.textContent = "Starting analysis...";
      }

      const skipRag = document.getElementById("skipRagPhases")?.checked;
      const skipClass = document.getElementById("skipClassification")?.checked;
      const body = { alias: newAlias, allJsonPath };
      if (skipRag) body.skipPhases = [5, 6];
      if (skipClass) body.skipClassification = true;

      const resp = await fetch("api/job/start", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...getAuthHeaders() },
        body: JSON.stringify(body)
      });

      if (!resp.ok) {
        const err = await resp.json().catch(() => ({ error: resp.statusText }));
        out.textContent = `Start failed: ${err.error || resp.statusText}`;
        startBtn.disabled = false;
        return;
      }

      const payload = await resp.json();
      out.textContent = `Job started: ${payload.jobId.substring(0, 8)}...\nAlias: ${payload.alias}\nStatus: ${payload.status}`;

      pollJobStatus(payload.jobId, out);
    } catch (e) {
      out.textContent = `Error: ${e.message || e}`;
      startBtn.disabled = false;
    }
  });
}

init().catch(e => {
  const out = document.getElementById("jobResult");
  if (out) out.textContent = String(e);
});
