using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GenericLogHandler.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddImportSources : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "import_sources",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    enabled = table.Column<bool>(type: "boolean", nullable: false),
                    priority = table.Column<int>(type: "integer", nullable: false),
                    path = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    format = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    watch_directory = table.Column<bool>(type: "boolean", nullable: false),
                    encoding = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    poll_interval = table.Column<int>(type: "integer", nullable: false),
                    process_existing = table.Column<bool>(type: "boolean", nullable: false),
                    is_append_only = table.Column<bool>(type: "boolean", nullable: false),
                    max_file_age_days = table.Column<int>(type: "integer", nullable: false),
                    config_json = table.Column<string>(type: "text", nullable: true),
                    description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    last_import_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    last_import_count = table.Column<int>(type: "integer", nullable: false),
                    last_error = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_import_sources", x => x.id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "import_sources");
        }
    }
}
