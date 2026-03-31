/**
 * Analytics Page JavaScript
 * Renders charts using Chart.js
 */
(function() {
    'use strict';

    // Chart instances
    let volumeChart = null;
    let levelChart = null;
    let sourceChart = null;
    let computersChart = null;
    let errorRateChart = null;

    // Current time range in hours
    let currentHours = 24;

    // Chart.js default options
    const chartDefaults = {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                labels: {
                    color: getComputedStyle(document.documentElement).getPropertyValue('--text-primary').trim() || '#333'
                }
            }
        },
        scales: {
            x: {
                ticks: {
                    color: getComputedStyle(document.documentElement).getPropertyValue('--text-secondary').trim() || '#666'
                },
                grid: {
                    color: getComputedStyle(document.documentElement).getPropertyValue('--border-color').trim() || '#e0e0e0'
                }
            },
            y: {
                ticks: {
                    color: getComputedStyle(document.documentElement).getPropertyValue('--text-secondary').trim() || '#666'
                },
                grid: {
                    color: getComputedStyle(document.documentElement).getPropertyValue('--border-color').trim() || '#e0e0e0'
                }
            }
        }
    };

    /**
     * Initialize page
     */
    function init() {
        // Date preset buttons
        document.querySelectorAll('.date-preset').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.date-preset').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentHours = parseInt(btn.dataset.hours);
                loadAllCharts();
            });
        });

        // Initial load
        loadAllCharts();

        // Listen for theme changes
        document.addEventListener('themechange', () => {
            updateChartColors();
        });
    }

    /**
     * Load all charts
     */
    async function loadAllCharts() {
        document.getElementById('lastUpdated').textContent = 'Loading...';
        
        try {
            await Promise.all([
                loadVolumeChart(),
                loadLevelChart(),
                loadSourceChart(),
                loadComputersChart(),
                loadErrorRateChart()
            ]);
            
            document.getElementById('lastUpdated').textContent = 
                'Updated: ' + new Date().toLocaleTimeString();
        } catch (e) {
            console.error('Error loading charts:', e);
            Toast.error('Failed to load analytics data');
        }
    }

    /**
     * Load volume over time chart
     */
    async function loadVolumeChart() {
        const response = await Api.get('/api/Dashboard/trends?hours=' + currentHours);
        if (!response || !response.Success) return;

        const data = response.Data || [];
        const labels = data.map(d => {
            const date = new Date(d.Hour);
            if (currentHours <= 24) return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' ' +
                   date.toLocaleTimeString([], { hour: '2-digit' });
        });
        const values = data.map(d => d.LogCount);

        const ctx = document.getElementById('volumeChart').getContext('2d');
        
        if (volumeChart) volumeChart.destroy();
        
        volumeChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Log Entries',
                    data: values,
                    borderColor: '#3b82f6',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    fill: true,
                    tension: 0.3
                }]
            },
            options: {
                ...chartDefaults,
                plugins: {
                    ...chartDefaults.plugins,
                    title: {
                        display: false
                    }
                }
            }
        });
    }

    /**
     * Load log level distribution chart
     */
    async function loadLevelChart() {
        const response = await Api.get('/api/Logs/level-counts');
        if (!response || !response.Success) return;

        const data = response.Data || {};
        const labels = Object.keys(data);
        const values = Object.values(data);
        
        const colors = {
            'TRACE': '#94a3b8',
            'DEBUG': '#64748b',
            'INFO': '#3b82f6',
            'WARN': '#f59e0b',
            'ERROR': '#ef4444',
            'FATAL': '#dc2626'
        };

        const ctx = document.getElementById('levelChart').getContext('2d');
        
        if (levelChart) levelChart.destroy();
        
        levelChart = new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels: labels,
                datasets: [{
                    data: values,
                    backgroundColor: labels.map(l => colors[l] || '#999')
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'right'
                    }
                }
            }
        });
    }

    /**
     * Load logs by source type chart
     */
    async function loadSourceChart() {
        // Use search with grouping or statistics
        const response = await Api.get('/api/Logs/statistics');
        if (!response || !response.Success) return;

        const sources = response.Data?.TopSources || {};
        const labels = Object.keys(sources).slice(0, 8);
        const values = Object.values(sources).slice(0, 8);

        const ctx = document.getElementById('sourceChart').getContext('2d');
        
        if (sourceChart) sourceChart.destroy();
        
        sourceChart = new Chart(ctx, {
            type: 'pie',
            data: {
                labels: labels.length ? labels : ['No Data'],
                datasets: [{
                    data: values.length ? values : [1],
                    backgroundColor: [
                        '#3b82f6', '#10b981', '#f59e0b', '#ef4444',
                        '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'
                    ]
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'right'
                    }
                }
            }
        });
    }

    /**
     * Load top computers chart
     */
    async function loadComputersChart() {
        const response = await Api.get('/api/Logs/top-computers?limit=10');
        if (!response || !response.Success) return;

        const data = response.Data || [];
        const labels = data.map(d => d.ComputerName || 'Unknown');
        const values = data.map(d => d.TotalLogs || 0);

        const ctx = document.getElementById('computersChart').getContext('2d');
        
        if (computersChart) computersChart.destroy();
        
        computersChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Log Entries',
                    data: values,
                    backgroundColor: '#3b82f6'
                }]
            },
            options: {
                ...chartDefaults,
                indexAxis: 'y',
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    }

    /**
     * Load error rate trend chart
     */
    async function loadErrorRateChart() {
        const response = await Api.get('/api/Dashboard/trends?hours=' + currentHours);
        if (!response || !response.Success) return;

        const data = response.Data || [];
        const labels = data.map(d => {
            const date = new Date(d.Hour);
            if (currentHours <= 24) return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' ' +
                   date.toLocaleTimeString([], { hour: '2-digit' });
        });
        
        const errorCounts = data.map(d => d.ErrorCount);
        const warnCounts = data.map(d => Math.max(0, d.LogCount - d.ErrorCount));

        const ctx = document.getElementById('errorRateChart').getContext('2d');
        
        if (errorRateChart) errorRateChart.destroy();
        
        errorRateChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'Errors',
                        data: errorCounts,
                        borderColor: '#ef4444',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        fill: true,
                        tension: 0.3
                    },
                    {
                        label: 'Warnings',
                        data: warnCounts,
                        borderColor: '#f59e0b',
                        backgroundColor: 'rgba(245, 158, 11, 0.1)',
                        fill: true,
                        tension: 0.3
                    }
                ]
            },
            options: {
                ...chartDefaults,
                plugins: {
                    legend: {
                        position: 'top'
                    }
                }
            }
        });
    }

    /**
     * Update chart colors on theme change
     */
    function updateChartColors() {
        // Reload charts to pick up new theme colors
        loadAllCharts();
    }

    // Initialize on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
