using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace GenericLogHandler.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddJobStatus : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "job_status",
                table: "log_entries",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "idx_log_entries_job_status",
                table: "log_entries",
                column: "job_status",
                filter: "job_status IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "idx_log_entries_job_status",
                table: "log_entries");

            migrationBuilder.DropColumn(
                name: "job_status",
                table: "log_entries");
        }
    }
}
