import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export class PreviewService {
    private context: vscode.ExtensionContext;
    private previewPanel: vscode.WebviewPanel | null = null;

    constructor(context: vscode.ExtensionContext) {
        this.context = context;
    }

    /**
     * Show Mermaid preview in webview panel
     */
    async showPreview(uri: vscode.Uri): Promise<void> {
        const document = await vscode.workspace.openTextDocument(uri);
        const mermaidContent = document.getText();

        if (this.previewPanel) {
            // Update existing panel
            this.previewPanel.webview.html = this.getWebviewContent(mermaidContent);
            this.previewPanel.reveal(vscode.ViewColumn.Beside);
        } else {
            // Create new panel
            this.previewPanel = vscode.window.createWebviewPanel(
                'mermaidPreview',
                'Mermaid Preview',
                vscode.ViewColumn.Beside,
                {
                    enableScripts: true,
                    retainContextWhenHidden: true
                }
            );

            this.previewPanel.webview.html = this.getWebviewContent(mermaidContent);

            // Reset panel when disposed
            this.previewPanel.onDidDispose(() => {
                this.previewPanel = null;
            });
        }

        // Watch for file changes and update preview
        const changeListener = vscode.workspace.onDidChangeTextDocument(event => {
            if (event.document.uri.toString() === uri.toString() && this.previewPanel) {
                this.previewPanel.webview.html = this.getWebviewContent(event.document.getText());
            }
        });

        this.previewPanel.onDidDispose(() => {
            changeListener.dispose();
        });
    }

    /**
     * Generate HTML content for webview
     */
    private getWebviewContent(mermaidContent: string): string {
        // Escape the mermaid content for embedding in JavaScript
        const escapedContent = mermaidContent
            .replace(/\\/g, '\\\\')
            .replace(/`/g, '\\`')
            .replace(/\$/g, '\\$');

        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mermaid Preview</title>
    <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
        mermaid.initialize({ 
            startOnLoad: true,
            theme: 'default',
            securityLevel: 'loose',
            fontFamily: 'Segoe UI, Arial, sans-serif'
        });
        
        window.addEventListener('DOMContentLoaded', () => {
            mermaid.contentLoaded();
        });
    </script>
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            padding: 20px;
            background-color: #1e1e1e;
            color: #d4d4d4;
        }
        .mermaid {
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
        }
        .header {
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0;
            color: #4ec9b0;
        }
        .error {
            background-color: #5a1d1d;
            border: 2px solid #f48771;
            border-radius: 4px;
            padding: 15px;
            margin: 20px 0;
        }
        .error h2 {
            margin-top: 0;
            color: #f48771;
        }
        pre {
            background-color: #2d2d2d;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Mermaid ERD Preview</h1>
        <p>Live preview of your entity relationship diagram</p>
    </div>
    
    <div class="mermaid">
${escapedContent}
    </div>
    
    <div id="error-container"></div>
    
    <script>
        window.addEventListener('error', (event) => {
            const errorContainer = document.getElementById('error-container');
            errorContainer.innerHTML = \`
                <div class="error">
                    <h2>⚠️ Mermaid Rendering Error</h2>
                    <p>\${event.message}</p>
                    <pre>\${event.error?.stack || 'No stack trace available'}</pre>
                </div>
            \`;
        });
    </script>
</body>
</html>`;
    }
}

