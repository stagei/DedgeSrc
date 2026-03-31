using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddWindowsSsoAndAuthMethod : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "auth_method",
                table: "users",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "windows_sso_enabled",
                table: "tenants",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "auth_method",
                table: "users");

            migrationBuilder.DropColumn(
                name: "windows_sso_enabled",
                table: "tenants");
        }
    }
}
