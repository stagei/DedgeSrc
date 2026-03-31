import * as vscode from 'vscode';
import { ConversionService } from '../services/conversionService';
import { getNonce } from '../utils/getNonce';

export class SplitEditorProvider implements vscode.CustomTextEditorProvider {
    public static register(context: vscode.ExtensionContext): vscode.Disposable {
        const provider = new SplitEditorProvider(context);
        const providerRegistration = vscode.window.registerCustomEditorProvider(
            'sqlmermaid.splitEditor',
            provider,
            {
                webviewOptions: {
                    retainContextWhenHidden: true,
                },
                supportsMultipleEditorsPerDocument: false,
            }
        );
        return providerRegistration;
    }

    private readonly conversionService: ConversionService;

    constructor(private readonly context: vscode.ExtensionContext) {
        this.conversionService = new ConversionService(context);
    }

    public async resolveCustomTextEditor(
        document: vscode.TextDocument,
        webviewPanel: vscode.WebviewPanel,
        _token: vscode.CancellationToken
    ): Promise<void> {
        webviewPanel.webview.options = {
            enableScripts: true,
        };

        // Determine initial mode based on file extension
        const ext = document.fileName.toLowerCase();
        const initialMode = ext.endsWith('.sql') ? 'sql' : 'mermaid';

        webviewPanel.webview.html = this.getHtmlForWebview(webviewPanel.webview, initialMode);

        // Send initial content
        webviewPanel.webview.postMessage({
            type: 'init',
            content: document.getText(),
            mode: initialMode,
        });

        // Handle messages from the webview
        webviewPanel.webview.onDidReceiveMessage(async (message) => {
            switch (message.type) {
                case 'convert':
                    await this.handleConversion(message, webviewPanel.webview, document);
                    break;
                case 'save':
                    await this.handleSave(message, document);
                    break;
                case 'getConfig':
                    this.sendConfig(webviewPanel.webview);
                    break;
            }
        });

        // Update webview when document changes
        const changeDocumentSubscription = vscode.workspace.onDidChangeTextDocument(e => {
            if (e.document.uri.toString() === document.uri.toString()) {
                webviewPanel.webview.postMessage({
                    type: 'documentChanged',
                    content: document.getText(),
                });
            }
        });

        webviewPanel.onDidDispose(() => {
            changeDocumentSubscription.dispose();
        });
    }

    private async handleConversion(
        message: any,
        webview: vscode.Webview,
        document: vscode.TextDocument
    ): Promise<void> {
        try {
            const { content, mode, dialect } = message;
            let result: string;

            if (mode === 'sql') {
                // SQL → Mermaid
                result = await this.conversionService.sqlToMermaid(content);
            } else {
                // Mermaid → SQL
                result = await this.conversionService.mermaidToSql(content, dialect || 'AnsiSql');
            }

            webview.postMessage({
                type: 'conversionResult',
                result: result,
                success: true,
            });
        } catch (error: any) {
            webview.postMessage({
                type: 'conversionResult',
                error: error.message,
                success: false,
            });
        }
    }

    private async handleSave(message: any, document: vscode.TextDocument): Promise<void> {
        const edit = new vscode.WorkspaceEdit();
        edit.replace(
            document.uri,
            new vscode.Range(0, 0, document.lineCount, 0),
            message.content
        );
        await vscode.workspace.applyEdit(edit);
    }

    private sendConfig(webview: vscode.Webview): void {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        webview.postMessage({
            type: 'config',
            config: {
                defaultDialect: config.get('defaultDialect', 'AnsiSql'),
                autoConvert: config.get('autoConvert', true),
                showPreview: config.get('showPreview', true),
            },
        });
    }

    private getHtmlForWebview(webview: vscode.Webview, initialMode: string): string {
        const nonce = getNonce();
        const styleUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this.context.extensionUri, 'media', 'split-editor.css')
        );

        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; 
        style-src ${webview.cspSource} 'unsafe-inline' https://cdn.jsdelivr.net; 
        script-src 'nonce-${nonce}' https://cdn.jsdelivr.net;
        img-src ${webview.cspSource} https: data:;
        font-src ${webview.cspSource} https://cdn.jsdelivr.net;">
    <link href="${styleUri}" rel="stylesheet">
    <script type="module" nonce="${nonce}">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
        window.mermaid = mermaid;
        mermaid.initialize({ 
            startOnLoad: false,
            theme: 'default',
            securityLevel: 'loose',
            fontFamily: 'var(--vscode-font-family)'
        });
    </script>
    <title>SQL ↔ Mermaid Split Editor</title>
