import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

export class FileService {
    /**
     * Create a new Mermaid file from SQL conversion
     */
    async createMermaidFile(sourceUri: vscode.Uri, mermaidContent: string): Promise<vscode.Uri> {
        const sourcePath = sourceUri.fsPath;
        const dir = path.dirname(sourcePath);
        const baseName = path.basename(sourcePath, path.extname(sourcePath));
        const newFilePath = path.join(dir, `${baseName}.mmd`);

        // Write file
        fs.writeFileSync(newFilePath, mermaidContent, 'utf-8');

        return vscode.Uri.file(newFilePath);
    }

    /**
     * Create a new SQL file from Mermaid conversion
     */
    async createSqlFile(sourceUri: vscode.Uri, sqlContent: string, dialect: string): Promise<vscode.Uri> {
        const sourcePath = sourceUri.fsPath;
        const dir = path.dirname(sourcePath);
        const baseName = path.basename(sourcePath, path.extname(sourcePath));
        const dialectSuffix = dialect !== 'AnsiSql' ? `_${dialect}` : '';
        const newFilePath = path.join(dir, `${baseName}${dialectSuffix}.sql`);

        // Write file
        fs.writeFileSync(newFilePath, sqlContent, 'utf-8');

        return vscode.Uri.file(newFilePath);
    }

    /**
     * Get suggested output file name
     */
    getSuggestedFileName(sourceUri: vscode.Uri, targetExtension: string): string {
        const baseName = path.basename(sourceUri.fsPath, path.extname(sourceUri.fsPath));
        return `${baseName}${targetExtension}`;
    }
}

