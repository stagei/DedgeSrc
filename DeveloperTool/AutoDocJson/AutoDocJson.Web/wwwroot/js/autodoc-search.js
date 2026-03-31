// AutoDocJson Search - controls-bar + query-builder + panel results + IndexedDB
// Layout follows GenericLogHandler patterns.

(function () {
    'use strict';

    function _t(key, fallback) {
        if (typeof DedgeAuth !== 'undefined' && typeof DedgeAuth.t === 'function') {
            return DedgeAuth.t(key, fallback);
        }
        return fallback;
    }

    let debounceTimer = null;
    let availableFields = null;
    let currentResults = null;
    let currentQuery = null;

    // Base path for API and page URLs (handles IIS virtual directory deployment)
    function basePath() {
        return (window.__basePath || '/').replace(/\/$/, '');
    }

    // ── Keyboard shortcut (Ctrl+K) ─────────────────────────────────────
    document.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
            e.preventDefault();
            const input = document.getElementById('search-input');
            if (input) { input.focus(); input.select(); }
        }
        if (e.key === 'Escape') {
            hideDropdown();
        }
    });

    // ── Wire up controls on DOMContentLoaded ───────────────────────────
    document.addEventListener('DOMContentLoaded', function () {
        const input = document.getElementById('search-input');
        if (input) {
            input.addEventListener('input', function () {
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => quickSearch(this.value), 300);
            });
            input.addEventListener('keydown', function (e) {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    runSimpleSearch();
                }
            });
        }

        // Type preset buttons
        document.querySelectorAll('#type-presets .btn-preset').forEach(btn => {
            btn.addEventListener('click', function () {
                const type = this.dataset.type;
                if (type === 'all') {
                    document.querySelectorAll('#type-presets .btn-preset').forEach(b => b.classList.remove('active'));
                    this.classList.add('active');
                } else {
                    document.querySelector('#type-presets .btn-preset[data-type="all"]')?.classList.remove('active');
                    this.classList.toggle('active');
                    const anyActive = document.querySelectorAll('#type-presets .btn-preset.active:not([data-type="all"])').length > 0;
                    if (!anyActive) {
                        document.querySelector('#type-presets .btn-preset[data-type="all"]')?.classList.add('active');
                    }
                }
            });
        });

        // Close dropdowns on outside click
        document.addEventListener('click', function (e) {
            if (!e.target.closest('#search-container')) hideDropdown();
            if (!e.target.closest('.search-history-container')) {
                const dd = document.getElementById('search-history-dropdown');
                if (dd) dd.style.display = 'none';
            }
        });

        // Load field options for the field filter dropdown
        loadFieldOptions();
    });

    // ── Quick search (instant dropdown while typing) ───────────────────
    function quickSearch(query) {
        query = query.trim();
        if (query.length < 2) { hideDropdown(); return; }

        const params = buildSearchParams(query);
        fetch(basePath() + '/api/search?' + params.toString())
            .then(r => r.json())
            .then(results => {
                const dropdown = document.getElementById('search-dropdown');
                if (!dropdown) return;
                if (results.length === 0) {
                    dropdown.innerHTML = '<div class="search-dd-empty">' + _t('search.noDropdownResults', 'No results found') + '</div>';
                    dropdown.style.display = 'block';
                    return;
                }

                const shown = results.slice(0, 8);
                let html = shown.map(r => {
                    const matchedIn = r.matches.map(m => m.field).filter((v, i, a) => a.indexOf(v) === i).join(', ');
                    return `<a class="search-dd-item" href="${basePath()}/Doc?file=${encodeURIComponent(r.jsonFile)}">
                        <span class="search-dd-type type-${r.type.toLowerCase()}">${r.type}</span>
                        <span class="search-dd-name">${escHtml(r.fileName)}</span>
                        <span class="search-dd-match">${escHtml(matchedIn)}</span>
                    </a>`;
                }).join('');

                if (results.length > 8) {
                    html += `<a class="search-dd-more" href="javascript:void(0)" onclick="runSimpleSearch()">
                        ${_t('search.showAllResults', 'Show all ' + results.length + ' results →').replace('{count}', results.length)}
                    </a>`;
                }
                dropdown.innerHTML = html;
                dropdown.style.display = 'block';
            })
            .catch(() => hideDropdown());
    }

    function hideDropdown() {
        const dd = document.getElementById('search-dropdown');
        if (dd) dd.style.display = 'none';
    }

    // ── Build search params from controls bar ──────────────────────────
    function buildSearchParams(query) {
        const params = new URLSearchParams();
        if (query) params.append('q', query);

        const selectedTypes = getSelectedTypes();
        if (selectedTypes.length > 0) params.append('types', selectedTypes.join(','));

        const fieldFilter = document.getElementById('field-filter');
        if (fieldFilter && fieldFilter.value) {
            params.append('elements[0].field', fieldFilter.value);
            params.append('elements[0].terms', query || '');
        }

        return params;
    }

    function getSelectedTypes() {
        const allBtn = document.querySelector('#type-presets .btn-preset[data-type="all"]');
        if (allBtn && allBtn.classList.contains('active')) return [];
        const types = [];
        document.querySelectorAll('#type-presets .btn-preset.active').forEach(btn => {
            if (btn.dataset.type !== 'all') types.push(btn.dataset.type);
        });
        return types;
    }

    // ── Simple search (Enter or Search button) ─────────────────────────
    window.runSimpleSearch = function () {
        const input = document.getElementById('search-input');
        if (!input) return;
        const val = input.value.trim();
        if (!val) return;
        hideDropdown();

        const params = buildSearchParams(val);
        currentQuery = { q: val, types: getSelectedTypes() };

        fetch(basePath() + '/api/search?' + params.toString())
            .then(r => r.json())
            .then(results => {
                currentResults = results;
                showSearchResults(results);
                saveToHistory(currentQuery, results.length);
            });
    };

    // ── initSearchPage: used from Search.cshtml ────────────────────────
    window.initSearchPage = function (query) {
        currentQuery = { q: query };
        const params = buildSearchParams(query);
        fetch(basePath() + '/api/search?' + params.toString())
            .then(r => r.json())
            .then(results => {
                currentResults = results;
                showSearchResults(results);
                saveToHistory({ q: query }, results.length);
            });
    };

    // ── Show results in panel ──────────────────────────────────────────
    function showSearchResults(results) {
        const wrapper = document.getElementById('search-results-wrapper');
        const container = document.getElementById('search-results');
        const countEl = document.getElementById('results-count');
        const emptyEl = document.getElementById('results-empty');
        if (!wrapper || !container) return;

        wrapper.style.display = '';

        if (results.length === 0) {
            if (countEl) countEl.textContent = '0 ' + _t('search.results', 'results').toLowerCase();
            container.innerHTML = '';
            if (emptyEl) {
                emptyEl.style.display = '';
                emptyEl.querySelector('.empty-state-title').textContent = _t('search.noResults', 'No Results');
                emptyEl.querySelector('.empty-state-message').textContent = _t('search.noResultsMessage', 'No matching documentation files found. Try different search terms.');
            }
            return;
        }

        if (emptyEl) emptyEl.style.display = 'none';
        if (countEl) countEl.textContent = results.length + ' ' + (results.length !== 1 ? _t('search.resultPlural', 'results') : _t('search.resultSingular', 'result'));

        let html = '<table class="data-table"><thead><tr>' +
            '<th style="width: 70px;">' + _t('table.type', 'Type') + '</th>' +
            '<th style="width: 220px;">' + _t('table.file', 'File') + '</th>' +
            '<th>' + _t('table.description', 'Description') + '</th>' +
            '<th style="width: 180px;">' + _t('search.matchedIn', 'Matched In') + '</th>' +
            '</tr></thead><tbody>';

        for (const r of results) {
            const matchedIn = r.matches.map(m => m.field).filter((v, i, a) => a.indexOf(v) === i).join(', ');
            const desc = r.description || '<span style="color:var(--text-muted)">' + _t('search.noDescription', '(no description)') + '</span>';
            html += `<tr onclick="window.location='${basePath()}/Doc?file=${encodeURIComponent(r.jsonFile)}'">
                <td><span class="type-badge type-${r.type.toLowerCase()}">${r.type}</span></td>
                <td><a href="${basePath()}/Doc?file=${encodeURIComponent(r.jsonFile)}">${escHtml(r.fileName)}</a></td>
                <td class="desc-cell">${desc}</td>
                <td class="match-cell">${escHtml(matchedIn)}</td>
            </tr>`;
        }
        html += '</tbody></table>';
        container.innerHTML = html;
    }

    window.hideSearchResults = function () {
        const wrapper = document.getElementById('search-results-wrapper');
        if (wrapper) wrapper.style.display = 'none';
    };

    // ── Advanced search - query builder ────────────────────────────────
    window.toggleAdvanced = function () {
        const panel = document.getElementById('advanced-panel');
        if (!panel) return;
        const visible = panel.style.display !== 'none';
        panel.style.display = visible ? 'none' : '';
        const btn = document.getElementById('btn-toggle-advanced');
        if (btn) btn.classList.toggle('active', !visible);
        if (!visible && !document.querySelector('.query-row')) addFilterRow();
        if (!visible) loadFieldOptions();
    };

    window.addFilterRow = function () {
        const container = document.getElementById('advanced-filters');
        if (!container) return;
        const idx = container.querySelectorAll('.query-row').length;
        const row = document.createElement('div');
        row.className = 'query-row';
        row.innerHTML = `
            <span class="query-row-num">${idx + 1}</span>
            <select class="field-select" data-idx="${idx}">
                <option value="">${_t('search.allFields', 'All fields')}</option>
            </select>
            <input type="text" class="value-input" placeholder="${_t('search.termsPlaceholder', 'Search terms (comma-separated for AND)')}" />
            <button class="remove-row-btn" onclick="removeFilterRow(this)" title="${_t('search.remove', 'Remove')}">×</button>
        `;
        container.appendChild(row);
        populateFieldSelect(row.querySelector('select'));
        updateRowNumbers();
    };

    window.removeFilterRow = function (btn) {
        btn.closest('.query-row').remove();
        updateRowNumbers();
    };

    function updateRowNumbers() {
        document.querySelectorAll('#advanced-filters .query-row').forEach((row, i) => {
            const num = row.querySelector('.query-row-num');
            if (num) num.textContent = i + 1;
            const sel = row.querySelector('.field-select');
            if (sel) sel.dataset.idx = i;
        });
    }

    window.clearAdvancedFilters = function () {
        const container = document.getElementById('advanced-filters');
        if (container) container.innerHTML = '';
        addFilterRow();
    };

    window.loadFieldOptions = function () {
        if (availableFields) {
            populateAllSelects();
            populateFieldFilter();
            return;
        }
        fetch(basePath() + '/api/search/fields')
            .then(r => r.json())
            .then(fields => {
                availableFields = fields;
                populateAllSelects();
                populateFieldFilter();
            })
            .catch(() => {});
    }

    function populateAllSelects() {
        document.querySelectorAll('.field-select').forEach(sel => populateFieldSelect(sel));
    }

    function populateFieldFilter() {
        const sel = document.getElementById('field-filter');
        if (!sel || !availableFields) return;
        const current = sel.value;
        while (sel.options.length > 1) sel.remove(1);
        sel.add(new Option('fileName', 'fileName'));
        sel.add(new Option('description', 'description'));
        for (const f of availableFields) {
            if (f !== 'fileName' && f !== 'description') {
                sel.add(new Option(f, f));
            }
        }
        sel.value = current;
    }

    function populateFieldSelect(sel) {
        if (!availableFields || !sel) return;
        const current = sel.value;
        while (sel.options.length > 1) sel.remove(1);

        const commonFields = ['fileName', 'description'];
        const metaFields = [];
        const contentFields = [];

        for (const f of availableFields) {
            if (commonFields.includes(f)) continue;
            if (f.startsWith('metadata.')) metaFields.push(f);
            else contentFields.push(f);
        }

        const grpCommon = document.createElement('optgroup');
        grpCommon.label = _t('search.commonFields', 'Common');
        commonFields.forEach(f => grpCommon.appendChild(new Option(f, f)));
        sel.appendChild(grpCommon);

        if (contentFields.length > 0) {
            const grpContent = document.createElement('optgroup');
            grpContent.label = _t('search.contentFields', 'Content');
            contentFields.forEach(f => grpContent.appendChild(new Option(f, f)));
            sel.appendChild(grpContent);
        }

        if (metaFields.length > 0) {
            const grpMeta = document.createElement('optgroup');
            grpMeta.label = _t('search.metadataFields', 'Metadata');
            metaFields.forEach(f => grpMeta.appendChild(new Option(f, f)));
            sel.appendChild(grpMeta);
        }

        sel.value = current;
    }

    window.runAdvancedSearch = function () {
        const selectedTypes = getSelectedTypes();
        const logic = document.querySelector('input[name="logic"]:checked')?.value || 'AND';

        const rows = document.querySelectorAll('.query-row');
        const params = new URLSearchParams();
        let hasTerms = false;

        rows.forEach((row, i) => {
            const field = row.querySelector('.field-select')?.value || '';
            const terms = row.querySelector('.value-input')?.value?.trim() || '';
            if (terms) {
                params.append(`elements[${i}].field`, field);
                params.append(`elements[${i}].terms`, terms);
                hasTerms = true;
            }
        });

        if (!hasTerms) return;
        if (selectedTypes.length > 0) params.append('types', selectedTypes.join(','));
        params.append('logic', logic);

        currentQuery = { elements: [], types: selectedTypes, logic };
        rows.forEach(row => {
            const field = row.querySelector('.field-select')?.value || '';
            const terms = row.querySelector('.value-input')?.value?.trim() || '';
            if (terms) currentQuery.elements.push({ field, terms });
        });

        fetch(basePath() + '/api/search?' + params.toString())
            .then(r => r.json())
            .then(results => {
                currentResults = results;
                showSearchResults(results);
                saveToHistory(currentQuery, results.length);
            });
    };

    // ── IndexedDB: saved/recent searches ───────────────────────────────
    const DB_NAME = 'AutoDocSearchDB';
    const DB_VERSION = 1;
    const STORE_NAME = 'searches';
    const MAX_ENTRIES = 50;

    function openDB() {
        return new Promise((resolve, reject) => {
            const req = indexedDB.open(DB_NAME, DB_VERSION);
            req.onupgradeneeded = function (e) {
                const db = e.target.result;
                if (!db.objectStoreNames.contains(STORE_NAME)) {
                    db.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
                }
            };
            req.onsuccess = () => resolve(req.result);
            req.onerror = () => reject(req.error);
        });
    }

    function buildLabel(query) {
        if (query.q) return query.q;
        if (query.simple) return query.simple;
        if (query.elements && query.elements.length > 0) {
            return query.elements.map(e =>
                (e.field ? `${e.field}: ` : '') + e.terms
            ).join(' + ');
        }
        return _t('search.label', 'search');
    }

    function saveToHistory(query, resultCount) {
        openDB().then(db => {
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);
            store.add({
                timestamp: new Date().toISOString(),
                label: buildLabel(query),
                query: query,
                resultCount: resultCount
            });
            const countReq = store.count();
            countReq.onsuccess = function () {
                if (countReq.result > MAX_ENTRIES) {
                    const cursorReq = store.openCursor();
                    let toDelete = countReq.result - MAX_ENTRIES;
                    cursorReq.onsuccess = function (e) {
                        const c = e.target.result;
                        if (c && toDelete > 0) {
                            c.delete();
                            toDelete--;
                            c.continue();
                        }
                    };
                }
            };
        }).catch(() => {});
    }

    window.saveCurrentSearch = function () {
        if (!currentQuery) return;
        const label = prompt(_t('search.labelPrompt', 'Label for this search:'), buildLabel(currentQuery));
        if (!label) return;
        openDB().then(db => {
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);
            store.add({
                timestamp: new Date().toISOString(),
                label: label,
                query: currentQuery,
                resultCount: currentResults ? currentResults.length : 0,
                saved: true
            });
        }).catch(() => {});
    };

    window.toggleSavedSearches = function () {
        const dd = document.getElementById('search-history-dropdown');
        if (!dd) return;
        if (dd.style.display !== 'none') { dd.style.display = 'none'; return; }

        openDB().then(db => {
            const tx = db.transaction(STORE_NAME, 'readonly');
            const store = tx.objectStore(STORE_NAME);
            const req = store.getAll();
            req.onsuccess = function () {
                const entries = req.result.reverse().slice(0, 15);
                if (entries.length === 0) {
                    dd.innerHTML = '<div class="search-history-empty">' + _t('search.noRecentSearches', 'No recent searches') + '</div>';
                } else {
                    dd.innerHTML = entries.map(e => {
                        const time = new Date(e.timestamp).toLocaleString();
                        const icon = e.saved ? '⭐' : '🕐';
                        return `<div class="search-history-item" onclick="replaySearch(${e.id})">
                            <span class="search-history-icon">${icon}</span>
                            <span class="search-history-text">${escHtml(e.label)}</span>
                            <span class="search-history-meta">${e.resultCount} · ${time}</span>
                        </div>`;
                    }).join('');
                    dd.innerHTML += '<div class="search-history-clear" onclick="clearSearchHistory()">' + _t('search.clearHistory', 'Clear History') + '</div>';
                }
                dd.style.display = 'block';
            };
        }).catch(() => {
            dd.innerHTML = '<div class="search-history-empty">' + _t('search.historyUnavailable', 'IndexedDB unavailable') + '</div>';
            dd.style.display = 'block';
        });
    };

    window.replaySearch = function (id) {
        const dd = document.getElementById('search-history-dropdown');
        if (dd) dd.style.display = 'none';

        openDB().then(db => {
            const tx = db.transaction(STORE_NAME, 'readonly');
            const store = tx.objectStore(STORE_NAME);
            const req = store.get(id);
            req.onsuccess = function () {
                if (!req.result) return;
                const q = req.result.query;
                if (q.q || q.simple) {
                    const input = document.getElementById('search-input');
                    if (input) input.value = q.q || q.simple;
                    runSimpleSearch();
                } else if (q.elements) {
                    // Replay advanced search
                    const panel = document.getElementById('advanced-panel');
                    if (panel && panel.style.display === 'none') toggleAdvanced();
                    clearAdvancedFilters();
                    const container = document.getElementById('advanced-filters');
                    if (!container) return;
                    container.innerHTML = '';
                    q.elements.forEach(el => {
                        addFilterRow();
                        const rows = container.querySelectorAll('.query-row');
                        const lastRow = rows[rows.length - 1];
                        if (lastRow) {
                            const fieldSel = lastRow.querySelector('.field-select');
                            const valueInput = lastRow.querySelector('.value-input');
                            if (fieldSel) fieldSel.value = el.field || '';
                            if (valueInput) valueInput.value = el.terms || '';
                        }
                    });
                    if (q.logic) {
                        const radio = document.querySelector(`input[name="logic"][value="${q.logic}"]`);
                        if (radio) radio.checked = true;
                    }
                    runAdvancedSearch();
                }
            };
        });
    };

    window.clearSearchHistory = function () {
        openDB().then(db => {
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);
            store.clear();
            const dd = document.getElementById('search-history-dropdown');
            if (dd) dd.innerHTML = '<div class="search-history-empty">' + _t('search.historyCleared', 'History cleared') + '</div>';
        }).catch(() => {});
    };

    function escHtml(str) {
        if (!str) return '';
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

})();
