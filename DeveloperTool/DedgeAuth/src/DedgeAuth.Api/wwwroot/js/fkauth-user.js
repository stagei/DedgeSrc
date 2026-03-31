/**
 * DedgeAuth User Menu Component
 * Provides user info display, logout functionality, and app switching
 * Served from DedgeAuth API for consistent behavior across all apps
 */

const DedgeAuth_LANG_FLAGS = {
    nb: { flag: '\u{1F1F3}\u{1F1F4}', label: 'Norsk' },
    en: { flag: '\u{1F1EC}\u{1F1E7}', label: 'English' }
};

class DedgeAuthUserMenu {
    constructor(containerId = 'DedgeAuthUserMenu') {
        this.containerId = containerId;
        this.userData = null;
        this._appTree = null;
        this.isOpen = false;
        this.accessToken = null;
        this.tokenExpiration = null;
        this._sharedTranslations = {};
        this.language = localStorage.getItem('DedgeAuth_language') || 'nb';
        this.supportedLanguages = ['nb', 'en'];
    }

    /**
     * Initialize the user menu
     */
    async init() {
        this.extractAndStoreToken();
        this.parseTokenExpiration();
        await this.fetchUserInfo();

        if (this.userData?.language) {
            this.language = this.userData.language;
            localStorage.setItem('DedgeAuth_language', this.language);
        }
        if (this.userData?.supportedLanguages?.length) {
            this.supportedLanguages = this.userData.supportedLanguages;
        }

        await this.loadSharedTranslations();
        this.loadTenantCss();
        this.render();
        this.attachEventListeners();
    }

    /**
     * Get translated text for a key. Falls back to the key itself.
     */
    _t(key) {
        return this._sharedTranslations[key] || key;
    }

    /**
     * Load shared translations from DedgeAuth's i18n endpoint
     */
    async loadSharedTranslations() {
        try {
            const response = await fetch(`api/DedgeAuth/ui/i18n/${this.language}.json`);
            if (response.ok) {
                this._sharedTranslations = await response.json();
            }
        } catch (e) {
            // Silent fallback — hardcoded English text in render() remains
        }
    }

    /**
     * Change the user's language preference
     */
    async changeLanguage(lang) {
        this.language = lang;
        localStorage.setItem('DedgeAuth_language', lang);

        await this.loadSharedTranslations();
        this.render();
        this.attachEventListeners();

        document.dispatchEvent(new CustomEvent('DedgeAuth:language-changed', {
            detail: { language: lang }
        }));

        if (this.userData?.authenticated) {
            try {
                await fetch('api/DedgeAuth/language', {
                    method: 'PUT',
                    headers: this.getAuthHeaders(),
                    body: JSON.stringify({ language: lang })
                });
            } catch (e) {
                // Best-effort — localStorage already updated
            }
        }
    }

    /**
     * Extract token from URL query string, cookie, or session storage.
     * Priority: ?token= URL param > DedgeAuth_access_token cookie > sessionStorage.
     * The ?code= param is handled server-side by DedgeAuthTokenExtractionMiddleware
     * (exchanged for JWT and stored in the cookie before the page loads).
     */
    extractAndStoreToken() {
        const urlParams = new URLSearchParams(window.location.search);
        const urlToken = urlParams.get('token');
        
        if (urlToken) {
            sessionStorage.setItem('gk_accessToken', urlToken);
            this.accessToken = urlToken;
            
            // Clean URL by removing token parameter
            const cleanUrl = new URL(window.location.href);
            cleanUrl.searchParams.delete('token');
            window.history.replaceState({}, document.title, cleanUrl.toString());
        } else {
            // Try reading from the cookie set by middleware after auth code exchange
            const cookieToken = this._getCookie('DedgeAuth_access_token');
            if (cookieToken) {
                sessionStorage.setItem('gk_accessToken', cookieToken);
                this.accessToken = cookieToken;
            } else {
                this.accessToken = sessionStorage.getItem('gk_accessToken');
            }
        }

        // Clean ?code= from URL if present (middleware already handled the exchange)
        if (urlParams.has('code')) {
            const cleanUrl = new URL(window.location.href);
            cleanUrl.searchParams.delete('code');
            window.history.replaceState({}, document.title, cleanUrl.toString());
        }
    }

