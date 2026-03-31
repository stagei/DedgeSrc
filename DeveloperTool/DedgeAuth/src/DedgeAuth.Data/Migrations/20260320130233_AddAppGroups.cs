using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DedgeAuth.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAppGroups : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "app_groups",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    slug = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    parent_id = table.Column<Guid>(type: "uuid", nullable: true),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    icon_url = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    acl_groups_json = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_app_groups", x => x.id);
                    table.ForeignKey(
                        name: "FK_app_groups_app_groups_parent_id",
                        column: x => x.parent_id,
                        principalTable: "app_groups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_app_groups_tenants_tenant_id",
                        column: x => x.tenant_id,
                        principalTable: "tenants",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "app_group_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    app_group_id = table.Column<Guid>(type: "uuid", nullable: false),
                    app_id = table.Column<Guid>(type: "uuid", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_app_group_items", x => x.id);
                    table.ForeignKey(
                        name: "FK_app_group_items_app_groups_app_group_id",
                        column: x => x.app_group_id,
                        principalTable: "app_groups",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_app_group_items_apps_app_id",
                        column: x => x.app_id,
                        principalTable: "apps",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_app_group_items_app_id",
                table: "app_group_items",
                column: "app_id");

            migrationBuilder.CreateIndex(
                name: "IX_app_group_items_group_app",
                table: "app_group_items",
                columns: new[] { "app_group_id", "app_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_app_groups_parent_id",
                table: "app_groups",
                column: "parent_id");

            migrationBuilder.CreateIndex(
                name: "IX_app_groups_tenant_id_slug",
                table: "app_groups",
                columns: new[] { "tenant_id", "slug" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "app_group_items");

            migrationBuilder.DropTable(
                name: "app_groups");
        }
    }
}
