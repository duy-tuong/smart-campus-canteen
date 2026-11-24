using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using CanteenApi.Services.Ordering;
using CanteenApi.Services.Reviews;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Dev;

public sealed record HistorySeedResult(
    DateOnly From, DateOnly To, int Orders, int Completed, int Cancelled, long Revenue,
    int Reviews, int Replies, int HiddenReviews, int VirtualStudents);

/// <summary>
/// Sinh dữ liệu lịch sử N ngày qua (chỉ môi trường Development) để biểu đồ thống kê và điểm sao
/// có số liệu khi demo / chụp ảnh báo cáo.
///
///  - Ngẫu nhiên CÓ THỂ LẶP LẠI (seed cố định): chạy lại cùng ngày cho cùng số liệu.
///  - Phân bổ theo giờ cao điểm thực tế; ngày thường đông, cuối tuần vắng.
///  - Giá, tùy chọn, tổng tiền tính đúng như đơn thật → thỏa mọi CHECK/UNIQUE của database.
///  - Đánh dấu bằng ClientRequestId "hist-…" và người dùng ảo "hist-student-…" để xóa sạch khi reset.
///  - Không đụng tới hôm nay: dữ liệu vận hành thật trong ngày không bị lẫn.
/// </summary>
public sealed class HistorySeeder(CanteenDbContext db, ReviewService reviews, TimeProvider clock, ILogger<HistorySeeder> logger)
{
    private const int Seed = 20261116;
    public const string HistoryPrefix = "hist-";
    public const string HistoryVoucherCode = "KHAITRUONG15";

    // Món phổ biến được chọn nhiều hơn (trọng số); món không có trong bảng = 1.
    private static readonly Dictionary<string, int> Popularity = new()
    {
        ["Cơm gà xối mỡ"] = 10, ["Cơm tấm sườn bì chả"] = 9, ["Phở bò tái"] = 7, ["Bánh mì thịt"] = 8,
        ["Trà sữa trân châu"] = 9, ["Cà phê sữa đá"] = 8, ["Trà đào cam sả"] = 6, ["Bún bò Huế"] = 5,
        ["Cơm chiên dương châu"] = 4, ["Nước suối"] = 5, ["Khoai tây chiên"] = 4, ["Mì xào hải sản"] = 3,
        ["Cơm bò lúc lắc"] = 3, ["Xúc xích nướng"] = 3, ["Bánh flan"] = 3, ["Hủ tiếu Nam Vang"] = 3,
        ["Nước ép cam"] = 2, ["Cơm chay thập cẩm"] = 2,
    };

    // Khung giờ (giờ VN) và tỷ trọng: sáng sớm, ra chơi, trưa (đông nhất), chiều tan học, giờ khác.
    private static readonly (TimeOnly Start, TimeOnly End, int Weight)[] Slots =
    [
        (new(6, 30), new(7, 45), 20), (new(9, 30), new(10, 0), 10), (new(11, 0), new(12, 45), 45),
        (new(16, 30), new(17, 45), 20), (new(13, 0), new(16, 0), 5),
    ];

    private static readonly string[] VirtualNames =
    [
        "Lê Minh Khang", "Phạm Thu Hà", "Võ Quốc Bảo", "Đặng Ngọc Mai", "Huỳnh Gia Huy",
        "Bùi Thanh Tâm", "Đỗ Khánh Linh", "Hồ Đức Thịnh",
    ];

    private static readonly string[] CancelReasons =
    [
        "Đặt nhầm món", "Hết giờ nghỉ, không kịp lấy", "Đổi ý không ăn nữa", "Quá hạn thanh toán", "Hết nguyên liệu",
    ];

    private static readonly Dictionary<int, string[]> Comments = new()
    {
        [5] = ["Rất ngon, sẽ ủng hộ tiếp!", "Món ăn nóng hổi, vừa miệng.", "Phần ăn đầy đặn, giá hợp lý.", "Ngon tuyệt, lấy món nhanh.", null!],
        [4] = ["Ngon, nhưng hơi đông lúc trưa.", "Ổn áp, giá sinh viên.", "Khá ngon, nên thêm rau.", null!],
        [3] = ["Bình thường, hơi nguội.", "Tạm được, hơi ít.", "Vị hơi nhạt."],
        [2] = ["Hơi mặn, chờ lâu.", "Phần ăn ít so với giá."],
        [1] = ["Đợi quá lâu mới có món.", "Món bị nguội, không ngon."],
    };