    /**
     * Read a cookie value by name
     */
    _getCookie(name) {
        const match = document.cookie.match(new RegExp('(?:^|; )' + name.replace(/([.$?*|{}()[\]\\/+^])/g, '\\$1') + '=([^;]*)'));
        return match ? decodeURIComponent(match[1]) : null;
    }

    /**
     * Parse token to get expiration time
     */
    parseTokenExpiration() {
        if (!this.accessToken) return;
        
        try {
            const payload = JSON.parse(atob(this.accessToken.split('.')[1]));
            if (payload.exp) {
                this.tokenExpiration = new Date(payload.exp * 1000);
            }
        } catch (e) {
            console.warn('Failed to parse token expiration');
        }
    }

    /**
     * Get headers with Authorization token
     */
    getAuthHeaders() {
        const headers = { 'Content-Type': 'application/json' };
        if (this.accessToken) {
            headers['Authorization'] = `Bearer ${this.accessToken}`;
        }
        return headers;
    }

    /**
     * Fetch current user information from the local API
     */
    async fetchUserInfo() {
        try {
            const response = await fetch('api/DedgeAuth/me', {
                headers: this.getAuthHeaders()
            });
            if (response.ok) {
                this.userData = await response.json();

                // Fetch the ACL-filtered app group tree (best-effort)
                if (this.userData.authenticated) {
                    try {
                        const treeResp = await fetch('api/DedgeAuth/app-tree', { headers: this.getAuthHeaders() });
                        if (treeResp.ok) {
                            this._appTree = await treeResp.json();
                        }
                    } catch { /* tree not available, fall back to flat list */ }
                }
            } else {
                console.error('Failed to fetch user info:', response.status);
                this.userData = { authenticated: false };
            }
        } catch (error) {
            console.error('Error fetching user info:', error);
            this.userData = { authenticated: false };
        }
    }

    /**
     * Load tenant-specific CSS from the DedgeAuth server and inject into #DedgeAuth-tenant-css.
     * Works regardless of authentication state — tenant branding is public data.
     * When authenticated, uses tenant domain from /api/DedgeAuth/me claims.
     * When not authenticated, fetches the default tenant from DedgeAuth to get the domain.
     */
    loadTenantCss() {
        // Use DedgeAuthUrl from /me response, or fall back to {origin}/DedgeAuth
        // (standard IIS virtual app path) for consumer apps not yet rebuilt.
        const DedgeAuthUrl = this.userData?.DedgeAuthUrl
            || `${window.location.origin}/DedgeAuth`;
        if (!DedgeAuthUrl) return;

        const styleElement = document.getElementById('DedgeAuth-tenant-css');
        if (!styleElement) return;

        // If authenticated with tenant info, use it directly
        const tenantDomain = this.userData?.tenant?.domain;
        if (tenantDomain) {
            this._injectTenantCss(DedgeAuthUrl, tenantDomain, styleElement);
            this._injectTenantFavicon(DedgeAuthUrl, tenantDomain);
            this._injectTenantLogo(DedgeAuthUrl, tenantDomain);
            this._dispatchInitialized(DedgeAuthUrl, tenantDomain);
            return;
        }

        // Not authenticated or no tenant claim — fetch default tenant from DedgeAuth
        fetch(`${DedgeAuthUrl}/api/tenants/default`)
            .then(response => response.ok ? response.json() : null)
            .then(tenant => {
                if (tenant?.domain) {
                    this._injectTenantCss(DedgeAuthUrl, tenant.domain, styleElement);
                    if (tenant.hasLogoData) {
                        this._injectTenantLogo(DedgeAuthUrl, tenant.domain);
                    }
                    if (tenant.hasIconData || tenant.hasLogoData) {
                        this._injectTenantFavicon(DedgeAuthUrl, tenant.domain);
                    }
                    this._dispatchInitialized(DedgeAuthUrl, tenant.domain);
                } else {
                    this._injectFallbackCss(styleElement);
                    this._dispatchInitialized(DedgeAuthUrl, null);
                }
            })
            .catch(() => {
                this._injectFallbackCss(styleElement);
                this._dispatchInitialized(DedgeAuthUrl, null);
            });
    }

    /**
     * Fetch and inject tenant CSS into the style element.
     * If tenant theme is empty or fetch fails, injects DedgeAuth default fallback (tenant-fallback.css) via local proxy.
     */
    _injectTenantCss(DedgeAuthUrl, tenantDomain, styleElement) {
        const cssUrl = `${DedgeAuthUrl}/tenants/${tenantDomain}/theme.css`;
        fetch(cssUrl)
            .then(response => {
                if (response.ok) return response.text();
                return null;
            })
            .then(css => {
                if (css && css.trim()) {
                    styleElement.textContent = css;
                } else {
                    this._injectFallbackCss(styleElement);
                }
            })
            .catch(() => {
                this._injectFallbackCss(styleElement);
            });
    }

