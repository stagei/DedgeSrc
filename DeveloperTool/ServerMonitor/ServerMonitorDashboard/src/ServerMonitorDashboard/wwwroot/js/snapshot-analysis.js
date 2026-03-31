(function () {
    'use strict';

    const overlay = document.getElementById('loading-overlay');
    const progressEl = document.getElementById('loading-progress');
    const serverSelect = document.getElementById('serverSelect');
    const dateFrom = document.getElementById('dateFrom');
    const dateTo = document.getElementById('dateTo');
    const btnGenerate = document.getElementById('btnGenerate');
    const reportArea = document.getElementById('report-area');
    const noReport = document.getElementById('no-report');

    const btnSaveJson = document.getElementById('btnSaveJson');
    const btnSaveHtml = document.getElementById('btnSaveHtml');

    let cpuChart = null, memChart = null, diskChart = null;
    let alertTimelineCharts = [];
    let lastReport = null;

    applyTheme();
    setDefaultDates();
    loadServers();

    btnGenerate.addEventListener('click', startAnalysis);
    btnSaveJson.addEventListener('click', saveReportAsJson);
    btnSaveHtml.addEventListener('click', saveReportAsHtml);

    function applyTheme() {
        const saved = localStorage.getItem('dashboard-theme');
        if (saved === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
    }

    function setDefaultDates() {
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        dateFrom.value = toLocalISOString(todayStart);
        dateTo.value = toLocalISOString(now);
    }

    function toLocalISOString(d) {
        const pad = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    async function loadServers() {
        try {
            const res = await fetch('api/analysis/servers');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const servers = await res.json();

            serverSelect.innerHTML = '';
            if (servers.length === 0) {
                serverSelect.innerHTML = '<option value="">-- No servers found --</option>';
                return;
            }

            servers.forEach(s => {
                const opt = document.createElement('option');
                opt.value = s.name;
                opt.textContent = `${s.name} (${s.fileCount} files)`;
                serverSelect.appendChild(opt);
            });

            btnGenerate.disabled = false;
        } catch (err) {
            serverSelect.innerHTML = `<option value="">Error: ${err.message}</option>`;
        }
    }

    async function startAnalysis() {
        const server = serverSelect.value;
        if (!server) return;

        const from = new Date(dateFrom.value).toISOString();
        const to = new Date(dateTo.value).toISOString();

        showOverlay();
        btnGenerate.disabled = true;
        btnSaveJson.classList.add('hidden');
        btnSaveHtml.classList.add('hidden');
        reportArea.classList.add('hidden');
        noReport.classList.add('hidden');

        try {
            const res = await fetch('api/analysis/jobs', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ server, from, to })
            });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const { jobId } = await res.json();
            await pollJobStatus(jobId);
        } catch (err) {
            hideOverlay();
            noReport.classList.remove('hidden');
            noReport.innerHTML = `<div class="error-message">Error starting analysis: ${escapeHtml(err.message)}</div>`;
            btnGenerate.disabled = false;
        }
    }

    async function pollJobStatus(jobId) {
        while (true) {
            await sleep(2000);
            try {
                const res = await fetch(`api/analysis/jobs/${jobId}`);
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                const job = await res.json();

                if (job.totalFiles > 0) {
                    progressEl.textContent = `Processing ${job.filesProcessed} / ${job.totalFiles} files...`;
                }

                if (job.status === 'Completed') {
                    hideOverlay();
                    btnGenerate.disabled = false;
                    if (job.report && job.report.snapshotCount > 0) {
                        renderReport(job.report);
                    } else {
                        noReport.classList.remove('hidden');
                        noReport.innerHTML = '<div class="no-data">No snapshots found for the selected server and date range.</div>';
                    }
                    return;
                }

                if (job.status === 'Failed') {
                    hideOverlay();
                    btnGenerate.disabled = false;
                    noReport.classList.remove('hidden');
                    noReport.innerHTML = `<div class="error-message">Analysis failed: ${escapeHtml(job.errorMessage || 'Unknown error')}</div>`;
                    return;
                }
            } catch (err) {
                hideOverlay();
                btnGenerate.disabled = false;
                noReport.classList.remove('hidden');
                noReport.innerHTML = `<div class="error-message">Polling error: ${escapeHtml(err.message)}</div>`;
                return;
            }
        }
    }

    function renderReport(report) {
        lastReport = report;
        reportArea.classList.remove('hidden');
        noReport.classList.add('hidden');
        btnSaveJson.classList.remove('hidden');
        btnSaveHtml.classList.remove('hidden');

        renderSummaryCards(report);
        renderCpuChart(report);
        renderMemoryChart(report);
        renderDiskChart(report);
        renderStatsTable(report);
        renderDiskTable(report);
        renderAlertsTable(report);
        renderAlertTimeline(report);
        renderAlertDetailTable(report);
    }

    function renderSummaryCards(r) {
        const duration = r.durationSeconds < 1 ? `${(r.durationSeconds * 1000).toFixed(0)}ms` : `${r.durationSeconds.toFixed(1)}s`;
        const cards = [
            { value: r.snapshotCount, label: 'Snapshots' },
            { value: formatTimeSpan(r.fromUtc, r.toUtc), label: 'Time Span' },
            { value: `${r.cpuStats?.avg ?? '-'}%`, label: 'Avg CPU' },
            { value: `${r.memoryStats?.avg ?? '-'}%`, label: 'Avg Memory' },
            { value: r.uptime?.uptimeDays ? `${r.uptime.uptimeDays.toFixed(1)}d` : '-', label: 'Uptime' },
            { value: r.totalAlerts, label: 'Total Alerts' },
            { value: duration, label: 'Job Duration' }
        ];

        document.getElementById('summaryCards').innerHTML = cards.map(c =>
            `<div class="summary-card"><div class="card-value">${c.value}</div><div class="card-label">${c.label}</div></div>`
        ).join('');
    }

    function renderCpuChart(r) {
        if (cpuChart) cpuChart.destroy();
        const ctx = document.getElementById('cpuChart').getContext('2d');
        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        const gridColor = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
        const textColor = isDark ? '#d4d4d8' : '#475569';

        cpuChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: r.cpuHistory.map(p => formatTime(p.timestamp)),
                datasets: [{
                    label: 'CPU %',
                    data: r.cpuHistory.map(p => p.value),
                    borderColor: '#3b82f6',
                    backgroundColor: 'rgba(59,130,246,0.1)',
                    fill: true,
                    tension: 0.3,
                    pointRadius: r.cpuHistory.length > 200 ? 0 : 2,
                    borderWidth: 1.5
                }]
            },
            options: chartOptions(gridColor, textColor, '%', [
                { value: 85, color: '#d97706', label: 'Warning (85%)' },
                { value: 100, color: '#dc2626', label: 'Critical (100%)' }
            ])
        });
    }

    function renderMemoryChart(r) {
        if (memChart) memChart.destroy();
        const ctx = document.getElementById('memoryChart').getContext('2d');
        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        const gridColor = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
        const textColor = isDark ? '#d4d4d8' : '#475569';

        memChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: r.memoryHistory.map(p => formatTime(p.timestamp)),
                datasets: [{
                    label: 'Memory %',
                    data: r.memoryHistory.map(p => p.value),
                    borderColor: '#8b5cf6',
                    backgroundColor: 'rgba(139,92,246,0.1)',
                    fill: true,
                    tension: 0.3,
                    pointRadius: r.memoryHistory.length > 200 ? 0 : 2,
                    borderWidth: 1.5
                }]
            },
            options: chartOptions(gridColor, textColor, '%', [
                { value: 90, color: '#d97706', label: 'Warning (90%)' },
                { value: 95, color: '#dc2626', label: 'Critical (95%)' }
            ])
        });
    }

    function renderDiskChart(r) {
        if (diskChart) diskChart.destroy();
        if (!r.diskHistory || r.diskHistory.length === 0) {
            document.getElementById('diskChart').parentElement.innerHTML = '<div class="no-data">No disk data available</div>';
            return;
        }

        const ctx = document.getElementById('diskChart').getContext('2d');
        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        const gridColor = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
        const textColor = isDark ? '#d4d4d8' : '#475569';
        const colors = ['#06b6d4', '#f59e0b', '#10b981', '#ef4444', '#8b5cf6', '#ec4899'];

        const longest = r.diskHistory.reduce((a, b) => a.usedPercent.length >= b.usedPercent.length ? a : b);

        diskChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: longest.usedPercent.map(p => formatTime(p.timestamp)),
                datasets: r.diskHistory.map((dg, i) => ({
                    label: `${dg.drive} Used %`,
                    data: dg.usedPercent.map(p => p.value),
                    borderColor: colors[i % colors.length],
                    backgroundColor: 'transparent',
                    tension: 0.3,
                    pointRadius: dg.usedPercent.length > 200 ? 0 : 2,
                    borderWidth: 1.5
                }))
            },
            options: chartOptions(gridColor, textColor, '%', [
                { value: 85, color: '#d97706', label: 'Warning (85%)' },
                { value: 95, color: '#dc2626', label: 'Critical (95%)' }
            ])
        });
    }

    function chartOptions(gridColor, textColor, suffix, thresholds) {
        const annotations = {};
        thresholds.forEach((t, i) => {
            annotations[`threshold_${i}`] = {
                type: 'line',
                yMin: t.value,
                yMax: t.value,
                borderColor: t.color,
                borderWidth: 1.5,
                borderDash: [6, 4],
                label: {
                    display: true,
                    content: t.label,
                    position: 'end',
                    font: { size: 10 },
                    backgroundColor: 'transparent',
                    color: t.color
                }
            };
        });

        const hasAnnotationPlugin = typeof Chart !== 'undefined' && Chart.registry && Chart.registry.plugins && Chart.registry.plugins.get('annotation');

        return {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            scales: {
                x: {
                    ticks: {
                        color: textColor,
                        maxTicksLimit: 20,
                        maxRotation: 45,
                        font: { size: 10 }
                    },
                    grid: { color: gridColor }
                },
                y: {
                    min: 0,
                    max: 100,
                    ticks: {
                        color: textColor,
                        callback: v => v + suffix,
                        font: { size: 10 }
                    },
                    grid: { color: gridColor }
                }
            },
            plugins: {
                legend: { labels: { color: textColor, font: { size: 11 } } },
                tooltip: { callbacks: { label: ctx => `${ctx.dataset.label}: ${ctx.parsed.y}${suffix}` } },
                ...(hasAnnotationPlugin ? { annotation: { annotations } } : {})
            }
        };
    }

    function renderStatsTable(r) {
        const area = document.getElementById('statsTableArea');
        const rows = [
            { metric: 'CPU', stats: r.cpuStats },
            { metric: 'Memory', stats: r.memoryStats }
        ];

        area.innerHTML = `
            <table class="data-table">
                <thead><tr><th>Metric</th><th>Min</th><th>Max</th><th>Avg</th><th>P95</th></tr></thead>
                <tbody>
                    ${rows.map(r => `<tr>
                        <td><strong>${r.metric}</strong></td>
                        <td>${r.stats?.min ?? '-'}%</td>
                        <td>${r.stats?.max ?? '-'}%</td>
                        <td>${r.stats?.avg ?? '-'}%</td>
                        <td>${r.stats?.p95 ?? '-'}%</td>
                    </tr>`).join('')}
                </tbody>
            </table>`;
    }

    function renderDiskTable(r) {
        const area = document.getElementById('diskTableArea');
        if (!r.diskSpaceSummary || r.diskSpaceSummary.length === 0) {
            area.innerHTML = '<div class="no-data">No disk data</div>';
            return;
        }

        area.innerHTML = `
            <table class="data-table">
                <thead><tr><th>Drive</th><th>Total (GB)</th><th>Available (GB)</th><th>Used %</th></tr></thead>
                <tbody>
                    ${r.diskSpaceSummary.map(d => `<tr>
                        <td><strong>${escapeHtml(d.drive)}</strong></td>
                        <td>${d.totalGB.toFixed(1)}</td>
                        <td>${d.latestAvailableGB.toFixed(1)}</td>
                        <td class="${d.latestUsedPercent > 90 ? 'severity-error' : d.latestUsedPercent > 80 ? 'severity-warning' : ''}">${d.latestUsedPercent.toFixed(1)}%</td>
                    </tr>`).join('')}
                </tbody>
            </table>`;
    }

    function renderAlertsTable(r) {
        const area = document.getElementById('alertTableArea');
        if (!r.alertSummary || r.alertSummary.length === 0) {
            area.innerHTML = '<div class="no-data">No alerts in this period</div>';
            return;
        }

        area.innerHTML = `
            <table class="data-table">
                <thead><tr><th>Message</th><th>Severity</th><th>Count</th><th>First Seen</th><th>Last Seen</th></tr></thead>
                <tbody>
                    ${r.alertSummary.map(a => `<tr>
                        <td style="max-width:500px;overflow:hidden;text-overflow:ellipsis" title="${escapeHtml(a.message)}">${escapeHtml(a.message)}</td>
                        <td class="${severityClass(a.severity)}">${escapeHtml(a.severity)}</td>
                        <td><strong>${a.count}</strong></td>
                        <td>${formatDateTime(a.firstSeen)}</td>
                        <td>${formatDateTime(a.lastSeen)}</td>
                    </tr>`).join('')}
                </tbody>
            </table>`;
    }

    function renderAlertTimeline(r) {
        alertTimelineCharts.forEach(c => c.destroy());
        alertTimelineCharts = [];

        const area = document.getElementById('alertTimelineArea');
        if (!r.alertTimeline || r.alertTimeline.length === 0) {
            area.innerHTML = '<div class="no-data">No alert timeline data</div>';
            return;
        }

        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        const gridColor = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
        const textColor = isDark ? '#d4d4d8' : '#475569';

        const lineColors = [
            '#ef4444', '#f59e0b', '#3b82f6', '#8b5cf6', '#10b981',
            '#f97316', '#ec4899', '#06b6d4', '#84cc16', '#6366f1',
            '#14b8a6', '#e11d48', '#a855f7', '#0ea5e9', '#eab308'
        ];

        const allTimestamps = new Set();
        r.alertTimeline.forEach(g => g.occurrences.forEach(o => allTimestamps.add(o.timestamp)));
        const sortedTimestamps = [...allTimestamps].sort();
        const labels = sortedTimestamps.map(t => formatTime(t));

        const datasets = r.alertTimeline.map((group, idx) => {
            const shortLabel = group.label.length > 50 ? group.label.substring(0, 47) + '...' : group.label;
            const total = group.occurrences.reduce((s, o) => s + o.value, 0);
            const occMap = {};
            group.occurrences.forEach(o => { occMap[o.timestamp] = o.value; });
            const data = sortedTimestamps.map(t => occMap[t] || 0);
            const color = lineColors[idx % lineColors.length];

            return {
                label: `${shortLabel} (${total})`,
                data,
                borderColor: color,
                backgroundColor: color + '18',
                fill: false,
                tension: 0.3,
                pointRadius: sortedTimestamps.length > 200 ? 0 : 2,
                borderWidth: 2
            };
        });

        const chartHeight = Math.max(250, Math.min(400, 200 + datasets.length * 20));
        area.innerHTML = `<div style="position:relative;height:${chartHeight}px"><canvas id="alertTimelineChart"></canvas></div>`;

        const canvas = document.getElementById('alertTimelineChart');
        if (!canvas) return;

        const maxVal = Math.max(1, ...datasets.flatMap(ds => ds.data));
        const chart = new Chart(canvas.getContext('2d'), {
            type: 'line',
            data: { labels, datasets },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                scales: {
                    x: {
                        ticks: { color: textColor, maxTicksLimit: 20, maxRotation: 45, font: { size: 10 } },
                        grid: { color: gridColor }
                    },
                    y: {
                        min: 0,
                        suggestedMax: maxVal + 1,
                        ticks: { color: textColor, stepSize: maxVal <= 10 ? 1 : undefined, font: { size: 10 } },
                        grid: { color: gridColor }
                    }
                },
                plugins: {
                    legend: {
                        display: true,
                        position: 'bottom',
                        labels: { color: textColor, font: { size: 10 }, boxWidth: 12, padding: 10, usePointStyle: true }
                    },
                    tooltip: {
                        callbacks: {
                            label: ctx => `${ctx.dataset.label}: ${ctx.parsed.y} occurrence(s)`
                        }
                    }
                }
            }
        });
        alertTimelineCharts.push(chart);
    }

    function renderAlertDetailTable(r) {
        const area = document.getElementById('alertDetailArea');
        if (!r.alertDetails || r.alertDetails.length === 0) {
            area.innerHTML = '<div class="no-data">No individual alert records in this period</div>';
            return;
        }

        area.innerHTML = `
            <div style="margin-bottom:0.5rem;font-size:0.85rem;color:var(--text-muted)">${r.alertDetails.length} alert records</div>
            <div style="max-height:500px;overflow-y:auto">
            <table class="data-table">
                <thead><tr><th>Timestamp</th><th>Severity</th><th>Category</th><th>Message</th></tr></thead>
                <tbody>
                    ${r.alertDetails.map(a => `<tr>
                        <td style="white-space:nowrap">${formatDateTime(a.timestamp)}</td>
                        <td class="${severityClass(a.severity)}">${escapeHtml(a.severity)}</td>
                        <td>${escapeHtml(a.category)}</td>
                        <td style="max-width:500px;overflow:hidden;text-overflow:ellipsis" title="${escapeHtml(a.details || a.message)}">${escapeHtml(a.message)}</td>
                    </tr>`).join('')}
                </tbody>
            </table>
            </div>`;
    }

    function saveReportAsJson() {
        if (!lastReport) return;
        const pad = n => String(n).padStart(2, '0');
        const now = new Date();
        const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}`;
        const filename = `${lastReport.serverName}_analysis_${stamp}.json`;
        downloadFile(filename, JSON.stringify(lastReport, null, 2), 'application/json');
    }

    function saveReportAsHtml() {
        if (!lastReport) return;
        const r = lastReport;
        const pad = n => String(n).padStart(2, '0');
        const now = new Date();
        const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}`;
        const filename = `${r.serverName}_analysis_${stamp}.html`;
        const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

        const cpuImg = captureChartImage('cpuChart');
        const memImg = captureChartImage('memoryChart');
        const diskImg = captureChartImage('diskChart');
        const alertTimelineImg = captureChartImage('alertTimelineChart');

        const duration = r.durationSeconds < 1 ? `${(r.durationSeconds * 1000).toFixed(0)}ms` : `${r.durationSeconds.toFixed(1)}s`;
        const summaryCards = [
            { value: r.snapshotCount, label: 'Snapshots' },
            { value: formatTimeSpan(r.fromUtc, r.toUtc), label: 'Time Span' },
            { value: `${r.cpuStats?.avg ?? '-'}%`, label: 'Avg CPU' },
            { value: `${r.memoryStats?.avg ?? '-'}%`, label: 'Avg Memory' },
            { value: r.uptime?.uptimeDays ? `${r.uptime.uptimeDays.toFixed(1)}d` : '-', label: 'Uptime' },
            { value: r.totalAlerts, label: 'Total Alerts' },
            { value: duration, label: 'Job Duration' }
        ];

        const bg = isDark ? '#0a0a0a' : '#f8fafc';
        const bgCard = isDark ? '#111' : '#fff';
        const bgHeader = isDark ? '#1a1a1a' : '#f1f5f9';
        const textPrimary = isDark ? '#f8fafc' : '#0f172a';
        const textSecondary = isDark ? '#e4e4e7' : '#475569';
        const textMuted = isDark ? '#a1a1aa' : '#94a3b8';
        const border = isDark ? '#27272a' : '#cbd5e1';
        const accent = isDark ? '#60a5fa' : '#0369a1';
        const errorColor = isDark ? '#f87171' : '#dc2626';
        const warningColor = isDark ? '#fbbf24' : '#d97706';

        const statsRows = [
            { metric: 'CPU', stats: r.cpuStats },
            { metric: 'Memory', stats: r.memoryStats }
        ];

        const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Analysis Report - ${escapeHtml(r.serverName)}</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: ${bg}; color: ${textPrimary}; padding: 1.5rem; }
