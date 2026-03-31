using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAdDomainAndAdGroupsCache : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ad_domain",
                table: "tenants",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ad_groups_cache",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false),
                    sam_account_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    distinguished_name = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    group_category = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    member_count = table.Column<int>(type: "integer", nullable: false),
                    last_synced_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ad_groups_cache", x => x.id);
                    table.ForeignKey(
                        name: "FK_ad_groups_cache_tenants_tenant_id",
                        column: x => x.tenant_id,
                        principalTable: "tenants",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ad_groups_cache_tenant_sam",
                table: "ad_groups_cache",
                columns: new[] { "tenant_id", "sam_account_name" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ad_groups_cache");

            migrationBuilder.DropColumn(
                name: "ad_domain",
                table: "tenants");
        }
    }
}