    /**
     * Inject DedgeAuth default tenant fallback CSS when theme.css is empty or unreachable.
     * Uses relative path so consumer app proxy serves api/DedgeAuth/ui/tenant-fallback.css.
     */
    _injectFallbackCss(styleElement) {
        const fallbackUrl = 'api/DedgeAuth/ui/tenant-fallback.css';
        fetch(fallbackUrl)
            .then(response => response.ok ? response.text() : null)
            .then(css => {
                if (css) styleElement.textContent = css;
            })
            .catch(() => {});
    }

    /**
     * Set the tenant logo image on any logo placeholder element.
     * Targets both #DedgeAuth-header-logo (new standard) and #tenant-logo (DocView legacy).
     */
    _injectTenantLogo(DedgeAuthUrl, tenantDomain) {
        const logoUrl = `${DedgeAuthUrl}/tenants/${tenantDomain}/logo`;
        ['DedgeAuth-header-logo', 'tenant-logo'].forEach(id => {
            const img = document.getElementById(id);
            if (img) {
                img.src = logoUrl;
                img.style.display = '';
            }
        });
    }

    /**
     * Dispatch a custom event so DedgeAuth-header.js (and any other listeners)
     * can react to the tenant being resolved without making a second API call.
     */
    _dispatchInitialized(DedgeAuthUrl, tenantDomain) {
        document.dispatchEvent(new CustomEvent('DedgeAuth:initialized', {
            detail: { DedgeAuthUrl, tenantDomain }
        }));
    }

    /**
     * Set the browser tab favicon from the tenant icon endpoint.
     * The server falls back to the logo if no dedicated icon is stored.
     */
    _injectTenantFavicon(DedgeAuthUrl, tenantDomain) {
        let faviconLink = document.getElementById('tenant-favicon');
        if (!faviconLink) {
            faviconLink = document.querySelector('link[rel="icon"]');
        }
        if (!faviconLink) {
            faviconLink = document.createElement('link');
            faviconLink.rel = 'icon';
            faviconLink.id = 'tenant-favicon';
            document.head.appendChild(faviconLink);
        }
        faviconLink.href = `${DedgeAuthUrl}/tenants/${tenantDomain}/icon`;
    }

    /**
     * Format display name with proper capitalization
     */
    formatDisplayName(nameOrEmail) {
        if (!nameOrEmail) return 'Unknown User';
        
        // If it looks like an email, extract and format the name part
        if (nameOrEmail.includes('@')) {
            const namePart = nameOrEmail.split('@')[0];
            // Replace dots/underscores with spaces, capitalize each word
            return namePart
                .replace(/[._]/g, ' ')
                .split(' ')
                .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
                .join(' ');
        }
        
        // Already a name - ensure proper capitalization
        return nameOrEmail
            .split(' ')
            .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
            .join(' ');
    }

    /**
     * Get user initials for avatar
     */
    getInitials(nameOrEmail) {
        if (!nameOrEmail) return '?';
        
        const formatted = this.formatDisplayName(nameOrEmail);
        const parts = formatted.split(' ');
        if (parts.length >= 2) {
            return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
        }
        return formatted.charAt(0).toUpperCase();
    }

