using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CanteenApi.Data.Migrations
{
    /// <inheritdoc />
    public partial class ReviewModeration : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Reviews_FoodId_CreatedAt",
                table: "Reviews");

            migrationBuilder.AddColumn<string>(
                name: "HiddenReason",
                table: "Reviews",
                type: "nvarchar(300)",
                maxLength: 300,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsHidden",
                table: "Reviews",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "RepliedAt",
                table: "Reviews",
                type: "datetime2(3)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RepliedByUserId",
                table: "Reviews",
                type: "nvarchar(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StaffReply",
                table: "Reviews",
                type: "nvarchar(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Reviews_FoodId_IsHidden_CreatedAt",
                table: "Reviews",
                columns: new[] { "FoodId", "IsHidden", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_Reviews_RepliedByUserId",
                table: "Reviews",
                column: "RepliedByUserId");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Reviews_HiddenReason",
                table: "Reviews",
                sql: "[IsHidden] = 0 OR [HiddenReason] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Reviews_Reply",
                table: "Reviews",
                sql: "([StaffReply] IS NULL AND [RepliedAt] IS NULL AND [RepliedByUserId] IS NULL) OR ([StaffReply] IS NOT NULL AND [RepliedAt] IS NOT NULL AND [RepliedByUserId] IS NOT NULL)");

            migrationBuilder.AddForeignKey(
                name: "FK_Reviews_Users_RepliedByUserId",
                table: "Reviews",
                column: "RepliedByUserId",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Reviews_Users_RepliedByUserId",
                table: "Reviews");

            migrationBuilder.DropIndex(
                name: "IX_Reviews_FoodId_IsHidden_CreatedAt",
                table: "Reviews");

            migrationBuilder.DropIndex(
                name: "IX_Reviews_RepliedByUserId",
                table: "Reviews");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Reviews_HiddenReason",
                table: "Reviews");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Reviews_Reply",
                table: "Reviews");

            migrationBuilder.DropColumn(
                name: "HiddenReason",
                table: "Reviews");

            migrationBuilder.DropColumn(
                name: "IsHidden",
                table: "Reviews");

            migrationBuilder.DropColumn(
                name: "RepliedAt",
                table: "Reviews");

            migrationBuilder.DropColumn(
                name: "RepliedByUserId",
                table: "Reviews");

            migrationBuilder.DropColumn(
                name: "StaffReply",
                table: "Reviews");

            migrationBuilder.CreateIndex(
                name: "IX_Reviews_FoodId_CreatedAt",
                table: "Reviews",
                columns: new[] { "FoodId", "CreatedAt" });
        }
    }
}
