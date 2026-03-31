using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAccessRequests : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "access_requests",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    app_id = table.Column<Guid>(type: "uuid", nullable: true),
                    request_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    requested_role = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    requested_access_level = table.Column<int>(type: "integer", nullable: true),
                    reason = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    reviewed_by = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    review_note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    reviewed_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_access_requests", x => x.id);
                    table.ForeignKey(
                        name: "FK_access_requests_apps_app_id",
                        column: x => x.app_id,
                        principalTable: "apps",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_access_requests_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_access_requests_app_id",
                table: "access_requests",
                column: "app_id");

            migrationBuilder.CreateIndex(
                name: "IX_access_requests_status",
                table: "access_requests",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "IX_access_requests_user_id_status",
                table: "access_requests",
                columns: new[] { "user_id", "status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "access_requests");
        }
    }
}