    public async Task<HistorySeedResult> SeedAsync(int days, bool reset, CancellationToken ct)
    {
        if (await db.Orders.AnyAsync(o => o.ClientRequestId != null && o.ClientRequestId.StartsWith(HistoryPrefix), ct))
        {
            if (!reset)
                throw new ConflictException(ErrorCodes.Duplicate, "Đã có dữ liệu lịch sử. Gọi lại với ?reset=true để sinh lại.");
            await ResetAsync(ct);
        }

        var staff = await db.Users.AsNoTracking().Where(u => u.Role == UserRole.Staff && u.IsActive).Select(u => u.Id).FirstOrDefaultAsync(ct)
            ?? throw new BusinessRuleException(ErrorCodes.ValidationError, "Chưa có tài khoản staff — chạy POST /api/dev/accounts trước.");
        var foods = await db.Foods.AsNoTracking().Where(f => !f.IsDeleted)
            .Include(f => f.OptionGroups).ThenInclude(g => g.Options)
            .OrderBy(f => f.Id).ToListAsync(ct);
        if (foods.Count == 0)
            throw new BusinessRuleException(ErrorCodes.ValidationError, "Chưa có thực đơn — chạy POST /api/dev/seed trước.");

        var random = new Random(Seed);
        var today = DateOnly.FromDateTime(VietnamTime.Now(clock));
        var from = today.AddDays(-days);
        var to = today.AddDays(-1);

        db.PreserveTimestamps = true;
        try
        {
            var students = await PrepareStudentsAsync(ct);
            var voucher = await PrepareVoucherAsync(from, today, ct);
            var foodWeights = foods.Select(f => Popularity.GetValueOrDefault(f.Name, 1)).ToArray();

            var orders = new List<Order>();
            var reviewList = new List<Review>();
            var sequence = 0;

            // Ngày nào đã có đơn thật thì đánh số tiếp sau mã lớn nhất (UNIQUE PickupDate + PickupCode).
            var existingCodes = await db.Orders.AsNoTracking()
                .Where(o => o.PickupDate >= from && o.PickupDate <= to)
                .Select(o => new { o.PickupDate, o.PickupCode }).ToListAsync(ct);
            var lastCode = existingCodes.GroupBy(x => x.PickupDate)
                .ToDictionary(g => g.Key, g => g.Max(x => int.TryParse(x.PickupCode, out var n) ? n : 0));

            for (var day = from; day <= to; day = day.AddDays(1))
            {
                var weekend = day.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;
                var count = weekend ? random.Next(6, 13) : random.Next(22, 41);

                var times = Enumerable.Range(0, count).Select(_ => RandomTime(random, day)).Order().ToList();
                for (var i = 0; i < times.Count; i++)
                {
                    var number = lastCode.GetValueOrDefault(day) + i + 1;
                    var order = BuildOrder(random, day, number, times[i], students, foods, foodWeights, staff, voucher, ref sequence);
                    orders.Add(order);
                    if (order.Status == OrderStatus.Completed && random.NextDouble() < 0.4)
                        reviewList.AddRange(BuildReviews(random, order, staff, today));
                }
            }

            db.Orders.AddRange(orders);
            db.Reviews.AddRange(reviewList);
            await db.SaveChangesAsync(ct);

            if (voucher is not null)
            {
                var used = orders.Count(o => o.VoucherId == voucher.Id && o.Status != OrderStatus.Cancelled);
                await db.Vouchers.Where(v => v.Id == voucher.Id).ExecuteUpdateAsync(s => s.SetProperty(v => v.UsedCount, used), ct);
            }
            await reviews.RecalculateAllFoodRatingsAsync(ct);

            var completed = orders.Where(o => o.Status == OrderStatus.Completed).ToList();
            var result = new HistorySeedResult(from, to, orders.Count, completed.Count, orders.Count - completed.Count,
                completed.Sum(o => (long)o.TotalAmount), reviewList.Count,
                reviewList.Count(r => r.StaffReply != null), reviewList.Count(r => r.IsHidden), VirtualNames.Length);
            logger.LogInformation("Seeded history {@Result}", result);
            return result;
        }
        finally
        {
            db.PreserveTimestamps = false;
        }
    }

