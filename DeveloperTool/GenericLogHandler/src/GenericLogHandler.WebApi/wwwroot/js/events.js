/**
 * Server-Sent Events (SSE) client for real-time updates
 * Provides automatic reconnection and event subscription management
 */
const SSE = (function() {
    'use strict';

    let eventSource = null;
    let reconnectAttempts = 0;
    let reconnectTimer = null;
    let listeners = new Map();
    let isConnected = false;

    const config = {
        url: (typeof Api !== 'undefined' ? Api.baseUrl : '') + '/api/events/stream',
        maxReconnectAttempts: 10,
        baseReconnectDelay: 1000,
        maxReconnectDelay: 30000
    };

    /**
     * Connect to SSE endpoint
     */
    function connect() {
        if (eventSource && eventSource.readyState !== EventSource.CLOSED) {
            console.log('[SSE] Already connected or connecting');
            return;
        }

        console.log('[SSE] Connecting to', config.url);
        eventSource = new EventSource(config.url);

        eventSource.onopen = function() {
            console.log('[SSE] Connected');
            isConnected = true;
            reconnectAttempts = 0;
            notifyListeners('connection', { status: 'connected' });
        };

        eventSource.onerror = function(event) {
            console.warn('[SSE] Connection error', event);
            isConnected = false;
            notifyListeners('connection', { status: 'error' });
            
            if (eventSource.readyState === EventSource.CLOSED) {
                scheduleReconnect();
            }
        };

        // Register known event types
        const eventTypes = [
            'connected',
            'heartbeat',
            'log-imported',
            'import-status-changed',
            'alert-triggered',
            'service-status-changed',
            'database-stats'
        ];

        eventTypes.forEach(type => {
            eventSource.addEventListener(type, function(event) {
                try {
                    const data = JSON.parse(event.data);
                    notifyListeners(type, data);
                } catch (e) {
                    console.error('[SSE] Failed to parse event data:', e);
                }
            });
        });
    }

    /**
     * Disconnect from SSE endpoint
     */
    function disconnect() {
        if (reconnectTimer) {
            clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }
        
        if (eventSource) {
            eventSource.close();
            eventSource = null;
        }
        
        isConnected = false;
        console.log('[SSE] Disconnected');
        notifyListeners('connection', { status: 'disconnected' });
    }

    /**
     * Schedule reconnection with exponential backoff
     */
    function scheduleReconnect() {
        if (reconnectAttempts >= config.maxReconnectAttempts) {
            console.error('[SSE] Max reconnect attempts reached');
            notifyListeners('connection', { status: 'failed', reason: 'max_attempts' });
            return;
        }

        const delay = Math.min(
            config.baseReconnectDelay * Math.pow(2, reconnectAttempts),
            config.maxReconnectDelay
        );
        
        reconnectAttempts++;
        console.log(`[SSE] Reconnecting in ${delay}ms (attempt ${reconnectAttempts})`);
        
        reconnectTimer = setTimeout(() => {
            if (eventSource) {
                eventSource.close();
                eventSource = null;
            }
            connect();
        }, delay);
    }

    /**
     * Subscribe to an event type
     * @param {string} eventType - Event type to subscribe to
     * @param {function} callback - Callback function
     * @returns {function} Unsubscribe function
     */
    function on(eventType, callback) {
        if (!listeners.has(eventType)) {
            listeners.set(eventType, new Set());
        }
        listeners.get(eventType).add(callback);

        // Return unsubscribe function
        return function off() {
            const typeListeners = listeners.get(eventType);
            if (typeListeners) {
                typeListeners.delete(callback);
            }
        };
    }

    /**
     * Unsubscribe from an event type
     * @param {string} eventType - Event type
     * @param {function} callback - Callback to remove
     */
    function off(eventType, callback) {
        const typeListeners = listeners.get(eventType);
        if (typeListeners) {
            if (callback) {
                typeListeners.delete(callback);
            } else {
                listeners.delete(eventType);
            }
        }
    }

    /**
     * Notify all listeners for an event type
     */
    function notifyListeners(eventType, data) {
        const typeListeners = listeners.get(eventType);
        if (typeListeners) {
            typeListeners.forEach(callback => {
                try {
                    callback(data);
                } catch (e) {
                    console.error('[SSE] Listener error:', e);
                }
            });
        }

        // Also notify wildcard listeners
        const wildcardListeners = listeners.get('*');
        if (wildcardListeners) {
            wildcardListeners.forEach(callback => {
                try {
                    callback(eventType, data);
                } catch (e) {
                    console.error('[SSE] Wildcard listener error:', e);
                }
            });
        }
    }

    /**
     * Get connection status
     */
    function getStatus() {
        return {
            connected: isConnected,
            reconnectAttempts: reconnectAttempts,
            readyState: eventSource ? eventSource.readyState : null
        };
    }

    /**
     * Initialize SSE with optional auto-connect
     * @param {boolean} autoConnect - Whether to connect immediately
     */
    function init(autoConnect = true) {
        if (autoConnect) {
            connect();
        }

        // Disconnect on page unload
        window.addEventListener('beforeunload', disconnect);

        // Reconnect when page becomes visible
        document.addEventListener('visibilitychange', function() {
            if (document.visibilityState === 'visible' && !isConnected) {
                connect();
            }
        });
    }

    // Public API
    return {
        init,
        connect,
        disconnect,
        on,
        off,
        getStatus
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = SSE;
}
