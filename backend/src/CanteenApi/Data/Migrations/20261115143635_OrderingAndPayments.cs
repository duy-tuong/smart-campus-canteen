using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CanteenApi.Data.Migrations
{
    /// <inheritdoc />
    public partial class OrderingAndPayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "CheckoutUrl",
                table: "Payments",
                type: "varchar(500)",
                unicode: false,
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiresAt",
                table: "Payments",
                type: "datetime2(3)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PaymentLinkId",
                table: "Payments",
                type: "varchar(64)",
                unicode: false,
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "ProviderOrderCode",
                table: "Payments",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "QrCode",
                table: "Payments",
                type: "varchar(1000)",
                unicode: false,
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ClientRequestId",
                table: "Orders",
                type: "varchar(64)",
                unicode: false,
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "PaidAt",
                table: "Orders",
                type: "datetime2(3)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PaymentStatus",
                table: "Orders",
                type: "varchar(20)",
                unicode: false,
                maxLength: 20,
                nullable: false,
                defaultValue: "Pending");

            migrationBuilder.AddColumn<DateOnly>(
                name: "PickupDate",
                table: "Orders",
                type: "date",
                nullable: false,
                defaultValue: new DateOnly(1, 1, 1));

            // Điền dữ liệu cho đơn đã có: ngày nhận món = ngày theo giờ Việt Nam (UTC+7) của CreatedAt,
            // phải chạy TRƯỚC khi tạo UNIQUE(PickupDate, PickupCode).
            migrationBuilder.Sql("UPDATE Orders SET PickupDate = CAST(DATEADD(HOUR, 7, CreatedAt) AS date);");

            migrationBuilder.CreateIndex(
                name: "IX_Payments_ProviderOrderCode",
                table: "Payments",
                column: "ProviderOrderCode",
                unique: true,
                filter: "[ProviderOrderCode] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Payments_ProviderMethod",
                table: "Payments",
                sql: "[ProviderOrderCode] IS NULL OR [Method] = 'BankTransfer'");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Payments_ProviderOrderCode",
                table: "Payments",
                sql: "[ProviderOrderCode] IS NULL OR [ProviderOrderCode] > 0");

            migrationBuilder.CreateIndex(
                name: "IX_Orders_PickupDate_PickupCode",
                table: "Orders",
                columns: new[] { "PickupDate", "PickupCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Orders_UserId_ClientRequestId",
                table: "Orders",
                columns: new[] { "UserId", "ClientRequestId" },
                unique: true,
                filter: "[ClientRequestId] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Orders_PaidAt",
                table: "Orders",
                sql: "[PaymentStatus] NOT IN ('Paid', 'Refunded') OR [PaidAt] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Orders_PaymentStatus",
                table: "Orders",
                sql: "[PaymentStatus] IN ('Pending', 'Paid', 'Refunded', 'Failed')");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Payments_ProviderOrderCode",
                table: "Payments");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Payments_ProviderMethod",
                table: "Payments");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Payments_ProviderOrderCode",
                table: "Payments");

            migrationBuilder.DropIndex(
                name: "IX_Orders_PickupDate_PickupCode",
                table: "Orders");

            migrationBuilder.DropIndex(
                name: "IX_Orders_UserId_ClientRequestId",
                table: "Orders");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Orders_PaidAt",
                table: "Orders");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Orders_PaymentStatus",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "CheckoutUrl",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "ExpiresAt",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "PaymentLinkId",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "ProviderOrderCode",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "QrCode",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "ClientRequestId",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "PaidAt",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "PaymentStatus",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "PickupDate",
                table: "Orders");
        }
    }
}
