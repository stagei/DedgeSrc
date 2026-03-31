/**
 * Generic Log Handler - Shared API helpers
 * Authentication is handled by DedgeAuth SSO (cookie-based JWT via DedgeAuth.Client middleware).
 * This module provides fetch wrappers with request cancellation support.
 */

const Api = {
  // Auto-detect base URL for IIS virtual application paths.
  // When loaded from http://server/GenericLogHandler/js/api.js → baseUrl = '/GenericLogHandler'
  // When loaded from http://localhost:8110/js/api.js → baseUrl = ''
  baseUrl: (function() {
    try {
      const src = document.currentScript?.src || '';
      const idx = src.indexOf('/js/api.js');
      if (idx > 0) {
        return new URL(src.substring(0, idx)).pathname;
      }
    } catch (e) {}
    return '';
  })(),
  
  // Request controllers for cancellation support
  _controllers: new Map(),

  /**
   * Get current user info from DedgeAuth /api/DedgeAuth/me endpoint.
   * Returns cached result if available.
   */
  _cachedUser: null,
  async getCurrentUser() {
    if (this._cachedUser) return this._cachedUser;
    try {
      const res = await fetch(this.baseUrl + '/api/DedgeAuth/me', { credentials: 'include' });
      if (res.ok) {
        this._cachedUser = await res.json();
        return this._cachedUser;
      }
    } catch (e) {}
    return null;
  },

  /**
   * Check if user is authenticated (via DedgeAuth cookie - let the server decide)
   */
  async isAuthenticated() {
    const user = await this.getCurrentUser();
    return user != null;
  },

  /**
   * Core fetch method with optional cancellation
   * DedgeAuth middleware handles auth via cookies (credentials: 'include').
   * On 401, the page is reloaded so DedgeAuth middleware can redirect to login.
   * @param {string} url - The URL to fetch
   * @param {Object} options - Fetch options
   * @param {string} options.cancelKey - Optional key for request cancellation
   */
  async fetch(url, options = {}) {
    const { cancelKey, ...fetchOptions } = options;
    
    // Setup abort controller if cancelKey provided
    let signal;
    if (cancelKey) {
      // Cancel any existing request with same key
      this.cancel(cancelKey);
      const controller = new AbortController();
      this._controllers.set(cancelKey, controller);
      signal = controller.signal;
    }
    
    // Build headers
    const headers = {
      'Content-Type': 'application/json',
      ...(fetchOptions.headers || {})
    };
    
    const opts = {
      credentials: 'include',
      headers,
      signal,
      ...fetchOptions
    };
    
    if (fetchOptions.body !== undefined && typeof fetchOptions.body === 'object' && !(fetchOptions.body instanceof FormData)) {
      opts.body = JSON.stringify(fetchOptions.body);
    }
    
    try {
      const res = await fetch(url, opts);
      
      // Cleanup controller
      if (cancelKey) {
        this._controllers.delete(cancelKey);
      }
      
      // 401 Unauthorized: DedgeAuth session expired or missing.
      // Reload the page so the DedgeAuth middleware can redirect to the DedgeAuth login page.
      if (res.status === 401) {
        window.location.reload();
        throw new Error('Session expired. Redirecting to login...');
      }
      
      if (res.status === 403) {
        throw new Error('You do not have permission to perform this action.');
      }
      
      const data = await res.json().catch(() => ({}));
      
      if (!res.ok) {
        throw new Error(data.Error || data.message || `Request failed: ${res.status}`);
      }
      
      return data;
    } catch (error) {
      // Cleanup controller
      if (cancelKey) {
        this._controllers.delete(cancelKey);
      }
      
      // Check if request was cancelled
      if (error.name === 'AbortError') {
        const cancelError = new Error('Request cancelled');
        cancelError.cancelled = true;
        throw cancelError;
      }
      
      throw error;
    }
  },

  /**
   * Cancel a pending request by key
   * @param {string} key - The cancel key to abort
   */
  cancel(key) {
    const controller = this._controllers.get(key);
    if (controller) {
      controller.abort();
      this._controllers.delete(key);
    }
  },

  /**
   * Cancel all pending requests
   */
  cancelAll() {
    this._controllers.forEach(controller => controller.abort());
    this._controllers.clear();
  },

  /**
   * GET request
   * @param {string} path - API path
   * @param {string} cancelKey - Optional cancel key
   */
  get(path, cancelKey) {
    return this.fetch(this.baseUrl + path, { method: 'GET', cancelKey });
  },

  /**
   * POST request
   * @param {string} path - API path
   * @param {Object} body - Request body
   * @param {string} cancelKey - Optional cancel key
   */
  post(path, body, cancelKey) {
    return this.fetch(this.baseUrl + path, { method: 'POST', body, cancelKey });
  },

  /**
   * PUT request
   * @param {string} path - API path
   * @param {Object} body - Request body
   * @param {string} cancelKey - Optional cancel key
   */
  put(path, body, cancelKey) {
    return this.fetch(this.baseUrl + path, { method: 'PUT', body, cancelKey });
  },

  /**
   * DELETE request
   * @param {string} path - API path
   * @param {string} cancelKey - Optional cancel key
   */
  delete(path, cancelKey) {
    return this.fetch(this.baseUrl + path, { method: 'DELETE', cancelKey });
  },

  /**
   * Logout via DedgeAuth proxy endpoint, then reload to trigger login redirect
   */
  async logout() {
    try {
      await fetch(this.baseUrl + '/api/DedgeAuth/logout', { method: 'POST', credentials: 'include' });
    } catch (e) {}
    window.location.reload();
  }
};

/**
 * Auth helper for pages - uses DedgeAuth SSO (server-side cookie auth).
 * DedgeAuth middleware handles redirects to the login page automatically.
 * These helpers provide client-side access level checks after authentication.
 */
const Auth = {
  /**
   * Get current user info from DedgeAuth
   */
  async getUser() {
    return Api.getCurrentUser();
  },

  /**
   * Check if user has at least the specified access level
   * @param {number} level - Minimum access level (0=ReadOnly, 1=User, 2=PowerUser, 3=Admin)
   */
  async hasLevel(level) {
    const user = await Api.getCurrentUser();
    if (!user) return false;
    const userLevel = parseInt(user.accessLevel || user.globalAccessLevel || '0');
    return userLevel >= level;
  },

  /**
   * Access level constants
   */
  READONLY: 0,
  USER: 1,
  POWERUSER: 2,
  ADMIN: 3
};
