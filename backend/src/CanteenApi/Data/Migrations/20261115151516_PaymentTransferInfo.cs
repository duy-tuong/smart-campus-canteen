using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CanteenApi.Data.Migrations
{
    /// <inheritdoc />
    public partial class PaymentTransferInfo : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "BankAccountName",
                table: "Payments",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BankAccountNumber",
                table: "Payments",
                type: "varchar(30)",
                unicode: false,
                maxLength: 30,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BankBin",
                table: "Payments",
                type: "varchar(20)",
                unicode: false,
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TransferContent",
                table: "Payments",
                type: "varchar(50)",
                unicode: false,
                maxLength: 50,
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "ChangedByUserId",
                table: "OrderStatusHistory",
                type: "nvarchar(128)",
                maxLength: 128,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(128)",
                oldMaxLength: 128);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BankAccountName",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "BankAccountNumber",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "BankBin",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "TransferContent",
                table: "Payments");

            migrationBuilder.AlterColumn<string>(
                name: "ChangedByUserId",
                table: "OrderStatusHistory",
                type: "nvarchar(128)",
                maxLength: 128,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "nvarchar(128)",
                oldMaxLength: 128,
                oldNullable: true);
        }
    }
}
