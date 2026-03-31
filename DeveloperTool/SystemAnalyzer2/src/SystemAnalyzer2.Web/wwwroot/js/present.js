import { initAliasSelect, setAliasInLink } from "./shared.js";

function parseMarkdown(md) {
  const m = globalThis.marked;
  if (m && typeof m.parse === "function") {
    return m.parse(md, { mangle: false, headerIds: false });
  }
  return `<pre>${escapeHtml(md)}</pre>`;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function buildSlides(alias) {
  const inner = document.getElementById("slidesInner");
  const hint = document.getElementById("presentTitleHint");
  inner.innerHTML = "<section><p>Loading…</p></section>";
  if (!alias) {
    inner.innerHTML = "<section><p>Select an analysis alias.</p></section>";
    if (hint) hint.textContent = "";
    return;
  }

  const r = await fetch(`api/present/${encodeURIComponent(alias)}/slides`);
  if (!r.ok) {
    const err = await r.json().catch(() => ({}));
    inner.innerHTML = `<section><p>Could not load slides: ${escapeHtml(err.error || r.statusText)}</p></section>`;
    if (hint) hint.textContent = "";
    return;
  }

  const data = await r.json();
  if (hint) hint.textContent = data.title || alias;

  const slides = data.slides || [];
  inner.innerHTML = "";
  slides.forEach(s => {
    const sec = document.createElement("section");
    if (s.html) sec.innerHTML = s.html;
    else if (s.markdown) sec.innerHTML = parseMarkdown(s.markdown);
    else if (s.imageUrl) {
      const src = s.imageUrl.startsWith("http") ? s.imageUrl : s.imageUrl;
      sec.innerHTML = `<img src="${escapeHtml(src)}" alt="" />`;
    } else sec.innerHTML = "<p>(empty slide)</p>";
    inner.appendChild(sec);
  });

  if (inner.children.length === 0) {
    inner.innerHTML = "<section><p>No slides for this profile.</p></section>";
  }
}

async function main() {
  const alias = await initAliasSelect("presentAliasSelect");
  setAliasInLink("graphFromPresent", "graph.html", alias);
  await buildSlides(alias);

  if (typeof Reveal !== "undefined") {
    Reveal.initialize({
      hash: true,
      slideNumber: "c/t",
      transition: "slide",
      backgroundTransition: "fade",
      width: 1280,
      height: 720,
      margin: 0.06
    });
  }
}

main().catch(e => {
  const inner = document.getElementById("slidesInner");
  if (inner) inner.innerHTML = `<section><p>${escapeHtml(String(e.message || e))}</p></section>`;
  console.error(e);
});
