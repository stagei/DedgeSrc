using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GenericLogHandler.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddProtectedField : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "protected",
                table: "log_entries",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "protection_reason",
                table: "log_entries",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_protected_timestamp",
                table: "log_entries",
                columns: new[] { "protected", "timestamp" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "idx_log_entries_protected_timestamp",
                table: "log_entries");

            migrationBuilder.DropColumn(
                name: "protected",
                table: "log_entries");

            migrationBuilder.DropColumn(
                name: "protection_reason",
                table: "log_entries");
        }
    }
}
