using System.Net;
using CanteenApi.Common;
using CanteenApi.Dtos.Menu;
using CanteenApi.Tests.Infrastructure;

namespace CanteenApi.Tests.Api;

/// <summary>Xác thực & phân quyền: mặc định đóng, vai trò lấy từ SQL Server, lỗi trả mã rõ ràng.</summary>
public class AuthorizationTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private static readonly SaveCategoryRequest NewCategory = new("Món chay", null, "eco", 5, true);

    [Fact]
    public async Task Health_KhongCanDangNhap()
    {
        var response = await Anonymous.GetAsync("/api/health");
        await response.ShouldHaveStatusAsync(HttpStatusCode.OK);
    }

    [Theory]
    [InlineData("/api/categories")]
    [InlineData("/api/foods")]
    [InlineData("/api/users/me")]
    [InlineData("/api/khong-ton-tai")] // FallbackPolicy: URL lạ cũng không lộ thông tin
    public async Task KhongCoToken_401(string url)
    {
        var response = await Anonymous.GetAsync(url);
        await response.ShouldBeProblemAsync(HttpStatusCode.Unauthorized, ErrorCodes.Unauthorized);
    }

    [Fact]
    public async Task ChuaCoHoSo_403_ProfileNotFound()
    {
        var response = await Factory.ClientFor(TestData.NoProfile).GetAsync("/api/categories");
        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.ProfileNotFound);
    }

    [Fact]
    public async Task TaiKhoanBiKhoa_403_AccountLocked()
    {
        var response = await Factory.ClientFor(TestData.Locked).GetAsync("/api/categories");
        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.AccountLocked);
    }

    [Fact]
    public async Task SinhVienGoiApiStaff_403_Forbidden()
    {
        var response = await AsStudent.PostJsonAsync("/api/categories", NewCategory);
        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    [Fact]
    public async Task StaffGoiApiAdmin_403_Forbidden()
    {
        var response = await AsStaff.GetAsync("/api/admin/users");
        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    [Fact]
    public async Task KhongTinClaimRoleTrongToken_VaiTroLayTuDatabase()
    {
        // Token "tự nhận" là admin nhưng bảng Users ghi student → vẫn bị chặn.
        var forged = Factory.ClientFor(TestData.Student1, tokenRole: "admin");

        var response = await forged.GetAsync("/api/admin/users");

        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    [Fact]
    public async Task AdminDoiVaiTro_CoHieuLucNgayRequestKeTiep()
    {
        var student = AsStudent;
        await (await student.PostJsonAsync("/api/categories", NewCategory))
            .ShouldHaveStatusAsync(HttpStatusCode.Forbidden);

        await (await AsAdmin.PatchJsonAsync($"/api/admin/users/{TestData.Student1}/role", new { role = "staff" }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);

        // Cùng "token" cũ, không cần đăng nhập lại.
        await (await student.PostJsonAsync("/api/categories", NewCategory))
            .ShouldHaveStatusAsync(HttpStatusCode.Created);
    }
}
