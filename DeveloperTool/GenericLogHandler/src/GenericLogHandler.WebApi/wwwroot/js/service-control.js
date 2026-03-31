/**
 * Service Control - Maintenance page: start/stop Import Service and Alert Agent.
 * Polls status, shows running indicator, displays API messages and loading state.
 */
(function (global) {
  'use strict';

  var POLL_INTERVAL_MS = 5000;
  var MESSAGE_DISPLAY_MS = 5000;
  var apiBase = '/api/maintenance/';

  var elements = {
    importStatus: null,
    agentStatus: null,
    importIndicator: null,
    agentIndicator: null,
    messageEl: null,
    lastUpdatedEl: null,
    contentWrapper: null
  };

  function get(id) {
    return document.getElementById(id);
  }

  function setRunningIndicator(id, isRunning) {
    var el = elements[id] || get(id);
    if (!el) return;
    el.classList.toggle('running', !!isRunning);
    el.setAttribute('aria-hidden', !isRunning);
  }

  function setStatus(id, text) {
    var el = elements[id] || get(id);
    if (el) el.textContent = text || '—';
  }

  function setLoading(loading) {
    var wrapper = elements.contentWrapper || document.querySelector('.service-control-content');
    if (wrapper) wrapper.classList.toggle('service-control-loading', !!loading);
  }

  function setLastUpdated(date) {
    var el = elements.lastUpdatedEl || get('serviceControlLastUpdated');
    if (el) {
      el.textContent = date ? 'Last updated: ' + date.toLocaleTimeString() : '';
      el.setAttribute('aria-live', 'polite');
    }
  }

  function showMessage(text, isError) {
    var el = elements.messageEl || get('serviceControlMessage');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'service-control-message' + (isError ? ' service-control-message-error' : ' service-control-message-success');
    el.setAttribute('aria-live', 'assertive');
    if (text) {
      clearTimeout(showMessage._hideTimer);
      showMessage._hideTimer = setTimeout(function () {
        el.textContent = '';
        el.className = 'service-control-message';
      }, MESSAGE_DISPLAY_MS);
    }
  }

  function updateUI(data) {
    if (!data || !data.Data) return;
    var importS = data.Data.Import;
    var agentS = data.Data.Agent;
    setStatus('importStatus', importS ? importS.Status + (importS.Message ? ' — ' + importS.Message : '') : '—');
    setStatus('agentStatus', agentS ? agentS.Status + (agentS.Message ? ' — ' + agentS.Message : '') : '—');
    var importRunning = importS && (importS.Status === 'Running' || importS.Status === 'StartPending' || importS.Status === 'ContinuePending');
    var agentRunning = agentS && (agentS.Status === 'Running' || agentS.Status === 'StartPending' || agentS.Status === 'ContinuePending');
    setRunningIndicator('importIndicator', !!importRunning);
    setRunningIndicator('agentIndicator', !!agentRunning);
    setLastUpdated(new Date());
  }

  function getApi() {
    return (typeof global !== 'undefined' && global.Api) || (typeof window !== 'undefined' && window.Api);
  }

  function fetchServices() {
    var api = getApi();
    if (!api) {
      setStatus('importStatus', 'API not loaded. Check console.');
      setStatus('agentStatus', '');
      return;
    }
    setStatus('importStatus', 'Loading…');
    setStatus('agentStatus', 'Loading…');
    setLoading(true);
    api.get(apiBase + 'services')
      .then(function (data) {
        updateUI(data);
      })
      .catch(function (err) {
        var msg = (err && err.message) ? err.message : 'Failed to load';
        setStatus('importStatus', msg);
        setStatus('agentStatus', msg);
        showMessage(msg, true);
      })
      .finally(function () {
        setLoading(false);
      });
  }

  function postAction(endpoint, button) {
    var api = getApi();
    if (!api) {
      showMessage('API not loaded.', true);
      return;
    }
    var buttons = document.querySelectorAll('.btn-service-start, .btn-service-stop');
    for (var i = 0; i < buttons.length; i++) buttons[i].disabled = true;
    setLoading(true);
    showMessage('Sending…', false);
    api.post(apiBase + endpoint)
      .then(function (res) {
        var msg = res && res.Data && res.Data.Message ? res.Data.Message : (res && res.Data && res.Data.Success ? 'Done.' : '');
        var success = res && res.Data && res.Data.Success;
        if (msg) showMessage(msg, !success);
        fetchServices();
      })
      .catch(function (err) {
        var msg = (err && err.message) ? err.message : 'Request failed';
        showMessage(msg, true);
        fetchServices();
      })
      .finally(function () {
        var buttons = document.querySelectorAll('.btn-service-start, .btn-service-stop');
        for (var i = 0; i < buttons.length; i++) buttons[i].disabled = false;
        setLoading(false);
      });
  }

  function init() {
    elements.importStatus = get('importStatus');
    elements.agentStatus = get('agentStatus');
    elements.importIndicator = get('importIndicator');
    elements.agentIndicator = get('agentIndicator');
    elements.messageEl = get('serviceControlMessage');
    elements.lastUpdatedEl = get('serviceControlLastUpdated');
    elements.contentWrapper = document.querySelector('.service-control-content');

    document.querySelectorAll('.btn-service-start, .btn-service-stop').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var endpoint = btn.getAttribute('data-endpoint');
        if (endpoint) postAction(endpoint, btn);
      });
    });

    fetchServices();
    setInterval(fetchServices, POLL_INTERVAL_MS);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})(typeof window !== 'undefined' ? window : this);