.container { max-width: 1100px; margin: 0 auto; }
h1 { font-size: 1.5rem; margin-bottom: 0.3rem; color: ${accent}; }
.subtitle { color: ${textMuted}; font-size: 0.85rem; margin-bottom: 1.5rem; }
.summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 0.75rem; margin-bottom: 1.5rem; }
.card { background: ${bgCard}; border: 1px solid ${border}; border-radius: 6px; padding: 0.9rem; text-align: center; }
.card-value { font-size: 1.5rem; font-weight: 700; color: ${textPrimary}; }
.card-label { font-size: 0.8rem; color: ${textMuted}; margin-top: 0.2rem; }
.panel { background: ${bgCard}; border: 1px solid ${border}; border-radius: 8px; margin-bottom: 1.2rem; overflow: hidden; }
.panel-header { padding: 0.7rem 1rem; background: ${bgHeader}; border-bottom: 1px solid ${border}; font-weight: 600; font-size: 0.95rem; }
.panel-body { padding: 1rem; }
.chart-img { width: 100%; height: auto; display: block; border-radius: 4px; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid ${border}; font-size: 0.9rem; }
th { background: ${bgHeader}; font-weight: 600; color: ${textMuted}; font-size: 0.82rem; }
.sev-error { color: ${errorColor}; font-weight: 600; }
.sev-warning { color: ${warningColor}; font-weight: 600; }
.sev-info { color: ${accent}; font-weight: 600; }
.footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid ${border}; color: ${textMuted}; font-size: 0.75rem; text-align: center; }
@media print { body { padding: 0.5rem; } .panel { break-inside: avoid; } }
</style>
</head>
<body>
<div class="container">
<h1>📊 Snapshot Analysis: ${escapeHtml(r.serverName)}</h1>
<div class="subtitle">${formatDateTime(r.fromUtc)} &mdash; ${formatDateTime(r.toUtc)} &nbsp;|&nbsp; Generated ${formatDateTime(now.toISOString())}</div>

