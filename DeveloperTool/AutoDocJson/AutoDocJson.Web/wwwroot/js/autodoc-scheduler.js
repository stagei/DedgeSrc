(function () {
    'use strict';

    function _t(key, fallback) {
        if (typeof DedgeAuth !== 'undefined' && typeof DedgeAuth.t === 'function') {
            return DedgeAuth.t(key, fallback);
        }
        return fallback;
    }

    function bp() {
        return (window.__basePath || '/').replace(/\/$/, '');
    }

    let _pollTimer = null;
    let _panelOpen = false;
    let _canManage = false;

    window.toggleSchedulerMenu = function () {
        const panel = document.getElementById('scheduler-panel');
        if (!panel) return;
        _panelOpen = !_panelOpen;
        panel.style.display = _panelOpen ? 'block' : 'none';
        if (_panelOpen) refreshStatus();
    };

    document.addEventListener('click', function (e) {
        const menu = document.getElementById('scheduler-menu');
        if (menu && !menu.contains(e.target) && _panelOpen) {
            _panelOpen = false;
            document.getElementById('scheduler-panel').style.display = 'none';
        }
    });

    window.schedulerAction = async function (action, needsConfirm) {
        if (!_canManage) {
            showError(_t('scheduler.adminOnly', 'Only Admin users can manage the batch job'));
            return;
        }

        if (needsConfirm) {
            var msg = _t('scheduler.confirmRegenerate',
                'This will delete all cached sources and regenerate everything from scratch. Continue?');
            if (!confirm(msg)) return;
        }

        const btns = document.querySelectorAll('.scheduler-actions .btn');
        btns.forEach(b => b.disabled = true);
        hideError();

        try {
            const resp = await fetch(bp() + '/api/scheduler/' + action, { method: 'POST' });
            if (resp.status === 403) {
                showError(_t('scheduler.adminOnly', 'Only Admin users can manage the batch job'));
                return;
            }
            const data = await resp.json();
            if (!data.success) showError(data.message || _t('scheduler.actionFailed', 'Action failed'));
        } catch (ex) {
            showError(ex.message);
        }

        await sleep(1000);
        await refreshStatus();
        updateButtonStates();
    };

    async function refreshStatus() {
        try {
            const resp = await fetch(bp() + '/api/scheduler/status');
            const data = await resp.json();
            applyStatus(data);
        } catch (ex) {
            applyStatus({ exists: false, error: ex.message });
        }
    }

    function applyStatus(s) {
        _canManage = !!(s && s.canManage);

        const dot = document.getElementById('scheduler-dot');
        const badge = document.getElementById('scheduler-state-badge');
        const elStatus = document.getElementById('sched-status');
        const elLastRun = document.getElementById('sched-lastrun');
        const elLastResult = document.getElementById('sched-lastresult');
        const elNextRun = document.getElementById('sched-nextrun');
        const elSchedule = document.getElementById('sched-schedule');
        const actions = document.getElementById('scheduler-actions');

        if (!s.exists) {
            setDotClass(dot, 'error');
            setBadge(badge, _t('scheduler.notFound', 'Not Found'), 'error');
            if (elStatus) elStatus.textContent = s.error || _t('scheduler.notRegistered', 'Task not registered');
            if (elLastRun) elLastRun.textContent = '--';
            if (elLastResult) elLastResult.textContent = '--';
            if (elNextRun) elNextRun.textContent = '--';
            if (elSchedule) elSchedule.textContent = '--';
            disableAllActions();
            return;
        }

        let stateClass = 'unknown';
        let stateLabel = s.status || _t('scheduler.unknown', 'Unknown');

        if (s.isRunning) {
            stateClass = 'running';
            stateLabel = _t('scheduler.running', 'Running');
        } else if (!s.isEnabled) {
            stateClass = 'disabled';
            stateLabel = _t('scheduler.disabled', 'Disabled');
        } else {
            stateClass = 'ready';
            stateLabel = _t('scheduler.ready', 'Ready');
        }

        setDotClass(dot, stateClass);
        setBadge(badge, stateLabel, stateClass);

        if (elStatus) elStatus.textContent = s.status || '--';
        if (elLastRun) elLastRun.textContent = formatTime(s.lastRunTime);
        if (elLastResult) {
            elLastResult.textContent = s.lastResult || '--';
            elLastResult.style.color = s.lastResult === '0' ? '#22c55e' : (s.lastResult && s.lastResult !== '--' ? '#f59e0b' : '');
        }
        if (elNextRun) elNextRun.textContent = formatTime(s.nextRunTime);
        if (elSchedule) elSchedule.textContent = s.scheduleType || '--';

        if (actions) {
            actions.classList.toggle('read-only', !_canManage);
            actions.title = _canManage
                ? ''
                : _t('scheduler.adminOnly', 'Only Admin users can manage the batch job');
        }

        if (!_canManage) {
            disableAllActions();
            return;
        }

        updateButtonStates(s);
    }

    function updateButtonStates(s) {
        const btnStart = document.getElementById('sched-btn-start');
        const btnStop = document.getElementById('sched-btn-stop');
        const btnEnable = document.getElementById('sched-btn-enable');
        const btnDisable = document.getElementById('sched-btn-disable');
        const btnRegenerate = document.getElementById('sched-btn-regenerate');

        if (!s || !s.exists) {
            if (btnStart) btnStart.disabled = true;
            if (btnStop) btnStop.disabled = true;
            if (btnRegenerate) btnRegenerate.disabled = true;
            if (btnEnable) { btnEnable.style.display = 'none'; btnEnable.disabled = true; }
            if (btnDisable) { btnDisable.style.display = 'none'; btnDisable.disabled = true; }
            return;
        }

        if (btnStart) btnStart.disabled = s.isRunning;
        if (btnStop) btnStop.disabled = !s.isRunning;
        if (btnRegenerate) btnRegenerate.disabled = s.isRunning;

        if (s.isEnabled) {
            if (btnEnable) btnEnable.style.display = 'none';
            if (btnDisable) { btnDisable.style.display = ''; btnDisable.disabled = false; }
        } else {
            if (btnEnable) { btnEnable.style.display = ''; btnEnable.disabled = false; }
            if (btnDisable) btnDisable.style.display = 'none';
        }
    }

    function disableAllActions() {
        document.querySelectorAll('.scheduler-actions .btn').forEach(b => b.disabled = true);
    }

    function setDotClass(dot, cls) {
        if (!dot) return;
        dot.className = 'scheduler-status-dot ' + cls;
    }

    function setBadge(badge, text, cls) {
        if (!badge) return;
        badge.textContent = text;
        badge.className = 'scheduler-badge ' + cls;
    }

    function formatTime(val) {
        if (!val) return '--';
        if (val === 'N/A') return _t('scheduler.na', 'N/A');
        if (val === 'Never') return _t('scheduler.never', 'Never');
        return val;
    }

    function showError(msg) {
        const el = document.getElementById('scheduler-error');
        if (el) { el.textContent = msg; el.style.display = 'block'; }
    }

    function hideError() {
        const el = document.getElementById('scheduler-error');
        if (el) el.style.display = 'none';
    }

    function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

    function startPolling() {
        refreshStatus();
        _pollTimer = setInterval(refreshStatus, 30000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startPolling);
    } else {
        startPolling();
    }
})();
