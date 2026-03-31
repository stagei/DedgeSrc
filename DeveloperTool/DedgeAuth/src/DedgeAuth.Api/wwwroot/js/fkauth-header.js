/**
 * DedgeAuth Header Component
 *
 * Renders a uniform brand section (tenant logo + app title) into #DedgeAuthHeader,
 * and renders the standard theme toggle pill into #DedgeAuthThemePill.
 * Manages the shared dark/light theme across all consumer apps.
 *
 * Standard HTML usage:
 *   <div id="DedgeAuthHeader" data-app-title="My App" data-home-url="index.html"></div>
 *   ...header actions...
 *   <div id="DedgeAuthUserMenu"></div>
 *   <div id="DedgeAuthThemePill"></div>
 *   <script src="api/DedgeAuth/ui/header.js" defer></script>
 *
 * #DedgeAuthHeader  → renders brand link (logo + app title) — left side
 * #DedgeAuthThemePill → renders the ☀/🌙 pill toggle   — right of user menu
 *
 * Logo is injected after DedgeAuth-user.js fires the "DedgeAuth:initialized" event.
 * If DedgeAuth is unavailable, the brand renders without a logo.
 */

(function () {
    'use strict';

    const STORAGE_KEY = 'DedgeAuth-theme';

    // ─── Theme ────────────────────────────────────────────────────────────────

    function getPreferredTheme() {
        const saved = localStorage.getItem(STORAGE_KEY);
        if (saved === 'dark' || saved === 'light') return saved;
        return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
            ? 'dark'
            : 'light';
    }

    function applyTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        document.body.classList.toggle('dark-mode', theme === 'dark');
        localStorage.setItem(STORAGE_KEY, theme);
        syncToggleUI(theme);
        document.dispatchEvent(new CustomEvent('DedgeAuth:themechange', { detail: { theme } }));
    }

    function syncToggleUI(theme) {
        // Standard pill buttons (rendered by this component into #DedgeAuthThemePill)
        document.querySelectorAll('.DedgeAuth-theme-btn[data-theme]').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.theme === theme);
        });
    }

    function bindToggle() {
        // Pill buttons (rendered into #DedgeAuthThemePill)
        document.querySelectorAll('.DedgeAuth-theme-btn[data-theme]').forEach(btn => {
            btn.addEventListener('click', () => applyTheme(btn.dataset.theme));
        });

        // System-level preference changes (when user has not saved a preference)
        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
                if (!localStorage.getItem(STORAGE_KEY)) {
                    applyTheme(e.matches ? 'dark' : 'light');
                }
            });
        }
    }

    // ─── Brand rendering ──────────────────────────────────────────────────────

    function render(container) {
        const appTitle = container.dataset.appTitle || document.title || 'App';
        const homeUrl  = container.dataset.homeUrl  || 'index.html';

        container.className = 'DedgeAuth-app-header-brand';
        container.innerHTML = `
            <a href="${escapeAttr(homeUrl)}" class="DedgeAuth-brand" title="Go to ${escapeHtml(appTitle)} home">
                <img id="DedgeAuth-header-logo"
                     class="DedgeAuth-brand-logo"
                     alt=""
                     style="display:none"
                     onerror="this.style.display='none'">
                <span class="DedgeAuth-app-title">${escapeHtml(appTitle)}</span>
            </a>`;
    }

    // ─── Theme pill rendering ─────────────────────────────────────────────────

    function renderPill(container) {
        const theme = getPreferredTheme();
        container.className = 'DedgeAuth-theme-pill';
        container.innerHTML = `
            <button class="DedgeAuth-theme-btn${theme === 'light' ? ' active' : ''}"
                    data-theme="light" title="Light mode" aria-label="Light mode">☀</button>
            <button class="DedgeAuth-theme-btn${theme === 'dark' ? ' active' : ''}"
                    data-theme="dark" title="Dark mode" aria-label="Dark mode">🌙</button>`;
    }

    function injectLogo(detail) {
        const img = document.getElementById('DedgeAuth-header-logo');
        if (!img) return;

        const { DedgeAuthUrl, tenantDomain } = detail || {};
        if (DedgeAuthUrl && tenantDomain) {
            img.src = `${DedgeAuthUrl}/tenants/${tenantDomain}/logo`;
            img.style.display = '';
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    function escapeAttr(str) {
        return String(str).replace(/"/g, '&quot;');
    }

    // ─── Init ─────────────────────────────────────────────────────────────────

    function init() {
        // Apply theme immediately (before paint) to avoid flash of wrong theme
        applyTheme(getPreferredTheme());

        const brandContainer = document.getElementById('DedgeAuthHeader');
        if (brandContainer) {
            render(brandContainer);
        }

        const pillContainer = document.getElementById('DedgeAuthThemePill');
        if (pillContainer) {
            renderPill(pillContainer);
        }

        bindToggle();

        // Listen for DedgeAuth-user.js to provide the tenant logo
        document.addEventListener('DedgeAuth:initialized', e => {
            injectLogo(e.detail);
        });
    }

    // Run as early as possible; re-run after DOM if needed
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // Expose for programmatic use
    window.DedgeAuthHeader = { applyTheme, getPreferredTheme };
})();
