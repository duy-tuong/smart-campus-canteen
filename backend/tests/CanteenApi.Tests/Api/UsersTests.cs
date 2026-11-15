using System.Net;
using System.Text;
using CanteenApi.Common;
using CanteenApi.Dtos.Users;
using CanteenApi.Models;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Api;

/// <summary>Hồ sơ của tôi: đăng ký hồ sơ, sửa, ảnh đại diện.</summary>
public class UsersTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private HttpClient NewUser => Factory.ClientFor(TestData.NoProfile, "new@test.vn");

    [Fact]
    public async Task GetMe_ChuaCoHoSo_404_ProfileNotFound()
    {
        var response = await NewUser.GetAsync("/api/users/me");
        await response.ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.ProfileNotFound);
    }

    [Fact]
    public async Task TaoHoSo_201_ChuanHoaHoTen_EmailLayTuToken_RoleStudent()
    {
        var response = await NewUser.PostJsonAsync("/api/users/me",
            new CreateProfileRequest("  Lê   Văn  Cường ", "0023419999", "0987654321"));

        var profile = await response.ReadAsAsync<UserProfileDto>(HttpStatusCode.Created);
        Assert.Equal("Lê Văn Cường", profile.FullName);
        Assert.Equal("new@test.vn", profile.Email);
        Assert.Equal(UserRole.Student, profile.Role);
        Assert.EndsWith("/api/users/me", response.Headers.Location?.ToString());
    }

    [Fact]
    public async Task TaoHoSoLan2_200_GiuHoSoCu()
    {
        var client = NewUser;
        await (await client.PostJsonAsync("/api/users/me", new CreateProfileRequest("Lê Văn Cường", "0023419999", null)))
            .ShouldHaveStatusAsync(HttpStatusCode.Created);

        var again = await client.PostJsonAsync("/api/users/me", new CreateProfileRequest("Tên Khác", "0023418888", null));

        var profile = await again.ReadAsAsync<UserProfileDto>(HttpStatusCode.OK);
        Assert.Equal("Lê Văn Cường", profile.FullName);
    }

    [Fact]
    public async Task TaoHoSo_TrungMssv_409()
    {
        var response = await NewUser.PostJsonAsync("/api/users/me",
            new CreateProfileRequest("Lê Văn Cường", TestData.Student1Code, null));

        await response.ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.StudentCodeTaken);
    }

    [Fact]
    public async Task TaoHoSo_DuLieuSai_400_LoiTheoTungTruong()
    {
        var response = await NewUser.PostJsonAsync("/api/users/me", new { fullName = "A", studentCode = "123", phone = "abc" });

        var problem = await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
        var fields = problem.GetProperty("errors").EnumerateObject().Select(p => p.Name).ToHashSet();
        Assert.Superset(new HashSet<string> { "FullName", "StudentCode", "Phone" }, fields);
    }

    [Fact]
    public async Task SuaHoSo_DoiSoDienThoai()
    {
        var response = await AsStudent.PutJsonAsync("/api/users/me", new UpdateProfileRequest("Nguyễn Văn An", "+84912345678", null));

        var profile = await response.ReadAsAsync<UserProfileDto>();
        Assert.Equal("+84912345678", profile.Phone);
    }

    [Fact]
    public async Task SuaHoSo_DoiMssvDaCo_422()
    {
        var response = await AsStudent.PutJsonAsync("/api/users/me", new UpdateProfileRequest("Nguyễn Văn An", null, "0023417777"));
        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.StudentCodeLocked);
    }

    [Fact]
    public async Task SuaHoSo_ChuaBiDoiUpdatedAt_KhiChiDangNhap()
    {
        var before = await Factory.WithDbAsync(db => db.Users.Where(u => u.Id == TestData.Student1).Select(u => u.UpdatedAt).SingleAsync());

        await (await AsStudent.GetAsync("/api/users/me")).ShouldHaveStatusAsync(HttpStatusCode.OK);

        var user = await Factory.WithDbAsync(db => db.Users.AsNoTracking().SingleAsync(u => u.Id == TestData.Student1));
        Assert.Equal(before, user.UpdatedAt);      // đăng nhập không phải là sửa hồ sơ
        Assert.NotNull(user.LastLoginAt);
    }

    [Fact]
    public async Task Avatar_UploadThayGo_FileDuocDonDep()
    {
        var client = AsStudent;

        var first = await (await client.UploadAsync("/api/users/me/avatar", HttpExtensions.TinyPng(), "a.png"))
            .ReadAsAsync<UserProfileDto>();
        Assert.StartsWith("http://localhost/uploads/avatars/", first.AvatarUrl);
        var firstFile = LocalPath(first.AvatarUrl!);
        Assert.True(File.Exists(firstFile));

        var second = await (await client.UploadAsync("/api/users/me/avatar", HttpExtensions.TinyPng(), "b.png"))
            .ReadAsAsync<UserProfileDto>();
        Assert.False(File.Exists(firstFile), "Ảnh cũ phải bị xóa khi thay ảnh mới");

        await (await client.DeleteAsync("/api/users/me/avatar")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Assert.False(File.Exists(LocalPath(second.AvatarUrl!)), "Gỡ ảnh phải xóa file");
    }

    [Fact]
    public async Task Avatar_FileTextGiaDuoiJpg_400_InvalidFile()
    {
        var response = await AsStudent.UploadAsync("/api/users/me/avatar", Encoding.UTF8.GetBytes("khong phai anh"), "virus.jpg");
        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.InvalidFile);
    }

    private string LocalPath(string url) =>
        Path.Combine(Factory.WebRoot, new Uri(url).AbsolutePath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
}