    /**
     * Format expiration time for display
     */
    formatExpiration() {
        if (!this.tokenExpiration) return null;
        
        const now = new Date();
        const diff = this.tokenExpiration - now;
        
        if (diff <= 0) return 'Expired';
        
        const minutes = Math.floor(diff / 60000);
        if (minutes < 60) {
            const template = this._t('menu.sessionRemaining');
            return template.replace('{minutes}', minutes);
        }
        
        return this.tokenExpiration.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    /**
     * Build language selector HTML for the dropdown
     */
    _buildLanguageSelector() {
        const buttons = this.supportedLanguages.map(lang => {
            const info = DedgeAuth_LANG_FLAGS[lang] || { flag: lang.toUpperCase(), label: lang };
            const isActive = lang === this.language ? ' gk-lang-active' : '';
            return `<button class="gk-lang-btn${isActive}" data-lang="${lang}" title="${info.label}">${info.flag}</button>`;
        }).join('');

        return `
            <div class="gk-lang-selector">
                <span class="gk-lang-label">${this._t('menu.language')}</span>
                <div class="gk-lang-buttons">${buttons}</div>
            </div>
        `;
    }

    /**
     * Render the user menu HTML
     */
    render() {
        const container = document.getElementById(this.containerId);
        if (!container) {
            console.warn(`Container #${this.containerId} not found`);
            return;
        }

        if (!this.userData?.authenticated) {
            container.innerHTML = '';
            return;
        }

        const user = this.userData.user;
        const apps = this.userData.applications || [];
        const otherApps = apps.filter(app => !app.isCurrent && app.url);
        const displayName = this.formatDisplayName(user.name || user.email);
        const expiresText = this.formatExpiration();

        const buildAppLink = (app) => {
            const rawUrl = (app.url || '').replace(/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?/, window.location.origin);
            const appUrl = rawUrl.endsWith('/') ? rawUrl : rawUrl + '/';
            const appDisplayName = app.name || this.formatAppName(app.appId);
            return `<a href="${appUrl}" class="gk-app-link" title="${app.appId}">
                <span class="gk-app-icon">\u{1F4E6}</span>
                <span class="gk-app-name">${appDisplayName}</span>
                <span class="gk-app-role">${app.role || ''}</span>
            </a>`;
        };

        const renderTreeMenu = (nodes) => {
            let html = '';
            for (const node of nodes) {
                if (node.type === 'group') {
                    html += `<div class="gk-section-title" style="margin-top:8px; padding-left:4px;">\u{1F4C1} ${node.name}</div>`;
                    if (node.children) {
                        for (const child of node.children) {
                            if (child.type === 'app') {
                                html += buildAppLink(child);
                            } else {
                                html += renderTreeMenu([child]);
                            }
                        }
                    }
                } else if (node.type === 'app') {
                    html += buildAppLink(node);
                }
            }
            return html;
        };

        let appLinksHtml = '';
        if (this._appTree && this._appTree.tree && this._appTree.tree.length > 0) {
            appLinksHtml = renderTreeMenu(this._appTree.tree);
            if (this._appTree.ungrouped) {
                for (const app of this._appTree.ungrouped) {
                    appLinksHtml += buildAppLink(app);
                }
            }
        } else {
            appLinksHtml = otherApps.map(app => buildAppLink(app)).join('');
        }

        container.innerHTML = `
            <div class="gk-user-menu">
                <button class="gk-user-button" id="gkUserButton" title="User menu">
                    <span class="gk-user-avatar">${this.getInitials(user.name || user.email)}</span>
                    <span class="gk-user-name">${displayName}</span>
                    <span class="gk-dropdown-arrow">\u25BC</span>
                </button>
                <div class="gk-dropdown" id="gkDropdown">
                    <div class="gk-dropdown-header">
                        <div class="gk-auth-status">\u2713 ${this._t('menu.authenticated')}</div>
                        <div class="gk-user-email">${user.email}</div>
                        <div class="gk-user-role">${user.globalAccessLevelName || 'User'}</div>
                        ${user.tenant ? `<div class="gk-user-tenant">${user.tenant}</div>` : ''}
                        ${expiresText ? `<div class="gk-token-expires">${expiresText}</div>` : ''}
                        ${this._buildLanguageSelector()}
                    </div>
                    
                    ${otherApps.length > 0 ? `
                        <div class="gk-dropdown-section">
                            <div class="gk-section-title">${this._t('menu.switchApp')}</div>
                            ${appLinksHtml}
                        </div>
                    ` : ''}
                    
                    <div class="gk-dropdown-section">
                        <a href="${this.userData.DedgeAuthUrl}/login.html" class="gk-menu-link" title="${this._t('menu.portal')}">
                            <span class="gk-menu-icon">\u{1F3E0}</span>
                            <span>${this._t('menu.portal')}</span>
                        </a>
                        ${(user.globalAccessLevel >= 3 || user.globalAccessLevel == 5) ? `
                            <a href="${this.userData.DedgeAuthUrl}/admin.html" class="gk-menu-link" title="${this._t('menu.admin')}">
                                <span class="gk-menu-icon">\u2699\uFE0F</span>
                                <span>${this._t('menu.admin')}</span>
                            </a>
                        ` : ''}
                    </div>
                    
                    <div class="gk-dropdown-footer">
                        <button class="gk-logout-button" id="gkLogoutButton">
                            <span class="gk-logout-icon">\u{1F6AA}</span>
                            <span>${this._t('menu.signOut')}</span>
                        </button>
                    </div>
                </div>
            </div>
        `;
    }

    /**
     * Format app ID to readable name
     */
    formatAppName(appId) {
        if (!appId) return 'Unknown App';
        // Split PascalCase: "ServerMonitorDashboard" -> "Server Monitor Dashboard"
        return appId.replace(/([A-Z])/g, ' $1').trim();
    }

    /**
     * Attach event listeners
     */
    attachEventListeners() {
        const userButton = document.getElementById('gkUserButton');
        const dropdown = document.getElementById('gkDropdown');
        const logoutButton = document.getElementById('gkLogoutButton');

        if (userButton && dropdown) {
            userButton.addEventListener('click', (e) => {
                e.stopPropagation();
                this.toggleDropdown();
            });

            document.addEventListener('click', (e) => {
                if (!e.target.closest('.gk-user-menu')) {
                    this.closeDropdown();
                }
            });

            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    this.closeDropdown();
                }
            });
        }

        if (logoutButton) {
            logoutButton.addEventListener('click', () => this.logout());
        }

        // Language selector buttons
        document.querySelectorAll('.gk-lang-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const lang = btn.getAttribute('data-lang');
                if (lang && lang !== this.language) {
                    this.changeLanguage(lang);
                }
            });
        });
    }

    toggleDropdown() {
        const dropdown = document.getElementById('gkDropdown');
        if (dropdown) {
            this.isOpen = !this.isOpen;
            dropdown.classList.toggle('open', this.isOpen);
        }
    }

    closeDropdown() {
        const dropdown = document.getElementById('gkDropdown');
        if (dropdown) {
            this.isOpen = false;
            dropdown.classList.remove('open');
        }
    }

    /**
     * Logout user - calls DedgeAuth directly to revoke tokens
     */
    async logout() {
        const logoutButton = document.getElementById('gkLogoutButton');
        if (logoutButton) {
            logoutButton.disabled = true;
            logoutButton.innerHTML = '<span class="gk-logout-icon">⏳</span><span>Signing out...</span>';
        }

        const DedgeAuthUrl = this.userData?.DedgeAuthUrl || '';

        try {
            // Call DedgeAuth logout endpoint directly to revoke tokens
            await fetch(`${DedgeAuthUrl}/api/auth/logout`, {
                method: 'POST',
                headers: this.getAuthHeaders(),
                credentials: 'include'  // Include refresh token cookie
            });
        } catch (error) {
            console.warn('DedgeAuth logout call failed:', error);
        }

        // Clear all stored tokens
        localStorage.removeItem('accessToken');
        localStorage.removeItem('user');
        sessionStorage.removeItem('gk_accessToken');
        this.accessToken = null;

        // Redirect to DedgeAuth login
        window.location.href = `${DedgeAuthUrl}/login.html`;
    }
}