    /// <summary>Xóa đơn lịch sử (cascade: món, tùy chọn, lịch sử, thanh toán, đánh giá), voucher và người dùng ảo.</summary>
    public async Task ResetAsync(CancellationToken ct)
    {
        await db.Orders.Where(o => o.ClientRequestId != null && o.ClientRequestId.StartsWith(HistoryPrefix)).ExecuteDeleteAsync(ct);
        await db.Vouchers.Where(v => v.Code == HistoryVoucherCode && !v.Orders.Any()).ExecuteDeleteAsync(ct);
        await db.Users.Where(u => u.Id.StartsWith(HistoryPrefix) && !u.Orders.Any()).ExecuteDeleteAsync(ct);
        await reviews.RecalculateAllFoodRatingsAsync(ct);
    }

    // ============================ Dựng dữ liệu ============================

    private async Task<List<string>> PrepareStudentsAsync(CancellationToken ct)
    {
        var existing = await db.Users.AsNoTracking()
            .Where(u => u.Role == UserRole.Student && u.IsActive && !u.Id.StartsWith(HistoryPrefix))
            .OrderBy(u => u.Email).Select(u => u.Id).ToListAsync(ct);

        var virtualIds = new List<string>();
        for (var i = 0; i < VirtualNames.Length; i++)
        {
            var id = $"{HistoryPrefix}student-{i + 1:00}";
            virtualIds.Add(id);
            if (await db.Users.AnyAsync(u => u.Id == id, ct)) continue;
            db.Users.Add(new AppUser
            {
                Id = id,
                Email = $"hist{i + 1:00}@smartcanteen.vn",
                FullName = VirtualNames[i],
                StudentCode = $"00234101{i + 50:00}",
                Role = UserRole.Student,
                CreatedAt = clock.GetUtcNow().UtcDateTime.AddDays(-60),
                UpdatedAt = clock.GetUtcNow().UtcDateTime.AddDays(-60),
            });
        }
        await db.SaveChangesAsync(ct);

        // Tài khoản demo thật được chọn nhiều hơn (lặp 3 lần) để lịch sử "Đơn của tôi" có nhiều đơn khi demo.
        return [.. existing, .. existing, .. existing, .. virtualIds];
    }

    /// <summary>Voucher của đợt khai trường, chỉ hiệu lực trong khoảng lịch sử (hôm nay đã hết hạn).</summary>
    private async Task<Voucher?> PrepareVoucherAsync(DateOnly from, DateOnly today, CancellationToken ct)
    {
        var start = TimeZoneInfo.ConvertTimeToUtc(from.ToDateTime(TimeOnly.MinValue), VietnamTime.Zone);
        var end = TimeZoneInfo.ConvertTimeToUtc(today.ToDateTime(TimeOnly.MinValue), VietnamTime.Zone);
        var voucher = await db.Vouchers.FirstOrDefaultAsync(v => v.Code == HistoryVoucherCode, ct);
        if (voucher is null)
        {
            voucher = new Voucher
            {
                Code = HistoryVoucherCode, Description = "Khai trường: giảm 15% tối đa 10.000đ cho đơn từ 30.000đ",
                DiscountType = DiscountType.Percent, DiscountValue = 15, MaxDiscount = 10_000, MinOrderAmount = 30_000,
                StartAt = start, EndAt = end, CreatedAt = start, UpdatedAt = start,
            };
            db.Vouchers.Add(voucher);
            await db.SaveChangesAsync(ct);
        }
        return voucher;
    }