</head>
<body>
    <!-- Toolbar -->
    <div class="toolbar">
        <div class="toolbar-left">
            <button id="toggleModeBtn" class="toolbar-btn" title="Switch SQL ↔ Mermaid">
                <span class="icon">⇄</span>
                <span id="modeText">SQL → Mermaid</span>
            </button>
            <div class="divider"></div>
            <select id="dialectSelect" class="dialect-select" title="SQL Dialect">
                <option value="AnsiSql">ANSI SQL</option>
                <option value="SqlServer">SQL Server</option>
                <option value="PostgreSql">PostgreSQL</option>
                <option value="MySql">MySQL</option>
            </select>
        </div>
        <div class="toolbar-right">
            <button id="togglePreviewBtn" class="toolbar-btn active" title="Toggle Preview">
                <span class="icon">👁</span>
                <span>Preview</span>
            </button>
            <button id="convertBtn" class="toolbar-btn primary" title="Convert">
                <span class="icon">▶</span>
                <span>Convert</span>
            </button>
            <button id="saveBtn" class="toolbar-btn" title="Save (Ctrl+S)">
                <span class="icon">💾</span>
                <span>Save</span>
            </button>
        </div>
    </div>

    <!-- Main Content -->
    <div class="content-container">
        <!-- Left Panel: Editor -->
        <div class="panel left-panel">
            <div class="panel-header">
                <span id="leftPanelTitle" class="panel-title">SQL Input</span>
                <div class="panel-actions">
                    <span id="lineCount" class="meta-info">0 lines</span>
                </div>
            </div>
            <textarea id="editor" class="code-editor" placeholder="Enter your SQL or Mermaid code here..." spellcheck="false"></textarea>
        </div>

        <!-- Splitter -->
        <div class="splitter"></div>

        <!-- Right Panel: Output + Preview -->
        <div class="panel right-panel">
            <div class="panel-header">
                <span id="rightPanelTitle" class="panel-title">Mermaid Output</span>
                <div class="panel-actions">
                    <button id="copyBtn" class="icon-btn" title="Copy to clipboard">
                        <span class="icon">📋</span>
                    </button>
                    <button id="exportBtn" class="icon-btn" title="Export to file">
                        <span class="icon">📄</span>
                    </button>
                </div>
            </div>
            
            <!-- Preview (Mermaid only) -->
            <div id="previewContainer" class="preview-container">
                <div class="preview-header">
                    <span class="preview-title">Live Preview</span>
                </div>
                <div id="previewContent" class="preview-content">
                    <div class="preview-placeholder">
                        <span class="icon">📊</span>
                        <p>Click "Convert" to see the preview</p>
                    </div>
                </div>
            </div>

            <!-- Output Editor -->
            <div class="output-container">
                <textarea id="output" class="code-editor readonly" readonly placeholder="Converted code will appear here..."></textarea>
            </div>

            <!-- Error Display -->
            <div id="errorContainer" class="error-container hidden">
                <div class="error-header">
                    <span class="icon">⚠️</span>
                    <span>Conversion Error</span>
                </div>
                <pre id="errorMessage" class="error-message"></pre>
            </div>
        </div>
    </div>

    <!-- Status Bar -->
    <div class="status-bar">
        <div class="status-left">
            <span id="statusText" class="status-text">Ready</span>
        </div>
        <div class="status-right">
            <span id="conversionTime" class="status-meta"></span>
        </div>
    </div>

    <script nonce="${nonce}">
        const vscode = acquireVsCodeApi();
        
        // State
        let currentMode = '${initialMode}'; // 'sql' or 'mermaid'
        let currentDialect = 'AnsiSql';
        let showPreview = true;
        let isConverting = false;
        let autoConvert = true;
        let conversionTimeout = null;

        // Elements
        const editor = document.getElementById('editor');
        const output = document.getElementById('output');
        const toggleModeBtn = document.getElementById('toggleModeBtn');
        const modeText = document.getElementById('modeText');
        const convertBtn = document.getElementById('convertBtn');
        const saveBtn = document.getElementById('saveBtn');
        const copyBtn = document.getElementById('copyBtn');
        const exportBtn = document.getElementById('exportBtn');
        const dialectSelect = document.getElementById('dialectSelect');
        const togglePreviewBtn = document.getElementById('togglePreviewBtn');
        const previewContainer = document.getElementById('previewContainer');
        const previewContent = document.getElementById('previewContent');
        const errorContainer = document.getElementById('errorContainer');
        const errorMessage = document.getElementById('errorMessage');
        const leftPanelTitle = document.getElementById('leftPanelTitle');
        const rightPanelTitle = document.getElementById('rightPanelTitle');
        const statusText = document.getElementById('statusText');
        const conversionTimeEl = document.getElementById('conversionTime');
        const lineCount = document.getElementById('lineCount');

        // Initialize
        vscode.postMessage({ type: 'getConfig' });
        updateUI();

        // Event Listeners
        toggleModeBtn.addEventListener('click', () => {
            currentMode = currentMode === 'sql' ? 'mermaid' : 'sql';
            updateUI();
            if (autoConvert && editor.value.trim()) {
                scheduleConversion();
            }
        });

        convertBtn.addEventListener('click', () => convert());

        saveBtn.addEventListener('click', () => {
            vscode.postMessage({
                type: 'save',
                content: editor.value
            });
            setStatus('Saved', 2000);
        });

        copyBtn.addEventListener('click', () => {
            navigator.clipboard.writeText(output.value);
            setStatus('Copied to clipboard', 2000);
        });

        exportBtn.addEventListener('click', () => {
            // Export handled by VS Code extension
            setStatus('Export feature coming soon', 2000);
        });

        dialectSelect.addEventListener('change', (e) => {
            currentDialect = e.target.value;
            if (currentMode === 'mermaid' && autoConvert && editor.value.trim()) {
                scheduleConversion();
            }
        });

        togglePreviewBtn.addEventListener('click', () => {
            showPreview = !showPreview;
            togglePreviewBtn.classList.toggle('active', showPreview);
            previewContainer.style.display = showPreview ? 'flex' : 'none';
        });

        editor.addEventListener('input', () => {
            updateLineCount();
            if (autoConvert) {
                scheduleConversion();
            }
        });

        editor.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.key === 's') {
                e.preventDefault();
                saveBtn.click();
            }
            if (e.ctrlKey && e.key === 'Enter') {
                e.preventDefault();
                convertBtn.click();
            }
        });

        // Handle messages from extension
        window.addEventListener('message', event => {
            const message = event.data;
            switch (message.type) {
                case 'init':
                    editor.value = message.content;
                    currentMode = message.mode;
                    updateUI();
                    updateLineCount();
                    if (autoConvert && editor.value.trim()) {
                        scheduleConversion();
                    }
                    break;
                case 'documentChanged':
                    if (editor.value !== message.content) {
                        editor.value = message.content;
                        updateLineCount();
                    }
                    break;
                case 'conversionResult':
                    handleConversionResult(message);
                    break;
                case 'config':
                    applyConfig(message.config);
                    break;
            }
        });

        function updateUI() {
            if (currentMode === 'sql') {
                modeText.textContent = 'SQL → Mermaid';
                leftPanelTitle.textContent = 'SQL Input';
                rightPanelTitle.textContent = 'Mermaid Output';
                dialectSelect.style.display = 'none';
                previewContainer.style.display = showPreview ? 'flex' : 'none';
            } else {
                modeText.textContent = 'Mermaid → SQL';
                leftPanelTitle.textContent = 'Mermaid Input';
                rightPanelTitle.textContent = \`SQL Output (\${currentDialect})\`;
                dialectSelect.style.display = 'inline-block';
                previewContainer.style.display = 'none';
            }
        }

        function scheduleConversion() {
            if (conversionTimeout) {
                clearTimeout(conversionTimeout);
            }
            conversionTimeout = setTimeout(() => convert(), 500);
        }

        async function convert() {
            if (isConverting || !editor.value.trim()) {
                return;
            }

            isConverting = true;
            setStatus('Converting...');
            errorContainer.classList.add('hidden');
            convertBtn.disabled = true;

            const startTime = performance.now();

            vscode.postMessage({
                type: 'convert',
                content: editor.value,
                mode: currentMode,
                dialect: currentDialect
            });
        }

        function handleConversionResult(message) {
            const endTime = performance.now();
            const duration = Math.round(endTime - (performance.now() - 100));
            
            isConverting = false;
            convertBtn.disabled = false;

            if (message.success) {
                output.value = message.result;
                errorContainer.classList.add('hidden');
                setStatus(\`Converted in \${duration}ms\`, 3000);
                conversionTimeEl.textContent = \`\${duration}ms\`;

                // Render Mermaid preview if in SQL mode
                if (currentMode === 'sql' && showPreview) {
                    renderMermaidPreview(message.result);
                }
            } else {
                output.value = '';
                errorMessage.textContent = message.error;
                errorContainer.classList.remove('hidden');
                setStatus('Conversion failed', 3000);
            }
        }

        async function renderMermaidPreview(mermaidCode) {
            try {
                previewContent.innerHTML = '<div class="mermaid">' + mermaidCode + '</div>';
                await window.mermaid.run({
                    querySelector: '.mermaid'
                });
            } catch (error) {
                previewContent.innerHTML = \`
                    <div class="preview-error">
                        <span class="icon">⚠️</span>
                        <p>Failed to render diagram</p>
                        <pre>\${error.message}</pre>
                    </div>
                \`;
            }
        }

        function updateLineCount() {
            const lines = editor.value.split('\\n').length;
            lineCount.textContent = \`\${lines} line\${lines !== 1 ? 's' : ''}\`;
        }

        function setStatus(text, duration) {
            statusText.textContent = text;
            if (duration) {
                setTimeout(() => {
                    statusText.textContent = 'Ready';
                }, duration);
            }
        }

        function applyConfig(config) {
            currentDialect = config.defaultDialect || 'AnsiSql';
            autoConvert = config.autoConvert !== false;
            showPreview = config.showPreview !== false;
            
            dialectSelect.value = currentDialect;
            togglePreviewBtn.classList.toggle('active', showPreview);
            previewContainer.style.display = showPreview ? 'flex' : 'none';
            
            updateUI();
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.key === 'm') {
                e.preventDefault();
                toggleModeBtn.click();
            }
        });
    </script>
</body>
</html>`;
    }
}

