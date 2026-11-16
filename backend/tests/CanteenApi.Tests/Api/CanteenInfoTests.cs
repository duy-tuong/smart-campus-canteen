using CanteenApi.Controllers;
using CanteenApi.Tests.Infrastructure;

namespace CanteenApi.Tests.Api;

/// <summary>GET /api/canteen/info — giờ mở cửa và quy tắc đặt món cho app.</summary>
public class CanteenInfoTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task KhongCanDangNhap_TraVeGioMoCuaVaQuyTac()
    {
        var info = await (await Anonymous.GetAsync("/api/canteen/info")).ReadAsAsync<CanteenInfoDto>();

        Assert.Equal(("06:30", "19:00"), (info.OpenTime, info.CloseTime));
        Assert.True(info.IsOpen); // 10:00 sáng giờ VN
        Assert.Equal(CanteenApiFactory.Now.UtcDateTime, info.ServerTime);
        Assert.Equal((10, 15, 3, 20), (info.MinPickupLeadMinutes, info.UnpaidTransferTimeoutMinutes,
            info.MaxActiveOrdersPerUser, info.MaxLinesPerOrder));
        Assert.True(info.BankTransferEnabled);
    }

    [Theory]
    [InlineData(23, 29, false)] // 06:29 VN (hôm sau) — chưa mở
    [InlineData(23, 30, true)]  // 06:30 VN — vừa mở
    [InlineData(11, 59, true)]  // 18:59 VN
    [InlineData(12, 0, false)]  // 19:00 VN — đã đóng
    public async Task IsOpen_TheoGioVietNam(int utcHour, int utcMinute, bool expected)
    {
        Factory.Clock.Set(new DateTimeOffset(2026, 11, 16, utcHour, utcMinute, 0, TimeSpan.Zero));
        var info = await (await Anonymous.GetAsync("/api/canteen/info")).ReadAsAsync<CanteenInfoDto>();
        Assert.Equal(expected, info.IsOpen);
    }

    [Fact]
    public async Task TatPayOS_BaoKhongNhanChuyenKhoan()
    {
        Factory.Payments.Enabled = false;
        var info = await (await Anonymous.GetAsync("/api/canteen/info")).ReadAsAsync<CanteenInfoDto>();
        Assert.False(info.BankTransferEnabled);
    }
}