    private Order BuildOrder(
        Random random, DateOnly day, int number, DateTime createdUtc, List<string> students, List<Food> foods,
        int[] foodWeights, string staff, Voucher? voucher, ref int sequence)
    {
        var userId = students[random.Next(students.Count)];
        var method = random.NextDouble() < 0.3 ? PaymentMethod.BankTransfer : PaymentMethod.Cash;
        var cancelled = random.NextDouble() < 0.08;

        var lineCount = random.NextDouble() switch { < 0.55 => 1, < 0.9 => 2, _ => 3 };
        var picked = new HashSet<int>();
        var items = new List<OrderItem>();
        while (items.Count < lineCount)
        {
            var food = foods[WeightedIndex(random, foodWeights)];
            if (!picked.Add(food.Id)) continue;
            var options = PickOptions(random, food);
            var optionsPrice = options.Sum(o => o.ExtraPrice);
            var quantity = random.NextDouble() switch { < 0.8 => 1, < 0.95 => 2, _ => 3 };
            items.Add(new OrderItem
            {
                FoodId = food.Id, FoodName = food.Name, UnitPrice = food.Price, OptionsPrice = optionsPrice,
                Quantity = quantity, LineTotal = (food.Price + optionsPrice) * quantity, Options = options,
            });
        }

        var subtotal = items.Sum(i => i.LineTotal);
        var useVoucher = !cancelled && voucher is not null && subtotal >= voucher.MinOrderAmount && random.NextDouble() < 0.15;
        var discount = useVoucher ? VoucherService.CalculateDiscount(voucher!, subtotal) : 0;
        var total = subtotal - discount;

        var maxPrep = items.Max(i => foods.First(f => f.Id == i.FoodId).PrepTimeMinutes);
        var cookingAt = createdUtc.AddMinutes(random.Next(1, 5));
        var readyAt = cookingAt.AddMinutes(maxPrep + random.Next(0, 6));
        var completedAt = readyAt.AddMinutes(random.Next(2, 20));
        var cancelledAt = createdUtc.AddMinutes(random.Next(2, 16));
        var endAt = cancelled ? cancelledAt : completedAt;

        var orderId = Guid.NewGuid().ToString();
        var history = new List<OrderStatusHistory>
        {
            new() { FromStatus = null, ToStatus = OrderStatus.Received, ChangedByUserId = userId, Note = "Đặt món", ChangedAt = createdUtc },
        };
        string? cancelReason = null;
        if (cancelled)
        {
            cancelReason = method == PaymentMethod.BankTransfer ? "Quá hạn thanh toán" : CancelReasons[random.Next(CancelReasons.Length - 2)];
            var bySystem = cancelReason == "Quá hạn thanh toán";
            history.Add(new() { FromStatus = OrderStatus.Received, ToStatus = OrderStatus.Cancelled,
                ChangedByUserId = bySystem ? null : userId, Note = cancelReason, ChangedAt = cancelledAt });
        }
        else
        {
            history.Add(new() { FromStatus = OrderStatus.Received, ToStatus = OrderStatus.Cooking, ChangedByUserId = staff, ChangedAt = cookingAt });
            history.Add(new() { FromStatus = OrderStatus.Cooking, ToStatus = OrderStatus.Ready, ChangedByUserId = staff, ChangedAt = readyAt });
            history.Add(new() { FromStatus = OrderStatus.Ready, ToStatus = OrderStatus.Completed, ChangedByUserId = staff, ChangedAt = completedAt });
        }

        var paidAt = cancelled ? (DateTime?)null : method == PaymentMethod.Cash ? completedAt : createdUtc.AddMinutes(random.Next(1, 4));
        var code = number.ToString("000");
        sequence++;

        return new Order
        {
            Id = orderId,
            PickupDate = day,
            PickupCode = code,
            ClientRequestId = $"{HistoryPrefix}{sequence:00000}",
            UserId = userId,
            Status = cancelled ? OrderStatus.Cancelled : OrderStatus.Completed,
            PaymentMethod = method,
            PaymentStatus = cancelled ? PaymentStatus.Failed : PaymentStatus.Paid,
            PaidAt = paidAt,
            Subtotal = subtotal,
            DiscountAmount = discount,
            TotalAmount = total,
            VoucherId = useVoucher ? voucher!.Id : null,
            VoucherCode = useVoucher ? voucher!.Code : null,
            EstimatedReadyAt = createdUtc.AddMinutes(maxPrep + 2),
            CancelReason = cancelReason,
            CreatedAt = createdUtc,
            UpdatedAt = endAt,
            Items = items,
            StatusHistory = history,
            Payments =
            {
                new Payment
                {
                    Method = method, Amount = total, CreatedAt = createdUtc,
                    Status = cancelled ? PaymentStatus.Failed : PaymentStatus.Paid,
                    PaidAt = paidAt,
                    TransactionRef = cancelled ? null
                        : method == PaymentMethod.Cash ? $"CASH-{day:yyMMdd}-{code}" : $"HIST-{day:yyMMdd}-{code}",
                },
            },
        };
    }

