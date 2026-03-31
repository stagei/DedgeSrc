using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GenericLogHandler.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "import_status",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    source_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    file_path = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    last_processed_timestamp = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    last_import_timestamp = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                    records_processed = table.Column<long>(type: "bigint", nullable: false),
                    records_failed = table.Column<long>(type: "bigint", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    error_message = table.Column<string>(type: "text", nullable: false),
                    processing_duration_ms = table.Column<long>(type: "bigint", nullable: false),
                    metadata = table.Column<string>(type: "text", nullable: false),
                    last_processed_byte_offset = table.Column<long>(type: "bigint", nullable: false),
                    file_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    last_file_size = table.Column<long>(type: "bigint", nullable: false),
                    file_creation_date = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    last_processed_line = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_import_status", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "log_entries",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    timestamp = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    level = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    process_id = table.Column<int>(type: "integer", nullable: false),
                    location = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    function_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    line_number = table.Column<int>(type: "integer", nullable: false),
                    computer_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    user_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    message = table.Column<string>(type: "text", maxLength: 8000, nullable: false),
                    concatenated_search_string = table.Column<string>(type: "text", nullable: false),
                    error_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    alert_id = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ordrenr = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    avdnr = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    job_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    exception_type = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    stack_trace = table.Column<string>(type: "text", nullable: true),
                    inner_exception = table.Column<string>(type: "text", nullable: true),
                    command_invocation = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    script_line_number = table.Column<int>(type: "integer", nullable: true),
                    script_name = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    position = table.Column<int>(type: "integer", nullable: true),
                    source_file = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    source_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    import_timestamp = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                    import_batch_id = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_log_entries", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "saved_filters",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    filter_json = table.Column<string>(type: "text", nullable: false),
                    created_by = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_alert_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    alert_config = table.Column<string>(type: "text", nullable: true),
                    last_evaluated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    last_triggered_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_shared = table.Column<bool>(type: "boolean", nullable: false),
                    category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_saved_filters", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "alert_history",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    filter_id = table.Column<Guid>(type: "uuid", nullable: false),
                    filter_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    triggered_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                    match_count = table.Column<int>(type: "integer", nullable: false),
                    action_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    action_taken = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    success = table.Column<bool>(type: "boolean", nullable: false),
                    error_message = table.Column<string>(type: "text", nullable: true),
                    action_response = table.Column<string>(type: "text", nullable: true),
                    execution_duration_ms = table.Column<long>(type: "bigint", nullable: false),
                    sample_entry_ids = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_alert_history", x => x.id);
                    table.ForeignKey(
                        name: "FK_alert_history_saved_filters_filter_id",
                        column: x => x.filter_id,
                        principalTable: "saved_filters",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "idx_alert_history_filter_id",
                table: "alert_history",
                column: "filter_id");

            migrationBuilder.CreateIndex(
                name: "idx_alert_history_success",
                table: "alert_history",
                column: "success");

            migrationBuilder.CreateIndex(
                name: "idx_alert_history_triggered_at",
                table: "alert_history",
                column: "triggered_at");

            migrationBuilder.CreateIndex(
                name: "idx_import_status_last_import",
                table: "import_status",
                column: "last_import_timestamp");

            migrationBuilder.CreateIndex(
                name: "idx_import_status_source_file",
                table: "import_status",
                columns: new[] { "source_name", "file_path" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "idx_import_status_status",
                table: "import_status",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_alert_id",
                table: "log_entries",
                column: "alert_id",
                filter: "alert_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_avdnr",
                table: "log_entries",
                column: "avdnr",
                filter: "avdnr IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_computer_name",
                table: "log_entries",
                column: "computer_name");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_error_id",
                table: "log_entries",
                column: "error_id",
                filter: "error_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_import_timestamp",
                table: "log_entries",
                column: "import_timestamp");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_job_name",
                table: "log_entries",
                column: "job_name",
                filter: "job_name IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_level",
                table: "log_entries",
                column: "level");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_ordrenr",
                table: "log_entries",
                column: "ordrenr",
                filter: "ordrenr IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_search_text",
                table: "log_entries",
                column: "concatenated_search_string");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_source_type",
                table: "log_entries",
                column: "source_type");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_timestamp",
                table: "log_entries",
                column: "timestamp");

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_timestamp_computer_level",
                table: "log_entries",
                columns: new[] { "timestamp", "computer_name", "level" });

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_user_name",
                table: "log_entries",
                column: "user_name");

            migrationBuilder.CreateIndex(
                name: "idx_saved_filters_alert_enabled",
                table: "saved_filters",
                column: "is_alert_enabled",
                filter: "is_alert_enabled = true");

            migrationBuilder.CreateIndex(
                name: "idx_saved_filters_category",
                table: "saved_filters",
                column: "category",
                filter: "category IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "idx_saved_filters_created_by",
                table: "saved_filters",
                column: "created_by");

            migrationBuilder.CreateIndex(
                name: "idx_saved_filters_name",
                table: "saved_filters",
                column: "name");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "alert_history");

            migrationBuilder.DropTable(
                name: "import_status");

            migrationBuilder.DropTable(
                name: "log_entries");

            migrationBuilder.DropTable(
                name: "saved_filters");
        }
    }
}
