export function getAliasFromUrl() {
  const p = new URLSearchParams(window.location.search);
  return p.get("alias") || "";
}

export function setAliasInLink(id, page, alias) {
  const el = document.getElementById(id);
  if (!el) return;
  el.href = alias ? `${page}?alias=${encodeURIComponent(alias)}` : page;
}

export async function loadAnalyses() {
  const resp = await fetch("api/analysis/list");
  if (!resp.ok) throw new Error("Could not load analyses");
  const payload = await resp.json();
  return Array.isArray(payload.analyses) ? payload.analyses : [];
}

export async function initAliasSelect(selectId) {
  const list = await loadAnalyses();
  const sel = document.getElementById(selectId);
  const currentAlias = getAliasFromUrl() || (list[0]?.alias ?? "");
  sel.innerHTML = list.map(a => `<option value="${a.alias}">${a.alias}</option>`).join("");
  if (currentAlias) {
    sel.value = currentAlias;
  }
  sel.addEventListener("change", () => {
    if (sel.value.startsWith("__")) return;
    const u = new URL(window.location.href);
    u.searchParams.set("alias", sel.value);
    window.location.href = u.toString();
  });
  return sel.value || currentAlias;
}
