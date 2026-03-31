/**
 * Debounce and Request Cancellation Utilities
 */

/**
 * Creates a debounced function that delays invoking func until after wait milliseconds
 * have elapsed since the last time the debounced function was invoked.
 * 
 * @param {Function} func - The function to debounce
 * @param {number} wait - The number of milliseconds to delay
 * @param {boolean} immediate - If true, trigger on the leading edge instead of trailing
 * @returns {Function} The debounced function
 */
function debounce(func, wait = 300, immediate = false) {
    let timeout;
    
    return function executedFunction(...args) {
        const context = this;
        
        const later = function() {
            timeout = null;
            if (!immediate) func.apply(context, args);
        };
        
        const callNow = immediate && !timeout;
        
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
        
        if (callNow) func.apply(context, args);
    };
}

/**
 * Creates a throttled function that only invokes func at most once per every wait milliseconds.
 * 
 * @param {Function} func - The function to throttle
 * @param {number} wait - The number of milliseconds to throttle
 * @returns {Function} The throttled function
 */
function throttle(func, wait = 100) {
    let inThrottle;
    
    return function executedFunction(...args) {
        const context = this;
        
        if (!inThrottle) {
            func.apply(context, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, wait);
        }
    };
}

/**
 * Request Manager - Handles request cancellation
 * Use this to cancel previous requests when making new ones
 */
class RequestManager {
    constructor() {
        this.controllers = new Map();
    }

    /**
     * Create a new AbortController for a request key.
     * If there's an existing request with the same key, it will be cancelled.
     * 
     * @param {string} key - Unique identifier for the request type
     * @returns {AbortSignal} The signal to pass to fetch
     */
    getSignal(key) {
        // Cancel any existing request with the same key
        this.cancel(key);
        
        // Create new controller
        const controller = new AbortController();
        this.controllers.set(key, controller);
        
        return controller.signal;
    }

    /**
     * Cancel a request by key
     * 
     * @param {string} key - The request key to cancel
     */
    cancel(key) {
        const controller = this.controllers.get(key);
        if (controller) {
            controller.abort();
            this.controllers.delete(key);
        }
    }

    /**
     * Cancel all pending requests
     */
    cancelAll() {
        this.controllers.forEach((controller, key) => {
            controller.abort();
        });
        this.controllers.clear();
    }

    /**
     * Check if a request is pending
     * 
     * @param {string} key - The request key to check
     * @returns {boolean} True if request is pending
     */
    isPending(key) {
        return this.controllers.has(key);
    }

    /**
     * Mark a request as complete (remove from tracking)
     * 
     * @param {string} key - The request key to mark complete
     */
    complete(key) {
        this.controllers.delete(key);
    }
}

// Create a global request manager instance
const requestManager = new RequestManager();

/**
 * Enhanced fetch with automatic cancellation
 * 
 * @param {string} key - Unique key for this request type
 * @param {string} url - The URL to fetch
 * @param {Object} options - Fetch options
 * @returns {Promise} The fetch promise
 */
async function cancellableFetch(key, url, options = {}) {
    const signal = requestManager.getSignal(key);
    
    try {
        const response = await fetch(url, { ...options, signal });
        requestManager.complete(key);
        return response;
    } catch (error) {
        requestManager.complete(key);
        
        if (error.name === 'AbortError') {
            // Request was cancelled, throw a specific error type
            const cancelError = new Error('Request was cancelled');
            cancelError.name = 'CancelledError';
            cancelError.key = key;
            throw cancelError;
        }
        
        throw error;
    }
}

/**
 * Create a debounced search function with request cancellation
 * 
 * @param {Function} searchFn - The search function to call
 * @param {number} wait - Debounce wait time in ms
 * @returns {Function} Debounced search function
 */
function createDebouncedSearch(searchFn, wait = 300) {
    const debouncedFn = debounce(searchFn, wait);
    
    return function(...args) {
        // Cancel any in-flight searches
        requestManager.cancel('search');
        return debouncedFn.apply(this, args);
    };
}

/**
 * Setup debounce on an input element
 * 
 * @param {HTMLElement|string} element - Input element or selector
 * @param {Function} callback - Callback to invoke with input value
 * @param {number} wait - Debounce wait time in ms
 */
function setupInputDebounce(element, callback, wait = 300) {
    const el = typeof element === 'string' ? document.querySelector(element) : element;
    if (!el) return;

    const debouncedCallback = debounce((e) => {
        callback(e.target.value, e);
    }, wait);

    el.addEventListener('input', debouncedCallback);
    el.addEventListener('keydown', (e) => {
        // Immediate search on Enter
        if (e.key === 'Enter') {
            callback(e.target.value, e);
        }
    });

    return debouncedCallback;
}

// Export for use in other scripts
if (typeof window !== 'undefined') {
    window.debounce = debounce;
    window.throttle = throttle;
    window.RequestManager = RequestManager;
    window.requestManager = requestManager;
    window.cancellableFetch = cancellableFetch;
    window.createDebouncedSearch = createDebouncedSearch;
    window.setupInputDebounce = setupInputDebounce;
}