/**
 * Static helper to get the current access token.
 * Checks URL param, cookie (from auth code exchange), then sessionStorage.
 */
DedgeAuthUserMenu.getAccessToken = function() {
    const urlParams = new URLSearchParams(window.location.search);
    const urlToken = urlParams.get('token');
    if (urlToken) {
        sessionStorage.setItem('gk_accessToken', urlToken);
        return urlToken;
    }
    // Check cookie set by DedgeAuthTokenExtractionMiddleware after auth code exchange
    const cookieMatch = document.cookie.match(/(?:^|; )DedgeAuth_access_token=([^;]*)/);
    if (cookieMatch) {
        const cookieToken = decodeURIComponent(cookieMatch[1]);
        sessionStorage.setItem('gk_accessToken', cookieToken);
        return cookieToken;
    }
    return sessionStorage.getItem('gk_accessToken');
};

/**
 * Static helper to get auth headers for fetch calls
 */
DedgeAuthUserMenu.getAuthHeaders = function() {
    const token = DedgeAuthUserMenu.getAccessToken();
    const headers = { 'Content-Type': 'application/json' };
    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }
    return headers;
};

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const container = document.getElementById('DedgeAuthUserMenu');
    if (container) {
        const userMenu = new DedgeAuthUserMenu('DedgeAuthUserMenu');
        userMenu.init();
        window.DedgeAuthUserMenu = userMenu;
    }
});
