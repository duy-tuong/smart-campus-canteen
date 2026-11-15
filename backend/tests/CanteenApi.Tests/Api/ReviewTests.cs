using System.Net;
using System.Net.Http.Json;
using CanteenApi.Common;
using CanteenApi.Dtos.Menu;
using CanteenApi.Dtos.Reviews;
using CanteenApi.Models;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Reviews;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Api;

/// <summary>Đánh giá món: quyền viết, hạn 7 ngày, điểm trung bình, hiển thị công khai, kiểm duyệt và trả lời.</summary>
public class ReviewTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    // ------------------------- Viết đánh giá -------------------------

    [Fact]
    public async Task VietDanhGia_201_CapNhatDiemMon()
    {
        var orderId = await CompletedOrderAsync(TestData.ComTam);

        var response = await ReviewAsync(AsStudent, orderId, TestData.ComTam, 5, "  Ngon, sườn mềm  ");

        var review = await response.ReadAsAsync<ReviewDto>(HttpStatusCode.Created);
        Assert.Equal((5, "Ngon, sườn mềm", true, true), (review.Rating, review.Comment, review.IsMine, review.CanEdit));
        Assert.Equal((5.00m, 1), await RatingAsync(TestData.ComTam));
    }

    [Fact]
    public async Task DonChuaHoanThanh_422()
    {
        var orderId = await TestOrders.AddAsync(Factory, TestData.ComTam, 1, CanteenApiFactory.Now.UtcDateTime.AddHours(-1));

        await (await ReviewAsync(AsStudent, orderId, TestData.ComTam, 5))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.ReviewNotAllowed);
    }

    [Fact]
    public async Task MonKhongCoTrongDon_422_DonNguoiKhac_404_DanhGiaTrung_409()
    {
        var orderId = await CompletedOrderAsync(TestData.ComTam);

        await (await ReviewAsync(AsStudent, orderId, TestData.TraSua, 5))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.ReviewNotAllowed);
        await (await ReviewAsync(AsStudent2, orderId, TestData.ComTam, 1))
            .ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);

        await (await ReviewAsync(AsStudent, orderId, TestData.ComTam, 4)).ShouldHaveStatusAsync(HttpStatusCode.Created);
        await (await ReviewAsync(AsStudent, orderId, TestData.ComTam, 5))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.ReviewExists);
    }

    [Fact]
    public async Task SoSaoSai_400()
    {
        var orderId = await CompletedOrderAsync(TestData.ComTam);
        await (await ReviewAsync(AsStudent, orderId, TestData.ComTam, 6))
            .ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task QuaHan7Ngay_KhongVietKhongSuaDuoc_NhungVanXoaDuoc()
    {
        var orderId = await CompletedOrderAsync(TestData.ComTam);
        var review = await (await ReviewAsync(AsStudent, orderId, TestData.ComTam, 3)).ReadAsAsync<ReviewDto>(HttpStatusCode.Created);
        var other = await CompletedOrderAsync(TestData.NuocSuoi);

        Factory.Clock.Advance(TimeSpan.FromDays(6));
        await (await AsStudent.PutJsonAsync($"/api/reviews/{review.Id}", new UpdateReviewRequest(4, "Sửa lại")))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);

        Factory.Clock.Advance(TimeSpan.FromDays(2)); // ngày thứ 8
        await (await AsStudent.PutJsonAsync($"/api/reviews/{review.Id}", new UpdateReviewRequest(1, "Sửa quá hạn")))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.ReviewWindowClosed);
        await (await ReviewAsync(AsStudent, other, TestData.NuocSuoi, 5))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.ReviewWindowClosed);

        await (await AsStudent.DeleteAsync($"/api/reviews/{review.Id}")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Assert.Equal((0m, 0), await RatingAsync(TestData.ComTam));
    }

    [Fact]
    public async Task ManDanhGiaDon_GopMonTrung_KemDanhGiaCuaToi_VaHan()
    {
        var orderId = await CompletedOrderAsync(TestData.ComTam);
        await TestOrders.AddItemAsync(Factory, orderId, TestData.ComTam, 2); // cùng món, dòng khác (khác tùy chọn)
        await TestOrders.AddItemAsync(Factory, orderId, TestData.NuocSuoi, 1);
        await ReviewAsync(AsStudent, orderId, TestData.NuocSuoi, 4);

        var page = await (await AsStudent.GetAsync($"/api/orders/{orderId}/reviews")).ReadAsAsync<OrderReviewsDto>();

        Assert.True(page.CanReview);
        Assert.Equal(CanteenApiFactory.Now.UtcDateTime.AddDays(7), page.ReviewDeadline);
        Assert.Equal([(TestData.ComTam, 3, false), (TestData.NuocSuoi, 1, true)],
            page.Items.Select(i => (i.FoodName, i.Quantity, i.MyReview is not null)));
    }

    // ------------------------- Điểm trung bình -------------------------

    [Fact]
    public async Task DiemTrungBinh_SauTaoSuaXoa_HienTrenMenu()
    {
        var ids = new List<int>();
        foreach (var rating in new[] { 5, 4, 3 })
        {
            var order = await CompletedOrderAsync(TestData.ComTam);
            ids.Add((await (await ReviewAsync(AsStudent, order, TestData.ComTam, rating)).ReadAsAsync<ReviewDto>(HttpStatusCode.Created)).Id);
        }
        Assert.Equal((4.00m, 3), await RatingAsync(TestData.ComTam));

        await AsStudent.PutJsonAsync($"/api/reviews/{ids[2]}", new UpdateReviewRequest(4, null)); // 5,4,4
        Assert.Equal((4.33m, 3), await RatingAsync(TestData.ComTam));

        await AsStudent.DeleteAsync($"/api/reviews/{ids[0]}"); // 4,4
        Assert.Equal((4.00m, 2), await RatingAsync(TestData.ComTam));

        var menu = await (await AsStudent.GetAsync("/api/foods?q=com%20tam")).ReadAsAsync<PagedResult<FoodSummaryDto>>();
        Assert.Equal((4.00m, 2), (menu.Items[0].AverageRating, menu.Items[0].RatingCount));
    }

    [Fact]
    public async Task MuoiDanhGiaSongSong_SoDemVaTrungBinhDung()
    {
        var orders = new List<string>();
        for (var i = 0; i < 10; i++) orders.Add(await CompletedOrderAsync(TestData.ComTam));

        // Sao 1..5 lặp lại 2 lần → trung bình 3,00.
        var responses = await Task.WhenAll(orders.Select((o, i) => ReviewAsync(AsStudent, o, TestData.ComTam, i % 5 + 1)));

        Assert.All(responses, r => Assert.Equal(HttpStatusCode.Created, r.StatusCode));
        Assert.Equal((3.00m, 10), await RatingAsync(TestData.ComTam));
    }

    // ------------------------- Hiển thị công khai -------------------------

    [Fact]
    public async Task DanhSachCongKhai_AnTen_PhanBoSao_KhongCoDanhGiaBiAn()
    {
        var reviewIds = new List<int>();
        foreach (var rating in new[] { 5, 5, 4, 1 })
        {
            var order = await CompletedOrderAsync(TestData.ComTam);
            reviewIds.Add((await (await ReviewAsync(AsStudent, order, TestData.ComTam, rating, "Bình luận")).ReadAsAsync<ReviewDto>(HttpStatusCode.Created)).Id);
        }
        await (await AsStaff.PatchJsonAsync($"/api/admin/reviews/{reviewIds[3]}/visibility", new { isHidden = true, reason = "Ngôn từ không phù hợp" }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);

        var page = await (await AsStudent2.GetAsync($"/api/foods/{await FoodIdAsync(TestData.ComTam)}/reviews"))
            .ReadAsAsync<FoodReviewPageDto>();

        Assert.Equal((4.67m, 3), (page.Summary.Average, page.Summary.Count)); // 5,5,4 — đánh giá 1 sao đã bị ẩn
        Assert.Equal([2, 1, 0, 0, 0], page.Summary.Distribution.Values);
        Assert.Equal(["5", "4", "3", "2", "1"], page.Summary.Distribution.Keys);
        Assert.Equal(3, page.Reviews.TotalCount);
        Assert.All(page.Reviews.Items, r => Assert.Equal(("An N.", false, (string?)null), (r.AuthorName, r.IsMine, r.HiddenReason)));

        var fiveStars = await (await AsStudent2.GetAsync($"/api/foods/{await FoodIdAsync(TestData.ComTam)}/reviews?rating=5"))
            .ReadAsAsync<FoodReviewPageDto>();
        Assert.Equal(2, fiveStars.Reviews.TotalCount);
    }

    [Theory]
    [InlineData("Nguyễn Văn An", "An N.")]
    [InlineData("trần thị bình", "bình T.")]
    [InlineData("Quản", "Quản")]
    [InlineData("", "Ẩn danh")]
    public void AnTenKhiHienCongKhai(string fullName, string expected) =>
        Assert.Equal(expected, ReviewService.MaskName(fullName));

    // ------------------------- Kiểm duyệt & trả lời -------------------------

    [Fact]
    public async Task AnDanhGia_TacGiaVanThayLyDo_KhongSuaDuoc_HienLaiThiTinhLaiDiem()
    {
        var order = await CompletedOrderAsync(TestData.ComTam);
        var review = await (await ReviewAsync(AsStudent, order, TestData.ComTam, 1, "Quá tệ!!!")).ReadAsAsync<ReviewDto>(HttpStatusCode.Created);

        await (await AsStaff.PatchJsonAsync($"/api/admin/reviews/{review.Id}/visibility", new { isHidden = true }))
            .ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError); // thiếu lý do
        await AsStaff.PatchJsonAsync($"/api/admin/reviews/{review.Id}/visibility", new { isHidden = true, reason = "Spam" });
        Assert.Equal((0m, 0), await RatingAsync(TestData.ComTam));

        var mine = await (await AsStudent.GetAsync("/api/users/me/reviews")).ReadAsAsync<PagedResult<ReviewDto>>();
        Assert.Equal((true, "Spam", false), (mine.Items[0].IsHidden, mine.Items[0].HiddenReason, mine.Items[0].CanEdit));
        await (await AsStudent.PutJsonAsync($"/api/reviews/{review.Id}", new UpdateReviewRequest(5, "Sửa")))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.ReviewHidden);

        await AsStaff.PatchJsonAsync($"/api/admin/reviews/{review.Id}/visibility", new { isHidden = false });
        Assert.Equal((1.00m, 1), await RatingAsync(TestData.ComTam));
    }

    [Fact]
    public async Task TraLoiDanhGia_TacGiaNhanThongBao_GoTraLoi()
    {
        var order = await CompletedOrderAsync(TestData.ComTam);
        var review = await (await ReviewAsync(AsStudent, order, TestData.ComTam, 3, "Hơi mặn")).ReadAsAsync<ReviewDto>(HttpStatusCode.Created);

        var replied = await (await AsStaff.PutJsonAsync($"/api/admin/reviews/{review.Id}/reply", new { reply = "Cảm ơn bạn, bếp sẽ điều chỉnh!" }))
            .ReadAsAsync<ReviewDto>();
        Assert.Equal(("Cảm ơn bạn, bếp sẽ điều chỉnh!", "Nguyễn Văn An"), (replied.StaffReply, replied.AuthorName)); // staff thấy tên đầy đủ

        var notifications = await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>();
        var n = notifications.Items[0];
        Assert.Equal((NotificationType.Review, "Căn-tin đã trả lời đánh giá của bạn"), (n.Type, n.Title));
        Assert.Contains("Cơm tấm sườn bì chả", n.Body);
        Assert.Contains(n.Id, Factory.Realtime.Notifications);

        var removed = await (await AsStaff.DeleteAsync($"/api/admin/reviews/{review.Id}/reply")).ReadAsAsync<ReviewDto>();
        Assert.Null(removed.StaffReply);
    }

    [Fact]
    public async Task QuanLyDanhGia_LocChuaTraLoi_TimKhongDau_SinhVien403()
    {
        var o1 = await CompletedOrderAsync(TestData.ComTam);
        var o2 = await CompletedOrderAsync(TestData.NuocSuoi);
        var r1 = await (await ReviewAsync(AsStudent, o1, TestData.ComTam, 2, "Cơm hơi nguội")).ReadAsAsync<ReviewDto>(HttpStatusCode.Created);
        await ReviewAsync(AsStudent, o2, TestData.NuocSuoi, 5, "Mát lạnh");
        await AsStaff.PutJsonAsync($"/api/admin/reviews/{r1.Id}/reply", new { reply = "Xin lỗi bạn!" });

        await (await AsStudent.GetAsync("/api/admin/reviews")).ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);

        var unanswered = await (await AsStaff.GetAsync("/api/admin/reviews?hasReply=false")).ReadAsAsync<PagedResult<ReviewDto>>();
        Assert.Equal("Mát lạnh", Assert.Single(unanswered.Items).Comment);

        var search = await (await AsStaff.GetAsync("/api/admin/reviews?q=com%20hoi%20nguoi")).ReadAsAsync<PagedResult<ReviewDto>>();
        Assert.Equal(r1.Id, Assert.Single(search.Items).Id);
    }

    // ------------------------- Hỗ trợ -------------------------

    /// <summary>Đơn đã hoàn thành của sinh viên 1 (có mốc Completed trong lịch sử lúc "bây giờ").</summary>
    private async Task<string> CompletedOrderAsync(string food)
    {
        var id = await TestOrders.AddAsync(Factory, food, 1, CanteenApiFactory.Now.UtcDateTime.AddHours(-1), OrderStatus.Completed);
        await Factory.WithDbAsync(async db =>
        {
            db.OrderStatusHistory.Add(new OrderStatusHistory
            {
                OrderId = id, FromStatus = OrderStatus.Ready, ToStatus = OrderStatus.Completed,
                ChangedByUserId = TestData.Staff, ChangedAt = Factory.Clock.GetUtcNow().UtcDateTime,
            });
            await db.SaveChangesAsync();
        });
        return id;
    }

    private async Task<HttpResponseMessage> ReviewAsync(HttpClient client, string orderId, string food, int rating, string? comment = null) =>
        await client.PostAsJsonAsync($"/api/orders/{orderId}/reviews",
            new CreateReviewRequest(await FoodIdAsync(food), rating, comment), HttpExtensions.Json);

    private Task<int> FoodIdAsync(string name) =>
        Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == name).Select(f => f.Id).SingleAsync());

    private Task<(decimal, int)> RatingAsync(string food) => Factory.WithDbAsync(async db =>
    {
        var f = await db.Foods.AsNoTracking().SingleAsync(x => x.Name == food);
        return (f.AverageRating, f.RatingCount);
    });
}