<div class="summary-cards">
${summaryCards.map(c => `<div class="card"><div class="card-value">${c.value}</div><div class="card-label">${c.label}</div></div>`).join('\n')}
</div>

${cpuImg ? `<div class="panel"><div class="panel-header">🖥️ CPU Usage Over Time</div><div class="panel-body"><img class="chart-img" src="${cpuImg}" alt="CPU chart"></div></div>` : ''}

${memImg ? `<div class="panel"><div class="panel-header">🧠 Memory Usage Over Time</div><div class="panel-body"><img class="chart-img" src="${memImg}" alt="Memory chart"></div></div>` : ''}

${diskImg ? `<div class="panel"><div class="panel-header">💾 Disk Usage Over Time</div><div class="panel-body"><img class="chart-img" src="${diskImg}" alt="Disk chart"></div></div>` : ''}

<div class="panel">
<div class="panel-header">📈 Statistics</div>
<div class="panel-body">
<table>
<thead><tr><th>Metric</th><th>Min</th><th>Max</th><th>Avg</th><th>P95</th></tr></thead>
<tbody>
${statsRows.map(s => `<tr><td><strong>${s.metric}</strong></td><td>${s.stats?.min ?? '-'}%</td><td>${s.stats?.max ?? '-'}%</td><td>${s.stats?.avg ?? '-'}%</td><td>${s.stats?.p95 ?? '-'}%</td></tr>`).join('\n')}
</tbody>
</table>
</div>
</div>

