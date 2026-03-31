/**
 * Toast Component - Notification toasts
 * Shows temporary messages at the top/bottom of the screen
 */
const Toast = (function() {
    let container = null;
    const DURATION = 4000;
    const POSITION = 'top-right'; // top-right, top-left, bottom-right, bottom-left, top-center, bottom-center

    /**
     * Initialize toast container
     */
    function init() {
        if (!document.getElementById('toast-container')) {
            container = document.createElement('div');
            container.id = 'toast-container';
            container.className = `toast-container toast-${POSITION}`;
            document.body.appendChild(container);
        } else {
            container = document.getElementById('toast-container');
        }
    }

    /**
     * Show a toast notification
     * @param {string} message - Message to display
     * @param {string} type - 'success', 'error', 'warning', 'info'
     * @param {number} duration - Duration in ms (0 for persistent)
     */
    function show(message, type = 'info', duration = DURATION) {
        if (!container) init();

        const id = 'toast-' + Date.now();
        const icons = {
            success: '✓',
            error: '✕',
            warning: '⚠',
            info: 'ℹ'
        };

        const toast = document.createElement('div');
        toast.id = id;
        toast.className = `toast toast-${type}`;
        toast.innerHTML = `
            <span class="toast-icon">${icons[type] || icons.info}</span>
            <span class="toast-message">${escapeHtml(message)}</span>
            <button class="toast-close" aria-label="Close">&times;</button>
        `;

        // Add to container
        container.appendChild(toast);

        // Trigger animation
        requestAnimationFrame(() => {
            toast.classList.add('toast-visible');
        });

        // Close button handler
        toast.querySelector('.toast-close').addEventListener('click', () => dismiss(id));

        // Auto-dismiss
        if (duration > 0) {
            setTimeout(() => dismiss(id), duration);
        }

        return id;
    }

    /**
     * Dismiss a toast
     */
    function dismiss(id) {
        const toast = document.getElementById(id);
        if (!toast) return;

        toast.classList.remove('toast-visible');
        toast.classList.add('toast-hiding');
        
        setTimeout(() => {
            toast.remove();
        }, 300);
    }

    /**
     * Show success toast
     */
    function success(message, duration) {
        return show(message, 'success', duration);
    }

    /**
     * Show error toast
     */
    function error(message, duration) {
        return show(message, 'error', duration);
    }

    /**
     * Show warning toast
     */
    function warning(message, duration) {
        return show(message, 'warning', duration);
    }

    /**
     * Show info toast
     */
    function info(message, duration) {
        return show(message, 'info', duration);
    }

    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // Initialize on load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    return {
        show,
        dismiss,
        success,
        error,
        warning,
        info
    };
})();
