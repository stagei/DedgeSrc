/**
 * MCP Server for read-only PostgreSQL queries.
 *
 * Reads DatabasesV2.json (Provider=PostgreSQL) for available databases and
 * exposes a single tool "query_postgresql" that accepts databaseName + query.
 *
 * Transport: stdio (registered in ~/.cursor/mcp.json)
 *
 * Environment variables:
 *   PG_USER       – PostgreSQL user (default: postgres)
 *   PG_PASSWORD   – PostgreSQL password (default: postgres)
 *   PG_PORT       – PostgreSQL port (default: 8432)
 *   PG_CONFIG     – Override path to DatabasesV2.json (auto-detected if omitted)
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import pg from "pg";
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const PG_USER = process.env.PG_USER || "postgres";
const PG_PASSWORD = process.env.PG_PASSWORD || "postgres";
const PG_PORT = parseInt(process.env.PG_PORT || "8432", 10);

// ─── Blocked SQL patterns (read-only enforcement) ───────────────────────────
const BLOCKED_PATTERNS = [
  /^\s*(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|MERGE|GRANT|REVOKE|VACUUM|REINDEX|CLUSTER|COMMENT\s+ON|SECURITY\s+LABEL)\b/i,
  /^\s*(COPY\s+.*\s+FROM)\b/i,
  /^\s*(DO\s+\$)/i,
];

function isReadOnly(query) {
  const trimmed = query.replace(/\/\*[\s\S]*?\*\//g, "").trim();
  return !BLOCKED_PATTERNS.some((pat) => pat.test(trimmed));
}

// ─── Load database configuration from DatabasesV2.json (Provider=PostgreSQL) ─
function loadDatabaseConfig() {
  const candidates = [
    process.env.PG_CONFIG,
    "\\dedge-server\\DedgeCommon\\Configfiles\\DatabasesV2.json",
  ].filter(Boolean);

  for (const path of candidates) {
    if (existsSync(path)) {
      const raw = readFileSync(path, "utf-8");
      const all = JSON.parse(raw);
      return all.filter((db) => db.Provider === "PostgreSQL");
    }
  }
  return [];
}

const allDatabases = loadDatabaseConfig();
const activeDatabases = allDatabases.filter((db) => db.IsActive !== false);

function findDatabase(name) {
  return activeDatabases.find(
    (db) => db.Database.toLowerCase() === name.toLowerCase()
  );
}

// ─── MCP Server ─────────────────────────────────────────────────────────────
const server = new McpServer({
  name: "postgresql-query",
  version: "1.0.0",
});

server.tool(
  "query_postgresql",
  "Execute a read-only SQL query against a PostgreSQL database. " +
    "Specify databaseName (from DatabasesV2.json, Provider=PostgreSQL) and the SQL query. " +
    "Only SELECT, WITH...SELECT, VALUES, and EXPLAIN are allowed. " +
    "Always include LIMIT on large tables.",
  {
    databaseName: z
      .string()
      .describe(
        "Database name from DatabasesV2.json (e.g. DedgeAuth, GenericLogHandler). Required."
      ),
    query: z.string().describe("SQL query to execute (read-only)."),
    environment: z
      .string()
      .optional()
      .describe(
        "Environment filter: TST or PRD. Defaults to TST if multiple matches exist."
      ),
  },
  async ({ databaseName, query, environment }) => {
    if (!databaseName) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: "databaseName is required. Available databases: " +
                [...new Set(activeDatabases.map((d) => d.Database))].join(", "),
            }),
          },
        ],
        isError: true,
      };
    }

    if (!isReadOnly(query)) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: "Query rejected: only read-only statements (SELECT, WITH...SELECT, VALUES, EXPLAIN) are allowed.",
            }),
          },
        ],
        isError: true,
      };
    }

    const matches = activeDatabases.filter(
      (db) => db.Database.toLowerCase() === databaseName.toLowerCase()
    );

    if (matches.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: `Database '${databaseName}' not found. Available: ${[...new Set(activeDatabases.map((d) => d.Database))].join(", ")}`,
            }),
          },
        ],
        isError: true,
      };
    }

    let dbEntry;
    if (environment) {
      dbEntry = matches.find(
        (m) => m.Environment.toLowerCase() === environment.toLowerCase()
      );
      if (!dbEntry) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                error: `Database '${databaseName}' not found for environment '${environment}'. Available environments: ${matches.map((m) => m.Environment).join(", ")}`,
              }),
            },
          ],
          isError: true,
        };
      }
    } else {
      dbEntry = matches.find((m) => m.Environment === "TST") || matches[0];
    }

    const client = new pg.Client({
      host: dbEntry.ServerName,
      port: dbEntry.Port || PG_PORT,
      database: dbEntry.Database,
      user: PG_USER,
      password: PG_PASSWORD,
      connectionTimeoutMillis: 10000,
      query_timeout: 60000,
    });

    try {
      await client.connect();
      const result = await client.query(query);

      const response = {
        database: dbEntry.Database,
        server: dbEntry.ServerName,
        environment: dbEntry.Environment,
        application: dbEntry.Application,
        rowCount: result.rowCount,
        fields: result.fields.map((f) => ({
          name: f.name,
          dataTypeID: f.dataTypeID,
        })),
        rows: result.rows,
      };

      return {
        content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
      };
    } catch (err) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: err.message,
              code: err.code,
              database: dbEntry.Database,
              server: dbEntry.ServerName,
            }),
          },
        ],
        isError: true,
      };
    } finally {
      await client.end().catch(() => {});
    }
  }
);

server.tool(
  "list_postgresql_databases",
  "List all available PostgreSQL databases from the configuration.",
  {},
  async () => {
    const summary = activeDatabases.map((db) => ({
      database: db.Database,
      application: db.Application,
      environment: db.Environment,
      server: db.ServerName,
      port: db.Port,
      description: db.Description,
    }));
    return {
      content: [{ type: "text", text: JSON.stringify(summary, null, 2) }],
    };
  }
);

server.tool(
  "list_postgresql_tables",
  "List all tables in a PostgreSQL database, optionally filtered by schema.",
  {
    databaseName: z.string().describe("Database name (e.g. DedgeAuth)."),
    schema: z
      .string()
      .optional()
      .describe("Schema name filter (default: public)."),
    environment: z
      .string()
      .optional()
      .describe("Environment: TST or PRD. Defaults to TST."),
  },
  async ({ databaseName, schema, environment }) => {
    const schemaFilter = schema || "public";

    const matches = activeDatabases.filter(
      (db) => db.Database.toLowerCase() === databaseName.toLowerCase()
    );
    if (matches.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: `Database '${databaseName}' not found.`,
            }),
          },
        ],
        isError: true,
      };
    }

    let dbEntry;
    if (environment) {
      dbEntry = matches.find(
        (m) => m.Environment.toLowerCase() === environment.toLowerCase()
      );
    }
    if (!dbEntry) {
      dbEntry = matches.find((m) => m.Environment === "TST") || matches[0];
    }

    const client = new pg.Client({
      host: dbEntry.ServerName,
      port: dbEntry.Port || PG_PORT,
      database: dbEntry.Database,
      user: PG_USER,
      password: PG_PASSWORD,
      connectionTimeoutMillis: 10000,
    });

    try {
      await client.connect();
      const result = await client.query(
        `SELECT table_schema, table_name, table_type
         FROM information_schema.tables
         WHERE table_schema = $1
         ORDER BY table_name`,
        [schemaFilter]
      );
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                database: dbEntry.Database,
                server: dbEntry.ServerName,
                schema: schemaFilter,
                tables: result.rows,
              },
              null,
              2
            ),
          },
        ],
      };
    } catch (err) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({ error: err.message, code: err.code }),
          },
        ],
        isError: true,
      };
    } finally {
      await client.end().catch(() => {});
    }
  }
);

server.tool(
  "describe_postgresql_table",
  "Show column details for a specific table in a PostgreSQL database.",
  {
    databaseName: z.string().describe("Database name (e.g. DedgeAuth)."),
    tableName: z.string().describe("Table name to describe."),
    schema: z
      .string()
      .optional()
      .describe("Schema name (default: public)."),
    environment: z
      .string()
      .optional()
      .describe("Environment: TST or PRD. Defaults to TST."),
  },
  async ({ databaseName, tableName, schema, environment }) => {
    const schemaFilter = schema || "public";

    const matches = activeDatabases.filter(
      (db) => db.Database.toLowerCase() === databaseName.toLowerCase()
    );
    if (matches.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              error: `Database '${databaseName}' not found.`,
            }),
          },
        ],
        isError: true,
      };
    }

    let dbEntry;
    if (environment) {
      dbEntry = matches.find(
        (m) => m.Environment.toLowerCase() === environment.toLowerCase()
      );
    }
    if (!dbEntry) {
      dbEntry = matches.find((m) => m.Environment === "TST") || matches[0];
    }

    const client = new pg.Client({
      host: dbEntry.ServerName,
      port: dbEntry.Port || PG_PORT,
      database: dbEntry.Database,
      user: PG_USER,
      password: PG_PASSWORD,
      connectionTimeoutMillis: 10000,
    });

    try {
      await client.connect();
      const result = await client.query(
        `SELECT
           c.column_name,
           c.data_type,
           c.character_maximum_length,
           c.numeric_precision,
           c.numeric_scale,
           c.is_nullable,
           c.column_default,
           CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 'YES' ELSE 'NO' END AS is_primary_key
         FROM information_schema.columns c
         LEFT JOIN information_schema.key_column_usage kcu
           ON c.table_schema = kcu.table_schema
           AND c.table_name = kcu.table_name
           AND c.column_name = kcu.column_name
         LEFT JOIN information_schema.table_constraints tc
           ON kcu.constraint_name = tc.constraint_name
           AND kcu.table_schema = tc.table_schema
           AND tc.constraint_type = 'PRIMARY KEY'
         WHERE c.table_schema = $1 AND c.table_name = $2
         ORDER BY c.ordinal_position`,
        [schemaFilter, tableName]
      );

      if (result.rows.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                error: `Table '${schemaFilter}.${tableName}' not found in ${dbEntry.Database}.`,
              }),
            },
          ],
          isError: true,
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                database: dbEntry.Database,
                server: dbEntry.ServerName,
                table: `${schemaFilter}.${tableName}`,
                columns: result.rows,
              },
              null,
              2
            ),
          },
        ],
      };
    } catch (err) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({ error: err.message, code: err.code }),
          },
        ],
        isError: true,
      };
    } finally {
      await client.end().catch(() => {});
    }
  }
);

// ─── Start server ───────────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