${r.diskSpaceSummary && r.diskSpaceSummary.length > 0 ? `<div class="panel">
<div class="panel-header">💽 Disk Space Summary</div>
<div class="panel-body">
<table>
<thead><tr><th>Drive</th><th>Total (GB)</th><th>Available (GB)</th><th>Used %</th></tr></thead>
<tbody>
${r.diskSpaceSummary.map(d => `<tr><td><strong>${escapeHtml(d.drive)}</strong></td><td>${d.totalGB.toFixed(1)}</td><td>${d.latestAvailableGB.toFixed(1)}</td><td class="${d.latestUsedPercent > 90 ? 'sev-error' : d.latestUsedPercent > 80 ? 'sev-warning' : ''}">${d.latestUsedPercent.toFixed(1)}%</td></tr>`).join('\n')}
</tbody>
</table>
</div>
</div>` : ''}

${r.alertSummary && r.alertSummary.length > 0 ? `<div class="panel">
<div class="panel-header">🚨 Alert Summary (${r.totalAlerts} total)</div>
<div class="panel-body">
<table>
<thead><tr><th>Message</th><th>Severity</th><th>Count</th><th>First Seen</th><th>Last Seen</th></tr></thead>
<tbody>
${r.alertSummary.map(a => {
    let cls = '';
    const sv = (a.severity || '').toLowerCase();
    if (sv === 'error' || sv === 'critical') cls = 'sev-error';
    else if (sv === 'warning') cls = 'sev-warning';
    else cls = 'sev-info';
    return `<tr><td>${escapeHtml(a.message)}</td><td class="${cls}">${escapeHtml(a.severity)}</td><td><strong>${a.count}</strong></td><td>${formatDateTime(a.firstSeen)}</td><td>${formatDateTime(a.lastSeen)}</td></tr>`;
}).join('\n')}
</tbody>
</table>
</div>
</div>` : '<div class="panel"><div class="panel-header">🚨 Alert Summary</div><div class="panel-body" style="text-align:center;color:' + textMuted + '">No alerts in this period</div></div>'}