/// <summary>Quản trị tài khoản (admin).</summary>
public class AdminUsersTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task DanhSach_PhanTrang()
    {
        var page = await (await AsAdmin.GetAsync("/api/admin/users?pageSize=2&page=3"))
            .ReadAsAsync<PagedResult<AdminUserListItemDto>>();

        Assert.Equal(5, page.TotalCount);
        Assert.Equal(3, page.TotalPages);
        Assert.Single(page.Items);
    }

    [Theory]
    [InlineData("nguyen van an", "Nguyễn Văn An")]  // không dấu
    [InlineData("TRAN THI", "Trần Thị Bình")]       // hoa/thường
    [InlineData("0023410002", "Trần Thị Bình")]     // theo MSSV
    [InlineData("staff@", "Nhân viên căn-tin")]      // theo email
    public async Task TimKiem(string search, string expectedName)
    {
        var page = await (await AsAdmin.GetAsync($"/api/admin/users?search={Uri.EscapeDataString(search)}"))
            .ReadAsAsync<PagedResult<AdminUserListItemDto>>();

        Assert.Equal(expectedName, Assert.Single(page.Items).FullName);
    }

    [Fact]
    public async Task LocTheoVaiTroVaTrangThai()
    {
        var locked = await (await AsAdmin.GetAsync("/api/admin/users?isActive=false"))
            .ReadAsAsync<PagedResult<AdminUserListItemDto>>();
        Assert.Equal(TestData.Locked, Assert.Single(locked.Items).Id);

        var staff = await (await AsAdmin.GetAsync("/api/admin/users?role=staff"))
            .ReadAsAsync<PagedResult<AdminUserListItemDto>>();
        Assert.Equal(TestData.Staff, Assert.Single(staff.Items).Id);
    }

    [Fact]
    public async Task PageSizeQuaLon_400()
    {
        var response = await AsAdmin.GetAsync("/api/admin/users?pageSize=500");
        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task ChiTiet_KhongTonTai_404()
    {
        var response = await AsAdmin.GetAsync("/api/admin/users/khong-co");
        await response.ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);
    }

    [Fact]
    public async Task DoiVaiTro_DongBoClaimSangFirebase()
    {
        var detail = await (await AsAdmin.PatchJsonAsync($"/api/admin/users/{TestData.Student2}/role", new { role = "staff" }))
            .ReadAsAsync<AdminUserDetailDto>();

        Assert.Equal(UserRole.Staff, detail.Role);
        Assert.Equal(UserRole.Staff, Factory.Firebase.RoleClaims[TestData.Student2]);
    }

    [Fact]
    public async Task KhoaTaiKhoan_ChanNgay_VaKhoaTrenFirebase()
    {
        var student2 = AsStudent2;
        await (await student2.GetAsync("/api/categories")).ShouldHaveStatusAsync(HttpStatusCode.OK);

        await (await AsAdmin.PatchJsonAsync($"/api/admin/users/{TestData.Student2}/status", new { isActive = false }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);

        Assert.True(Factory.Firebase.Disabled[TestData.Student2]);
        await (await student2.GetAsync("/api/categories"))
            .ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.AccountLocked);

        await (await AsAdmin.PatchJsonAsync($"/api/admin/users/{TestData.Student2}/status", new { isActive = true }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);
        await (await student2.GetAsync("/api/categories")).ShouldHaveStatusAsync(HttpStatusCode.OK);
    }

    [Theory]
    [InlineData("role", "{\"role\":\"student\"}")]
    [InlineData("status", "{\"isActive\":false}")]
    public async Task AdminKhongTuSuaChinhMinh_403(string action, string json)
    {
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        var response = await AsAdmin.PatchAsync($"/api/admin/users/{TestData.Admin}/{action}", content);

        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.CannotModifySelf);
    }

    [Fact]
    public async Task VaiTroKhongHopLe_400()
    {
        var response = await AsAdmin.PatchJsonAsync($"/api/admin/users/{TestData.Student2}/role", new { role = "vua" });
        await response.ShouldHaveStatusAsync(HttpStatusCode.BadRequest);
    }
}
