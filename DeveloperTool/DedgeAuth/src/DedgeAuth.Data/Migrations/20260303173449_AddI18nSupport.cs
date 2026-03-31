using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddI18nSupport : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "preferred_language",
                table: "users",
                type: "character varying(10)",
                maxLength: 10,
                nullable: false,
                defaultValue: "nb");

            migrationBuilder.AddColumn<string>(
                name: "supported_languages_json",
                table: "tenants",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "preferred_language",
                table: "users");

            migrationBuilder.DropColumn(
                name: "supported_languages_json",
                table: "tenants");
        }
    }
}