${alertTimelineImg ? `<div class="panel">
<div class="panel-header">📉 Alerts Over Time</div>
<div class="panel-body"><img class="chart-img" src="${alertTimelineImg}" alt="Alert timeline"></div>
</div>` : ''}

${r.alertDetails && r.alertDetails.length > 0 ? `<div class="panel">
<div class="panel-header">📋 Complete Alert Log (${r.alertDetails.length} records)</div>
<div class="panel-body">
<table>
<thead><tr><th>Timestamp</th><th>Severity</th><th>Category</th><th>Message</th></tr></thead>
<tbody>
${r.alertDetails.map(a => {
    let cls = '';
    const sv = (a.severity || '').toLowerCase();
    if (sv === 'error' || sv === 'critical') cls = 'sev-error';
    else if (sv === 'warning') cls = 'sev-warning';
    else cls = 'sev-info';
    return `<tr><td style="white-space:nowrap">${formatDateTime(a.timestamp)}</td><td class="${cls}">${escapeHtml(a.severity)}</td><td>${escapeHtml(a.category)}</td><td>${escapeHtml(a.message)}</td></tr>`;
}).join('\n')}
</tbody>
</table>
</div>
</div>` : ''}

<div class="footer">ServerMonitor Dashboard &mdash; Snapshot Analysis Report &mdash; ${r.snapshotCount} snapshots analyzed in ${duration}</div>
</div>
</body>
</html>`;

        downloadFile(filename, html, 'text/html');
    }

    function captureChartImage(canvasId) {
        const canvas = document.getElementById(canvasId);
        if (!canvas || canvas.width === 0) return null;
        try {
            return canvas.toDataURL('image/png');
        } catch { return null; }
    }

    function downloadFile(filename, content, mimeType) {
        const blob = new Blob([content], { type: mimeType });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    function showOverlay() {
        progressEl.textContent = '';
        overlay.classList.add('visible');
    }

    function hideOverlay() {
        overlay.classList.remove('visible');
    }

    function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

    function escapeHtml(str) {
        if (!str) return '';
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function formatTime(ts) {
        const d = new Date(ts);
        const pad = n => String(n).padStart(2, '0');
        return `${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    function formatDateTime(ts) {
        if (!ts) return '-';
        const d = new Date(ts);
        const pad = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    function formatTimeSpan(from, to) {
        const ms = new Date(to) - new Date(from);
        const hours = Math.floor(ms / 3600000);
        const mins = Math.floor((ms % 3600000) / 60000);
        if (hours > 24) return `${(hours / 24).toFixed(1)}d`;
        if (hours > 0) return `${hours}h ${mins}m`;
        return `${mins}m`;
    }

    function severityClass(sev) {
        if (!sev) return '';
        const s = sev.toLowerCase();
        if (s === 'error' || s === 'critical') return 'severity-error';
        if (s === 'warning') return 'severity-warning';
        return 'severity-info';
    }
})();
