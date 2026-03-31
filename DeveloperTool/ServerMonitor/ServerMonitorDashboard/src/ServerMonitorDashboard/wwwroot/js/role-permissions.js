/**
 * ServerMonitor Role-based permissions helper
 * 
 * Roles (highest to lowest):
 * - Admin: Full access (all except ScriptRunner)
 * - PowerUser: Extended access (job control, trigger files, ScriptRunner via TrayApp)
 * - User: Standard view (limited refresh, pop-outs without auto-refresh)
 * - ReadOnly: Minimal view (no auto-refresh, no pop-outs, view only)
 */
const RolePermissions = {
    // Role hierarchy for ServerMonitor
    hierarchy: {
        'Admin': ['Admin', 'PowerUser', 'User', 'ReadOnly'],
        'PowerUser': ['PowerUser', 'User', 'ReadOnly'],
        'User': ['User', 'ReadOnly'],
        'ReadOnly': ['ReadOnly']
    },

    // Cache for user role
    _cachedRole: null,
    _initialized: false,

    /**
     * Initialize role permissions - call after DedgeAuth user menu is ready
     */
    async init() {
        // Wait for DedgeAuth user menu to initialize
        if (window.DedgeAuthUserMenu && !window.DedgeAuthUserMenu.userData) {
            await window.DedgeAuthUserMenu.init();
        }
        this._initialized = true;
        this._cachedRole = this._fetchRole();
        this.applyRoleRestrictions();
    },

    /**
     * Get role from DedgeAuth user data
     */
    _fetchRole() {
        const userData = window.DedgeAuthUserMenu?.userData;
        if (!userData?.authenticated) return null;
        
        const currentApp = userData.applications?.find(a => a.isCurrent);
        return currentApp?.role || null;
    },

    /**
     * Get current user's role for this app
     */
    getCurrentRole() {
        if (!this._initialized) {
            return this._fetchRole();
        }
        return this._cachedRole;
    },

    /**
     * Check if user has at least the specified role
     */
    hasRole(requiredRole) {
        const userRole = this.getCurrentRole();
        if (!userRole) return false;
        
        const userPermissions = this.hierarchy[userRole] || [];
        return userPermissions.includes(requiredRole);
    },

    // Role check helpers
    isAdmin() { return this.getCurrentRole() === 'Admin'; },
    isPowerUser() { return this.hasRole('PowerUser'); },
    isUser() { return this.hasRole('User'); },
    isReadOnly() { return this.getCurrentRole() === 'ReadOnly'; },
    
    // Feature-specific checks
    canControlJobs() { return this.isPowerUser(); },      // Admin, PowerUser
    canManageTriggerFiles() { return this.isPowerUser(); }, // Admin, PowerUser
    canAccessTools() { return this.isAdmin(); },           // Admin only
    canEditConfig() { return this.isAdmin(); },            // Admin only
    canUsePopouts() { return this.hasRole('User') && !this.isReadOnly(); }, // Admin, PowerUser, User
    canAutoRefresh() { return this.isPowerUser(); },       // Admin, PowerUser (full range)

    /**
     * Get available refresh intervals based on role (in seconds, matching HTML select values)
     */
    getAvailableRefreshIntervals() {
        const role = this.getCurrentRole();
        if (role === 'ReadOnly') return []; // No auto-refresh
        if (role === 'User') return [300, 600, 1800, 3600]; // 5,10,30,60 min in seconds
        return [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]; // Full range for Admin/PowerUser
    },

    /**
     * Apply visibility to elements based on role
     */
    applyRoleRestrictions() {
        // Admin-only elements (Tools, Config, Settings)
        document.querySelectorAll('[data-require-role="Admin"]').forEach(el => {
            el.style.display = this.isAdmin() ? '' : 'none';
        });
        
        // PowerUser+ elements (Job control, Trigger files)
        document.querySelectorAll('[data-require-role="PowerUser"]').forEach(el => {
            el.style.display = this.isPowerUser() ? '' : 'none';
        });
        
        // User+ elements (Pop-outs)
        document.querySelectorAll('[data-require-role="User"]').forEach(el => {
            el.style.display = this.hasRole('User') ? '' : 'none';
        });
        
        // Pop-out links - hide for ReadOnly
        document.querySelectorAll('[data-popout-link]').forEach(el => {
            if (this.isReadOnly()) {
                el.style.display = 'none';
            }
        });
        
        // Job control buttons - hide for User and ReadOnly
        document.querySelectorAll('[data-job-control]').forEach(el => {
            if (!this.canControlJobs()) {
                el.style.display = 'none';
            }
        });
        
        // Trigger file buttons - hide for User and ReadOnly
        document.querySelectorAll('[data-trigger-control]').forEach(el => {
            if (!this.canManageTriggerFiles()) {
                el.style.display = 'none';
            }
        });
        
        // Auto-refresh controls - configure based on role
        this.configureRefreshControls();
    },

    /**
     * Configure refresh interval dropdown/controls
     */
    configureRefreshControls() {
        const intervals = this.getAvailableRefreshIntervals();
        const refreshSelect = document.getElementById('refreshInterval');
        
        if (!refreshSelect) return;
        
        if (intervals.length === 0) {
            // ReadOnly: disable auto-refresh entirely
            refreshSelect.disabled = true;
            refreshSelect.title = 'Auto-refresh not available for read-only access';
            // Stop any running auto-refresh
            if (window.refreshTimer) {
                clearInterval(window.refreshTimer);
                window.refreshTimer = null;
            }
        } else if (this.getCurrentRole() === 'User') {
            // User: filter to allowed intervals only (5, 10, 30, 60 minutes)
            Array.from(refreshSelect.options).forEach(opt => {
                const val = parseInt(opt.value);
                if (val > 0 && !intervals.includes(val)) {
                    opt.disabled = true;
                    opt.style.display = 'none';
                }
            });
            // If current selection is not allowed, reset to manual
            const currentVal = parseInt(refreshSelect.value);
            if (currentVal > 0 && !intervals.includes(currentVal)) {
                refreshSelect.value = '0';
                if (window.refreshTimer) {
                    clearInterval(window.refreshTimer);
                    window.refreshTimer = null;
                }
            }
        }
    },

    /**
     * Check if auto-refresh is allowed for pop-out windows
     * User role gets pop-outs but without auto-refresh
     */
    canPopoutAutoRefresh() {
        return this.isPowerUser(); // Admin, PowerUser only
    },

    /**
     * Get pop-out URL with role-based auto-refresh parameter
     */
    getPopoutUrl(baseUrl) {
        if (this.isReadOnly()) {
            return null; // ReadOnly can't use pop-outs
        }
        
        if (this.getCurrentRole() === 'User') {
            // User gets pop-out but without auto-refresh
            const url = new URL(baseUrl, window.location.origin);
            url.searchParams.set('autorefresh', 'false');
            return url.toString();
        }
        
        return baseUrl;
    },

    /**
     * Show access denied message
     */
    showAccessDenied(message) {
        const msg = message || 'You do not have permission to perform this action.';
        if (window.showNotification) {
            window.showNotification(msg, 'error');
        } else {
            alert(msg);
        }
    },

    /**
     * Handle 403 API responses
     */
    handle403Response() {
        this.showAccessDenied('Permission denied. You do not have access to this feature.');
    }
};

// Auto-initialize after DOM is ready and DedgeAuth user menu is loaded
document.addEventListener('DOMContentLoaded', () => {
    // Wait a bit for DedgeAuth-user.js to initialize first
    setTimeout(() => {
        RolePermissions.init().catch(err => {
            console.warn('RolePermissions init failed:', err);
        });
    }, 100);
});

// Export for use in other modules
window.RolePermissions = RolePermissions;