    /// <summary>Chọn tùy chọn hợp lệ: nhóm bắt buộc chọn đủ MinSelect, nhóm tùy ý có 30% khả năng chọn 1.</summary>
    private static List<OrderItemOption> PickOptions(Random random, Food food)
    {
        var result = new List<OrderItemOption>();
        foreach (var group in food.OptionGroups.OrderBy(g => g.SortOrder))
        {
            var available = group.Options.Where(o => o.IsAvailable).OrderBy(o => o.SortOrder).ToList();
            var count = group.MinSelect > 0 ? group.MinSelect : random.NextDouble() < 0.3 ? 1 : 0;
            foreach (var option in available.OrderBy(_ => random.Next()).Take(Math.Min(count, group.MaxSelect)))
                result.Add(new OrderItemOption { GroupName = group.Name, OptionName = option.Name, ExtraPrice = option.ExtraPrice });
        }
        return result;
    }

    private IEnumerable<Review> BuildReviews(Random random, Order order, string staff, DateOnly today)
    {
        var todayStartUtc = TimeZoneInfo.ConvertTimeToUtc(today.ToDateTime(TimeOnly.MinValue), VietnamTime.Zone);
        var completedAt = order.StatusHistory.Max(h => h.ChangedAt);

        foreach (var item in order.Items.Take(random.NextDouble() < 0.25 ? 2 : 1))
        {
            var rating = random.NextDouble() switch { < 0.5 => 5, < 0.8 => 4, < 0.92 => 3, < 0.97 => 2, _ => 1 };
            var pool = Comments[rating];
            var createdAt = completedAt.AddMinutes(random.Next(10, 60 * 24));
            if (createdAt >= todayStartUtc) createdAt = completedAt.AddMinutes(5);

            var review = new Review
            {
                OrderId = order.Id, FoodId = item.FoodId!.Value, UserId = order.UserId, Rating = (byte)rating,
                Comment = pool[random.Next(pool.Length)], CreatedAt = createdAt, UpdatedAt = createdAt,
            };

            if (rating == 1 && random.NextDouble() < 0.3)
            {
                review.Comment = "Spam quảng cáo bán hàng online!!!";
                review.IsHidden = true;
                review.HiddenReason = "Nội dung quảng cáo, không liên quan tới món ăn";
            }
            else if (rating <= 3 ? random.NextDouble() < 0.6 : random.NextDouble() < 0.08)
            {
                review.StaffReply = rating <= 3
                    ? "Cảm ơn góp ý của bạn, căn-tin sẽ cải thiện ạ!"
                    : "Cảm ơn bạn đã ủng hộ căn-tin!";
                review.RepliedAt = createdAt.AddHours(random.Next(1, 12));
                review.RepliedByUserId = staff;
            }
            yield return review;
        }
    }

    private static DateTime RandomTime(Random random, DateOnly day)
    {
        var slot = Slots[WeightedIndex(random, Slots.Select(s => s.Weight).ToArray())];
        var minutes = (int)(slot.End - slot.Start).TotalMinutes;
        var local = day.ToDateTime(slot.Start.AddMinutes(random.Next(minutes))).AddSeconds(random.Next(60));
        return TimeZoneInfo.ConvertTimeToUtc(local, VietnamTime.Zone);
    }

    private static int WeightedIndex(Random random, int[] weights)
    {
        var roll = random.Next(weights.Sum());
        for (var i = 0; i < weights.Length; i++)
        {
            roll -= weights[i];
            if (roll < 0) return i;
        }
        return weights.Length - 1;
    }
}
