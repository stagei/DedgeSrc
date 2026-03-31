/**
 * DedgeAuth i18n Translation Loader
 * Provides client-side translation support for DedgeAuth ecosystem apps.
 * Consumer apps include via: <script src="api/DedgeAuth/ui/i18n.js"></script>
 *
 * Listens for 'DedgeAuth:language-changed' event from DedgeAuth-user.js,
 * loads the app's own translations from /api/i18n/{lang}, and applies
 * them to elements with data-i18n attributes.
 */

(function () {
    'use strict';

    window.DedgeAuth = window.DedgeAuth || {};

    let _translations = {};
    let _currentLang = localStorage.getItem('DedgeAuth_language') || 'nb';

    /**
     * Get translated text for a key, with optional fallback.
     * Supports placeholder substitution: DedgeAuth.t('key', { minutes: 5 })
     */
    window.DedgeAuth.t = function (key, fallbackOrParams, params) {
        let text = _translations[key];
        let substitutions = params;

        if (typeof fallbackOrParams === 'string') {
            if (!text) text = fallbackOrParams;
        } else if (typeof fallbackOrParams === 'object' && fallbackOrParams !== null) {
            substitutions = fallbackOrParams;
        }

        if (!text) return key;

        if (substitutions) {
            Object.keys(substitutions).forEach(function (k) {
                text = text.replace(new RegExp('\\{' + k + '\\}', 'g'), substitutions[k]);
            });
        }

        return text;
    };

    /**
     * Get current language code
     */
    window.DedgeAuth.getLanguage = function () {
        return _currentLang;
    };

    /**
     * Apply translations to all elements with data-i18n attributes
     */
    function applyTranslations() {
        document.querySelectorAll('[data-i18n]').forEach(function (el) {
            var key = el.getAttribute('data-i18n');
            var text = _translations[key];
            if (text) {
                el.textContent = text;
            }
        });

        document.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
            var key = el.getAttribute('data-i18n-placeholder');
            var text = _translations[key];
            if (text) {
                el.placeholder = text;
            }
        });

        document.querySelectorAll('[data-i18n-title]').forEach(function (el) {
            var key = el.getAttribute('data-i18n-title');
            var text = _translations[key];
            if (text) {
                el.title = text;
            }
        });

        document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
            var key = el.getAttribute('data-i18n-html');
            var text = _translations[key];
            if (text) {
                el.innerHTML = text;
            }
        });
    }

    /**
     * Load translations for a specific language from the app's local endpoint
     */
    async function loadTranslations(lang) {
        try {
            var response = await fetch('api/i18n/' + lang);
            if (response.ok) {
                _translations = await response.json();
                _currentLang = lang;
                applyTranslations();
                return true;
            }
        } catch (e) {
            // Silently fail — English fallback text in HTML remains
        }

        // Fallback: try loading from DedgeAuth shared translations via proxy
        try {
            var sharedResponse = await fetch('api/DedgeAuth/ui/i18n/' + lang + '.json');
            if (sharedResponse.ok) {
                var sharedTranslations = await sharedResponse.json();
                _translations = Object.assign({}, sharedTranslations, _translations);
                _currentLang = lang;
                applyTranslations();
                return true;
            }
        } catch (e) {
            // Silent fallback
        }

        return false;
    }

    /**
     * Manually trigger translation reload and DOM update
     */
    window.DedgeAuth.applyTranslations = applyTranslations;

    /**
     * Set language and reload translations
     */
    window.DedgeAuth.setLanguage = async function (lang) {
        localStorage.setItem('DedgeAuth_language', lang);
        await loadTranslations(lang);
        document.dispatchEvent(new CustomEvent('DedgeAuth:language-applied', {
            detail: { language: lang }
        }));
    };

    // Listen for language changes from DedgeAuth-user.js
    document.addEventListener('DedgeAuth:language-changed', function (e) {
        var lang = e.detail && e.detail.language;
        if (lang && lang !== _currentLang) {
            loadTranslations(lang);
        }
    });

    // Load translations on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
            loadTranslations(_currentLang);
        });
    } else {
        loadTranslations(_currentLang);
    }
})();
