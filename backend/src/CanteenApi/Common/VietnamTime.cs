namespace CanteenApi.Common;

/// <summary>
/// Quy đổi thời gian theo múi giờ Việt Nam (UTC+7).
/// Database luôn lưu UTC; các khái niệm "hôm nay", "doanh thu theo ngày" phải tính theo giờ Việt Nam,
/// nếu không đơn đặt lúc 6h sáng sẽ bị tính vào ngày hôm trước.
/// </summary>
public static class VietnamTime
{
    public static readonly TimeZoneInfo Zone = FindZone();

    /// <summary>Thời điểm hiện tại theo giờ Việt Nam.</summary>
    public static DateTime Now(TimeProvider clock) =>
        TimeZoneInfo.ConvertTimeFromUtc(clock.GetUtcNow().UtcDateTime, Zone);

    /// <summary>Khoảng [đầu ngày, đầu ngày hôm sau) của một ngày Việt Nam, quy ra UTC để truy vấn database.</summary>
    public static (DateTime StartUtc, DateTime EndUtc) DayRangeUtc(DateOnly day)
    {
        var startLocal = day.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified);
        var startUtc = TimeZoneInfo.ConvertTimeToUtc(startLocal, Zone);
        return (startUtc, startUtc.AddDays(1));
    }

    /// <summary>Khoảng UTC của "hôm nay" theo giờ Việt Nam.</summary>
    public static (DateTime StartUtc, DateTime EndUtc) TodayRangeUtc(TimeProvider clock) =>
        DayRangeUtc(DateOnly.FromDateTime(Now(clock)));

    private static TimeZoneInfo FindZone()
    {
        // .NET 6+ hiểu tên IANA trên mọi hệ điều hành; tên Windows để dự phòng.
        foreach (var id in new[] { "Asia/Ho_Chi_Minh", "SE Asia Standard Time" })
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
            catch (TimeZoneNotFoundException) { }
        }
        return TimeZoneInfo.CreateCustomTimeZone("ICT", TimeSpan.FromHours(7), "Indochina Time", "ICT");
    }
}
