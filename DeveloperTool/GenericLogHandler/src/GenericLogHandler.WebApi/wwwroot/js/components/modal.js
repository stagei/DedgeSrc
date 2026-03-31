/**
 * Modal Component - Unified modal dialog system
 * Supports multiple modal types: info, confirm, log details
 */
const Modal = (function() {
    let activeModals = [];
    let modalContainer = null;

    /**
     * Initialize modal system
     */
    function init() {
        // Create modal container if not exists
        if (!document.getElementById('modal-container')) {
            modalContainer = document.createElement('div');
            modalContainer.id = 'modal-container';
            document.body.appendChild(modalContainer);
        } else {
            modalContainer = document.getElementById('modal-container');
        }

        // Global escape key handler
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && activeModals.length > 0) {
                closeTop();
            }
        });
    }

    /**
     * Show a modal dialog
     * @param {Object} options - Modal options
     * @param {string} options.title - Modal title
     * @param {string} options.content - Modal HTML content
     * @param {string} options.size - 'small', 'medium', 'large', 'fullscreen'
     * @param {Array} options.buttons - Array of button configs {text, class, onClick}
     * @param {Function} options.onClose - Callback when modal closes
     */
    function show(options = {}) {
        const {
            title = '',
            content = '',
            size = 'medium',
            buttons = [],
            onClose = null,
            closable = true
        } = options;

        const modalId = 'modal-' + Date.now();
        const sizeClass = {
            small: 'modal-sm',
            medium: 'modal-md',
            large: 'modal-lg',
            fullscreen: 'modal-fullscreen'
        }[size] || 'modal-md';

        const html = `
            <div class="modal-overlay" id="${modalId}" data-modal-id="${modalId}">
                <div class="modal-container ${sizeClass}">
                    <div class="modal-header">
                        <h3 class="modal-title">${escapeHtml(title)}</h3>
                        ${closable ? '<button class="modal-close" data-action="close" aria-label="Close">&times;</button>' : ''}
                    </div>
                    <div class="modal-body">
                        ${content}
                    </div>
                    ${buttons.length > 0 ? `
                        <div class="modal-footer">
                            ${buttons.map((btn, i) => `
                                <button class="btn ${btn.class || 'btn-outline'}" data-button-index="${i}">
                                    ${escapeHtml(btn.text)}
                                </button>
                            `).join('')}
                        </div>
                    ` : ''}
                </div>
            </div>
        `;

        modalContainer.insertAdjacentHTML('beforeend', html);
        const modalEl = document.getElementById(modalId);

        // Store modal info
        const modalInfo = { id: modalId, element: modalEl, onClose, buttons };
        activeModals.push(modalInfo);

        // Event delegation for modal
        modalEl.addEventListener('click', (e) => {
            const target = e.target;
            
            // Close button or overlay click
            if (target.dataset.action === 'close' || target.classList.contains('modal-overlay')) {
                if (closable) close(modalId);
            }
            
            // Button click
            const btnIndex = target.dataset.buttonIndex;
            if (btnIndex !== undefined && buttons[btnIndex]) {
                const result = buttons[btnIndex].onClick ? buttons[btnIndex].onClick() : true;
                if (result !== false) close(modalId);
            }
        });

        // Focus trap
        const focusable = modalEl.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        if (focusable.length) focusable[0].focus();

        // Prevent body scroll
        document.body.style.overflow = 'hidden';

        return modalId;
    }

    /**
     * Show log entry details modal
     */
    function showLogDetails(entry) {
        const content = `
            <div class="log-detail-grid">
                <div class="log-detail-row">
                    <span class="log-detail-label">Timestamp:</span>
                    <span class="log-detail-value">${formatDate(entry.Timestamp)}</span>
                </div>
                <div class="log-detail-row">
                    <span class="log-detail-label">Level:</span>
                    <span class="log-detail-value"><span class="level-badge level-${(entry.Level || '').toLowerCase()}">${entry.Level || '-'}</span></span>
                </div>
                <div class="log-detail-row">
                    <span class="log-detail-label">Computer:</span>
                    <span class="log-detail-value">${escapeHtml(entry.ComputerName || '-')}</span>
                </div>
                <div class="log-detail-row">
                    <span class="log-detail-label">User:</span>
                    <span class="log-detail-value">${escapeHtml(entry.UserName || '-')}</span>
                </div>
                <div class="log-detail-row">
                    <span class="log-detail-label">Function:</span>
                    <span class="log-detail-value">${escapeHtml(entry.FunctionName || '-')}</span>
                </div>
                <div class="log-detail-row">
                    <span class="log-detail-label">Source:</span>
                    <span class="log-detail-value">${escapeHtml(entry.SourceFile || '-')}</span>
                </div>
                ${entry.JobName ? `
                <div class="log-detail-row">
                    <span class="log-detail-label">Job:</span>
                    <span class="log-detail-value">${escapeHtml(entry.JobName)} ${entry.JobStatus ? `(${escapeHtml(entry.JobStatus)})` : ''}</span>
                </div>
                ` : ''}
                <div class="log-detail-row log-detail-full">
                    <span class="log-detail-label">Message:</span>
                    <pre class="log-detail-message">${escapeHtml(entry.Message || '-')}</pre>
                </div>
                ${entry.ExceptionType ? `
                <div class="log-detail-row log-detail-full">
                    <span class="log-detail-label">Exception:</span>
                    <pre class="log-detail-exception">${escapeHtml(entry.ExceptionType)}${entry.StackTrace ? '\n' + escapeHtml(entry.StackTrace) : ''}</pre>
                </div>
                ` : ''}
            </div>
        `;

        return show({
            title: 'Log Entry Details',
            content,
            size: 'large',
            buttons: [
                { text: 'Copy as JSON', class: 'btn-outline', onClick: () => { copyToClipboard(JSON.stringify(entry, null, 2)); return false; } },
                { text: 'Close', class: 'btn-primary' }
            ]
        });
    }

    /**
     * Show confirmation dialog
     */
    function confirm(message, options = {}) {
        return new Promise((resolve) => {
            show({
                title: options.title || 'Confirm',
                content: `<p>${escapeHtml(message)}</p>`,
                size: 'small',
                closable: options.closable !== false,
                buttons: [
                    { text: options.cancelText || 'Cancel', class: 'btn-outline', onClick: () => { resolve(false); } },
                    { text: options.confirmText || 'Confirm', class: options.danger ? 'btn-danger' : 'btn-primary', onClick: () => { resolve(true); } }
                ],
                onClose: () => resolve(false)
            });
        });
    }

    /**
     * Show alert dialog
     */
    function alert(message, title = 'Notice') {
        return new Promise((resolve) => {
            show({
                title,
                content: `<p>${escapeHtml(message)}</p>`,
                size: 'small',
                buttons: [
                    { text: 'OK', class: 'btn-primary', onClick: () => resolve() }
                ]
            });
        });
    }

    /**
     * Close a specific modal
     */
    function close(modalId) {
        const index = activeModals.findIndex(m => m.id === modalId);
        if (index === -1) return;

        const modalInfo = activeModals[index];
        if (modalInfo.onClose) modalInfo.onClose();
        
        modalInfo.element.remove();
        activeModals.splice(index, 1);

        if (activeModals.length === 0) {
            document.body.style.overflow = '';
        }
    }

    /**
     * Close the topmost modal
     */
    function closeTop() {
        if (activeModals.length > 0) {
            close(activeModals[activeModals.length - 1].id);
        }
    }

    /**
     * Close all modals
     */
    function closeAll() {
        while (activeModals.length > 0) {
            closeTop();
        }
    }

    // Utility functions
    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function formatDate(dateStr) {
        if (!dateStr) return '-';
        try {
            return new Date(dateStr).toLocaleString();
        } catch {
            return dateStr;
        }
    }

    function copyToClipboard(text) {
        navigator.clipboard.writeText(text).then(() => {
            Toast.show('Copied to clipboard', 'success');
        }).catch(() => {
            Toast.show('Failed to copy', 'error');
        });
    }

    // Initialize on load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    return {
        show,
        showLogDetails,
        confirm,
        alert,
        close,
        closeTop,
        closeAll
    };
})();
