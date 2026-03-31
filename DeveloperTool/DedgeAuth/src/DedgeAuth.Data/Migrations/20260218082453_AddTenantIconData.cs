using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTenantIconData : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "icon_content_type",
                table: "tenants",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "icon_data",
                table: "tenants",
                type: "bytea",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "icon_content_type",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "icon_data",
                table: "tenants");
        }
    }
}
