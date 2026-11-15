using CanteenApi.Common;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>Chèn đơn hàng trực tiếp vào database test để dựng kịch bản (số suất đã bán, lượt voucher...).</summary>
public static class TestOrders
{
    private static int _sequence;

    public static Task<string> AddAsync(
        CanteenApiFactory factory,
        string foodName,
        int quantity,
        DateTime createdAtUtc,
        OrderStatus status = OrderStatus.Received,
        string userId = TestData.Student1,
        string? voucherCode = null) =>
        factory.WithDbAsync(async db =>
        {
            var food = await db.Foods.SingleAsync(f => f.Name == foodName);
            var voucher = voucherCode is null ? null : await db.Vouchers.SingleAsync(v => v.Code == voucherCode);
            var id = Guid.NewGuid().ToString();
            var total = food.Price * quantity;
            var discount = voucher is null ? 0 : Math.Min(1000, total);

            db.Orders.Add(new Order
            {
                Id = id,
                // Mã nhận món dạng số, duy nhất (UNIQUE PickupDate + PickupCode); dải 500+ để không trùng mã do API cấp.
                PickupCode = (500 + Interlocked.Increment(ref _sequence) % 400).ToString("000"),
                PickupDate = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(createdAtUtc, VietnamTime.Zone)),
                UserId = userId,
                Status = status,
                Subtotal = total,
                DiscountAmount = discount,
                TotalAmount = total - discount,
                VoucherId = voucher?.Id,
                VoucherCode = voucher?.Code,
                CancelReason = status == OrderStatus.Cancelled ? "Khách hủy" : null,
                Items =
                {
                    new OrderItem
                    {
                        FoodId = food.Id, FoodName = food.Name, UnitPrice = food.Price,
                        Quantity = quantity, LineTotal = total,
                    },
                },
            });
            await db.SaveChangesAsync();

            // SaveChanges tự gán CreatedAt = giờ thật → ghi đè bằng thời điểm của kịch bản test.
            await db.Orders.Where(o => o.Id == id).ExecuteUpdateAsync(s => s.SetProperty(o => o.CreatedAt, createdAtUtc));
            return id;
        });

    /// <summary>Thêm một dòng món vào đơn đã có (giữ đúng ràng buộc tổng tiền của đơn).</summary>
    public static Task AddItemAsync(CanteenApiFactory factory, string orderId, string foodName, int quantity) =>
        factory.WithDbAsync(async db =>
        {
            var food = await db.Foods.SingleAsync(f => f.Name == foodName);
            var order = await db.Orders.SingleAsync(o => o.Id == orderId);
            var line = food.Price * quantity;
            db.OrderItems.Add(new OrderItem
            {
                OrderId = orderId, FoodId = food.Id, FoodName = food.Name, UnitPrice = food.Price,
                Quantity = quantity, LineTotal = line,
            });
            order.Subtotal += line;
            order.TotalAmount += line;
            await db.SaveChangesAsync();
        });
}
