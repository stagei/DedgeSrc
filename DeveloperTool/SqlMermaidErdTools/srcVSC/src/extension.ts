import * as vscode from 'vscode';
import { ConversionService } from './services/conversionService';
import { PreviewService } from './services/previewService';
import { FileService } from './services/fileService';

let conversionService: ConversionService;
let previewService: PreviewService;
let fileService: FileService;

export function activate(context: vscode.ExtensionContext) {
    console.log('SqlMermaid ERD Tools extension is now active!');

    // Initialize services
    conversionService = new ConversionService(context);
    previewService = new PreviewService(context);
    fileService = new FileService();

    // Register commands
    context.subscriptions.push(
        vscode.commands.registerCommand('sqlmermaid.sqlToMermaid', async () => {
            await handleSqlToMermaid();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('sqlmermaid.mermaidToSql', async () => {
            await handleMermaidToSql();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('sqlmermaid.mermaidToSqlWithDialect', async () => {
            await handleMermaidToSqlWithDialect();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('sqlmermaid.previewMermaid', async () => {
            await handlePreviewMermaid();
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('sqlmermaid.convertCurrentFile', async () => {
            await handleConvertCurrentFile();
        })
    );

    // Show welcome message on first install
    const hasShownWelcome = context.globalState.get<boolean>('hasShownWelcome', false);
    if (!hasShownWelcome) {
        showWelcomeMessage(context);
        context.globalState.update('hasShownWelcome', true);
    }
}

async function handleSqlToMermaid() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No active editor found');
        return;
    }

    const sql = editor.document.getText();
    if (!sql.trim()) {
        vscode.window.showWarningMessage('SQL file is empty');
        return;
    }

    try {
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "Converting SQL to Mermaid...",
            cancellable: false
        }, async () => {
            const mermaid = await conversionService.sqlToMermaid(sql);
            
            // Handle output based on settings
            const config = vscode.workspace.getConfiguration('sqlmermaid');
            const outputFormat = config.get<string>('outputFormat', 'newFile');

            if (outputFormat === 'clipboard' || outputFormat === 'both') {
                await vscode.env.clipboard.writeText(mermaid);
                vscode.window.showInformationMessage('Mermaid diagram copied to clipboard!');
            }

            if (outputFormat === 'newFile' || outputFormat === 'both') {
                const newFilePath = await fileService.createMermaidFile(editor.document.uri, mermaid);
                const doc = await vscode.workspace.openTextDocument(newFilePath);
                await vscode.window.showTextDocument(doc, { preview: false });
                
                // Auto-open preview if enabled
                if (config.get<boolean>('autoOpenPreview', true)) {
                    await previewService.showPreview(doc.uri);
                }
                
                vscode.window.showInformationMessage(`✅ Converted to Mermaid: ${newFilePath.fsPath}`);
            }
        });
    } catch (error: any) {
        vscode.window.showErrorMessage(`Conversion failed: ${error.message}`);
    }
}

async function handleMermaidToSql() {
    const config = vscode.workspace.getConfiguration('sqlmermaid');
    const defaultDialect = config.get<string>('defaultDialect', 'AnsiSql');
    await convertMermaidToSql(defaultDialect);
}

async function handleMermaidToSqlWithDialect() {
    const dialect = await vscode.window.showQuickPick(
        ['AnsiSql', 'SqlServer', 'PostgreSql', 'MySql'],
        {
            placeHolder: 'Select SQL dialect',
            title: 'Convert Mermaid to SQL'
        }
    );

    if (!dialect) {
        return; // User cancelled
    }

    await convertMermaidToSql(dialect);
}

async function convertMermaidToSql(dialect: string) {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No active editor found');
        return;
    }

    const mermaid = editor.document.getText();
    if (!mermaid.trim()) {
        vscode.window.showWarningMessage('Mermaid file is empty');
        return;
    }

    try {
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Converting Mermaid to ${dialect}...`,
            cancellable: false
        }, async () => {
            const sql = await conversionService.mermaidToSql(mermaid, dialect);
            
            // Handle output based on settings
            const config = vscode.workspace.getConfiguration('sqlmermaid');
            const outputFormat = config.get<string>('outputFormat', 'newFile');

            if (outputFormat === 'clipboard' || outputFormat === 'both') {
                await vscode.env.clipboard.writeText(sql);
                vscode.window.showInformationMessage(`${dialect} SQL copied to clipboard!`);
            }

            if (outputFormat === 'newFile' || outputFormat === 'both') {
                const newFilePath = await fileService.createSqlFile(editor.document.uri, sql, dialect);
                const doc = await vscode.workspace.openTextDocument(newFilePath);
                await vscode.window.showTextDocument(doc, { preview: false });
                
                vscode.window.showInformationMessage(`✅ Converted to ${dialect}: ${newFilePath.fsPath}`);
            }
        });
    } catch (error: any) {
        vscode.window.showErrorMessage(`Conversion failed: ${error.message}`);
    }
}

async function handlePreviewMermaid() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No active editor found');
        return;
    }

    await previewService.showPreview(editor.document.uri);
}

async function handleConvertCurrentFile() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage('No active editor found');
        return;
    }

    const ext = editor.document.fileName.toLowerCase();
    if (ext.endsWith('.sql')) {
        await handleSqlToMermaid();
    } else if (ext.endsWith('.mmd') || ext.endsWith('.mermaid')) {
        await handleMermaidToSql();
    } else {
        vscode.window.showWarningMessage('Current file is not a .sql or .mmd file');
    }
}

function showWelcomeMessage(context: vscode.ExtensionContext) {
    const message = '🎉 Welcome to SQL ↔ Mermaid ERD Tools! Convert between SQL and Mermaid diagrams with ease.';
    const actions = ['View Commands', 'Settings', 'Dismiss'];
    
    vscode.window.showInformationMessage(message, ...actions).then(selection => {
        if (selection === 'View Commands') {
            vscode.commands.executeCommand('workbench.action.showCommands', 'SqlMermaid');
        } else if (selection === 'Settings') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'sqlmermaid');
        }
    });
}

export function deactivate() {
    console.log('SqlMermaid ERD Tools extension is now deactivated');
}

