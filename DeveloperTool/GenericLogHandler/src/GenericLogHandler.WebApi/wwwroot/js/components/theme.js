/**
 * Theme Component - Unified dark/light mode toggle
 * Standardizes theme storage key to 'loghandler-theme' across all pages
 */
const Theme = (function() {
    const STORAGE_KEY = 'loghandler-theme';
    const DARK_CLASS = 'dark-mode';
    const DARK_ATTR = 'dark';
    
    let currentTheme = 'light';
    let toggleButton = null;
    let iconElement = null;

    /**
     * Initialize theme from localStorage or system preference
     */
    function init(buttonSelector = '#themeToggle') {
        // Get saved theme or detect system preference
        const savedTheme = localStorage.getItem(STORAGE_KEY);
        if (savedTheme) {
            currentTheme = savedTheme;
        } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
            currentTheme = 'dark';
        }

        // Apply theme immediately
        applyTheme(currentTheme);

        // Setup toggle (supports both button and checkbox)
        toggleButton = document.querySelector(buttonSelector);
        if (toggleButton) {
            if (toggleButton.type === 'checkbox') {
                // New checkbox-based toggle
                toggleButton.checked = currentTheme === 'dark';
                toggleButton.addEventListener('change', () => {
                    setTheme(toggleButton.checked ? 'dark' : 'light');
                });
            } else {
                // Legacy button toggle
                iconElement = toggleButton.querySelector('.theme-icon') || toggleButton.querySelector('span');
                updateIcon();
                toggleButton.addEventListener('click', toggle);
            }
        }

        // Listen for system theme changes
        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
                if (!localStorage.getItem(STORAGE_KEY)) {
                    setTheme(e.matches ? 'dark' : 'light');
                }
            });
        }

        return currentTheme;
    }

    /**
     * Apply theme to document
     */
    function applyTheme(theme) {
        if (theme === 'dark') {
            document.documentElement.setAttribute('data-theme', 'dark');
            document.body.classList.add(DARK_CLASS);
        } else {
            document.documentElement.setAttribute('data-theme', 'light');
            document.body.classList.remove(DARK_CLASS);
        }
    }

    /**
     * Update the toggle button icon/state
     */
    function updateIcon() {
        if (toggleButton && toggleButton.type === 'checkbox') {
            // Sync checkbox state
            toggleButton.checked = currentTheme === 'dark';
        } else if (iconElement) {
            // Legacy emoji icon
            iconElement.textContent = currentTheme === 'dark' ? '☀️' : '🌙';
        }
    }

    /**
     * Toggle between dark and light themes
     */
    function toggle() {
        setTheme(currentTheme === 'dark' ? 'light' : 'dark');
    }

    /**
     * Set a specific theme
     */
    function setTheme(theme) {
        currentTheme = theme;
        localStorage.setItem(STORAGE_KEY, theme);
        applyTheme(theme);
        updateIcon();
        
        // Dispatch event for other components
        document.dispatchEvent(new CustomEvent('themechange', { detail: { theme } }));
    }

    /**
     * Get current theme
     */
    function getTheme() {
        return currentTheme;
    }

    /**
     * Check if dark mode is active
     */
    function isDark() {
        return currentTheme === 'dark';
    }

    return {
        init,
        toggle,
        setTheme,
        getTheme,
        isDark
    };
})();

// Auto-initialize if DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => Theme.init());
} else {
    Theme.init();
}
