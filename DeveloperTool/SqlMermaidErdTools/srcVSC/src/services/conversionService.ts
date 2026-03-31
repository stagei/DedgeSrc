import * as vscode from 'vscode';
import * as child_process from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';

export class ConversionService {
    private context: vscode.ExtensionContext;
    private cliPath: string | null = null;

    constructor(context: vscode.ExtensionContext) {
        this.context = context;
        this.detectCli();
    }

    /**
     * Detect the SqlMermaidErdTools CLI executable
     */
    private detectCli(): void {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        const customPath = config.get<string>('cliPath');

        if (customPath && fs.existsSync(customPath)) {
            this.cliPath = customPath;
            console.log(`Using custom CLI path: ${customPath}`);
            return;
        }

        // Try to find dotnet global tool
        try {
            const result = child_process.execSync('dotnet tool list -g', { encoding: 'utf-8' });
            if (result.includes('sqlmermaiderdtools.cli')) {
                this.cliPath = 'sqlmermaid'; // Global tool
                console.log('Found SqlMermaidErdTools as global tool');
                return;
            }
        } catch (error) {
            console.log('SqlMermaidErdTools CLI not found as global tool');
        }

        // Check if running from development workspace
        if (vscode.workspace.workspaceFolders) {
            for (const folder of vscode.workspace.workspaceFolders) {
                const devCliPath = path.join(folder.uri.fsPath, 'src', 'SqlMermaidErdTools.CLI', 'bin', 'Debug', 'net10.0', 'SqlMermaidErdTools.CLI.exe');
                if (fs.existsSync(devCliPath)) {
                    this.cliPath = devCliPath;
                    console.log(`Found development CLI: ${devCliPath}`);
                    return;
                }
            }
        }

        console.log('No CLI found - will use API endpoint if configured');
    }

    /**
     * Convert SQL DDL to Mermaid ERD
     */
    async sqlToMermaid(sql: string): Promise<string> {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        const apiEndpoint = config.get<string>('apiEndpoint');

        if (apiEndpoint) {
            return await this.sqlToMermaidApi(sql, apiEndpoint);
        } else if (this.cliPath) {
            return await this.sqlToMermaidCli(sql);
        } else {
            throw new Error('No conversion method available. Install CLI or configure API endpoint in settings.');
        }
    }

    /**
     * Convert Mermaid ERD to SQL DDL
     */
    async mermaidToSql(mermaid: string, dialect: string): Promise<string> {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        const apiEndpoint = config.get<string>('apiEndpoint');

        if (apiEndpoint) {
            return await this.mermaidToSqlApi(mermaid, dialect, apiEndpoint);
        } else if (this.cliPath) {
            return await this.mermaidToSqlCli(mermaid, dialect);
        } else {
            throw new Error('No conversion method available. Install CLI or configure API endpoint in settings.');
        }
    }

    /**
     * Convert SQL to Mermaid using CLI
     */
    private async sqlToMermaidCli(sql: string): Promise<string> {
        const tempSqlFile = path.join(this.context.globalStorageUri.fsPath, `temp_${Date.now()}.sql`);
        const tempMmdFile = path.join(this.context.globalStorageUri.fsPath, `temp_${Date.now()}.mmd`);

        // Ensure temp directory exists
        if (!fs.existsSync(this.context.globalStorageUri.fsPath)) {
            fs.mkdirSync(this.context.globalStorageUri.fsPath, { recursive: true });
        }

        try {
            // Write SQL to temp file
            fs.writeFileSync(tempSqlFile, sql, 'utf-8');

            // Execute CLI
            const command = `"${this.cliPath}" sql-to-mmd "${tempSqlFile}" --output "${tempMmdFile}"`;
            console.log(`Executing: ${command}`);
            
            child_process.execSync(command, { 
                encoding: 'utf-8',
                stdio: 'pipe'
            });

            // Read result
            const mermaid = fs.readFileSync(tempMmdFile, 'utf-8');
            return mermaid;
        } finally {
            // Clean up temp files
            if (fs.existsSync(tempSqlFile)) {
                fs.unlinkSync(tempSqlFile);
            }
            if (fs.existsSync(tempMmdFile)) {
                fs.unlinkSync(tempMmdFile);
            }
        }
    }

    /**
     * Convert Mermaid to SQL using CLI
     */
    private async mermaidToSqlCli(mermaid: string, dialect: string): Promise<string> {
        const tempMmdFile = path.join(this.context.globalStorageUri.fsPath, `temp_${Date.now()}.mmd`);
        const tempSqlFile = path.join(this.context.globalStorageUri.fsPath, `temp_${Date.now()}.sql`);

        // Ensure temp directory exists
        if (!fs.existsSync(this.context.globalStorageUri.fsPath)) {
            fs.mkdirSync(this.context.globalStorageUri.fsPath, { recursive: true });
        }

        try {
            // Write Mermaid to temp file
            fs.writeFileSync(tempMmdFile, mermaid, 'utf-8');

            // Execute CLI
            const command = `"${this.cliPath}" mmd-to-sql "${tempMmdFile}" --dialect ${dialect} --output "${tempSqlFile}"`;
            console.log(`Executing: ${command}`);
            
            child_process.execSync(command, { 
                encoding: 'utf-8',
                stdio: 'pipe'
            });

            // Read result
            const sql = fs.readFileSync(tempSqlFile, 'utf-8');
            return sql;
        } finally {
            // Clean up temp files
            if (fs.existsSync(tempMmdFile)) {
                fs.unlinkSync(tempMmdFile);
            }
            if (fs.existsSync(tempSqlFile)) {
                fs.unlinkSync(tempSqlFile);
            }
        }
    }

    /**
     * Convert SQL to Mermaid using REST API
     */
    private async sqlToMermaidApi(sql: string, apiEndpoint: string): Promise<string> {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        const apiKey = config.get<string>('apiKey');

        try {
            const response = await axios.post(
                `${apiEndpoint}/api/v1/convert/sql-to-mermaid`,
                { sql },
                {
                    headers: {
                        'Content-Type': 'application/json',
                        ...(apiKey && { 'Authorization': `Bearer ${apiKey}` })
                    }
                }
            );

            return response.data.mermaid || response.data;
        } catch (error: any) {
            if (error.response?.status === 429) {
                throw new Error('API rate limit exceeded. Please upgrade your plan or wait before trying again.');
            } else if (error.response?.status === 401) {
                throw new Error('Invalid API key. Please check your settings.');
            } else {
                throw new Error(`API request failed: ${error.message}`);
            }
        }
    }

    /**
     * Convert Mermaid to SQL using REST API
     */
    private async mermaidToSqlApi(mermaid: string, dialect: string, apiEndpoint: string): Promise<string> {
        const config = vscode.workspace.getConfiguration('sqlmermaid');
        const apiKey = config.get<string>('apiKey');

        try {
            const response = await axios.post(
                `${apiEndpoint}/api/v1/convert/mermaid-to-sql`,
                { mermaid, dialect },
                {
                    headers: {
                        'Content-Type': 'application/json',
                        ...(apiKey && { 'Authorization': `Bearer ${apiKey}` })
                    }
                }
            );

            return response.data.sql || response.data;
        } catch (error: any) {
            if (error.response?.status === 429) {
                throw new Error('API rate limit exceeded. Please upgrade your plan or wait before trying again.');
            } else if (error.response?.status === 401) {
                throw new Error('Invalid API key. Please check your settings.');
            } else {
                throw new Error(`API request failed: ${error.message}`);
            }
        }
    }
}

