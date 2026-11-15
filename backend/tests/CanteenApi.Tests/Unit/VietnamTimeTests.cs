using CanteenApi.Common;
using Microsoft.Extensions.Time.Testing;

namespace CanteenApi.Tests.Unit;

/// <summary>"Hôm nay" phải tính theo giờ Việt Nam (UTC+7), không theo UTC của database.</summary>
public class VietnamTimeTests
{
    [Fact]
    public void DayRangeUtc_BatDauLuc17hUtcNgayHomTruoc()
    {
        var (start, end) = VietnamTime.DayRangeUtc(new DateOnly(2026, 11, 16));

        Assert.Equal(new DateTime(2026, 11, 15, 17, 0, 0), start);
        Assert.Equal(new DateTime(2026, 11, 16, 17, 0, 0), end);
    }

    [Theory]
    [InlineData("2026-11-15T16:59:00Z", 15)] // 23:59 ngày 15 giờ VN
    [InlineData("2026-11-15T17:00:00Z", 16)] // 00:00 ngày 16 giờ VN
    [InlineData("2026-11-16T03:00:00Z", 16)] // 10:00 ngày 16 giờ VN
    public void TodayRangeUtc_TheoGioVietNam(string utcNow, int expectedVietnamDay)
    {
        var clock = new FakeTimeProvider(DateTimeOffset.Parse(utcNow));

        var (start, _) = VietnamTime.TodayRangeUtc(clock);

        var expected = VietnamTime.DayRangeUtc(new DateOnly(2026, 11, expectedVietnamDay)).StartUtc;
        Assert.Equal(expected, start);
    }
}
