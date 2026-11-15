using CanteenApi.Data;
using CanteenApi.Models;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>Dữ liệu mẫu cố định cho mỗi test (nạp lại từ đầu trước mỗi test).</summary>
public static class TestData
{
    // ----- Người dùng (uid giả) -----
    public const string Student1 = "uid-student-1";
    public const string Student2 = "uid-student-2";
    public const string Staff = "uid-staff";
    public const string Admin = "uid-admin";
    public const string Locked = "uid-locked";
    public const string NoProfile = "uid-no-profile"; // có "token" nhưng chưa có dòng trong Users

    public const string Student1Code = "0023410001";

    // ----- Tên dữ liệu menu -----
    public const string Rice = "Cơm";
    public const string Drinks = "Nước uống";
    public const string HiddenCategory = "Món thử nghiệm";

    public const string ComGa = "Cơm gà xối mỡ";
    public const string ComTam = "Cơm tấm sườn bì chả";
    public const string TraSua = "Trà sữa trân châu";
    public const string NuocSuoi = "Nước suối";
    public const string HiddenFood = "Món bí mật";

    public static async Task SeedAsync(CanteenDbContext db)
    {
        db.Users.AddRange(
            new AppUser { Id = Student1, Email = "sv01@test.vn", FullName = "Nguyễn Văn An", StudentCode = Student1Code, Role = UserRole.Student },
            new AppUser { Id = Student2, Email = "sv02@test.vn", FullName = "Trần Thị Bình", StudentCode = "0023410002", Role = UserRole.Student },
            new AppUser { Id = Staff, Email = "staff@test.vn", FullName = "Nhân viên căn-tin", Role = UserRole.Staff },
            new AppUser { Id = Admin, Email = "admin@test.vn", FullName = "Quản trị", Role = UserRole.Admin },
            new AppUser { Id = Locked, Email = "locked@test.vn", FullName = "Bị khóa", StudentCode = "0023410099", Role = UserRole.Student, IsActive = false });

        db.Categories.AddRange(
            new Category
            {
                Name = Rice, Icon = "rice_bowl", SortOrder = 1,
                Foods =
                {
                    new Food { Name = ComGa, Description = "Gà chiên giòn, cơm chiên", Price = 35000, PrepTimeMinutes = 10, DailyLimit = 60 },
                    new Food { Name = ComTam, Description = "Sườn nướng, bì, chả trứng", Price = 40000, PrepTimeMinutes = 10 },
                },
            },
            new Category
            {
                Name = Drinks, Icon = "local_drink", SortOrder = 2,
                Foods =
                {
                    new Food
                    {
                        Name = TraSua, Description = "Trà sữa Assam, trân châu đường đen", Price = 25000, PrepTimeMinutes = 4,
                        OptionGroups =
                        {
                            new FoodOptionGroup
                            {
                                Name = "Size", IsRequired = true, MinSelect = 1, MaxSelect = 1, SortOrder = 1,
                                Options = { new FoodOption { Name = "M", ExtraPrice = 0 }, new FoodOption { Name = "L", ExtraPrice = 6000 } },
                            },
                            new FoodOptionGroup
                            {
                                Name = "Topping", IsRequired = false, MinSelect = 0, MaxSelect = 2, SortOrder = 2,
                                Options =
                                {
                                    new FoodOption { Name = "Trân châu", ExtraPrice = 5000 },
                                    new FoodOption { Name = "Pudding", ExtraPrice = 7000 },
                                    new FoodOption { Name = "Thạch (tạm hết)", ExtraPrice = 5000, IsAvailable = false },
                                },
                            },
                        },
                    },
                    new Food { Name = NuocSuoi, Description = "Chai 500ml", Price = 8000, PrepTimeMinutes = 1 },
                },
            },
            new Category
            {
                Name = HiddenCategory, Icon = "science", SortOrder = 3, IsActive = false,
                Foods = { new Food { Name = HiddenFood, Description = "Chưa mở bán", Price = 50000, PrepTimeMinutes = 5 } },
            });

        await db.SaveChangesAsync();
    }
}
