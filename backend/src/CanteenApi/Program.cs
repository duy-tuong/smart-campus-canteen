using System.Text.Json;
using System.Text.Json.Serialization;
using CanteenApi.Auth;
using CanteenApi.Data;
using CanteenApi.Options;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// ---------- Cấu hình ----------
builder.Services.Configure<FirebaseOptions>(
    builder.Configuration.GetSection(FirebaseOptions.SectionName));

// ---------- Services ----------
builder.Services
    .AddControllers()
    .AddJsonOptions(o =>
        // Enum trả về dạng chuỗi camelCase: "received", "cooking", "ready"...
        o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)));
builder.Services.AddOpenApi();

// SQL Server (EF Core) — nguồn dữ liệu chính: menu, người dùng, đơn hàng.
builder.Services.AddDbContext<CanteenDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("CanteenDb")
        ?? throw new InvalidOperationException("Thiếu ConnectionStrings:CanteenDb.")));

// Firebase: credential, Admin SDK, Realtime Database (REST), xác thực JWT ID token.
builder.Services.AddFirebase(builder.Configuration);

// TODO (bước sau): đăng ký FoodService, OrderService (thư mục Services/)

var app = builder.Build();

// ---------- Pipeline ----------
if (app.Environment.IsDevelopment())
{
    // Tự áp dụng migration khi chạy local: clone repo về, chạy là có database.
    using (var scope = app.Services.CreateScope())
    {
        scope.ServiceProvider.GetRequiredService<CanteenDbContext>().Database.Migrate();
    }

    app.MapOpenApi();          // /openapi/v1.json
    app.MapScalarApiReference(); // /scalar - giao diện tài liệu API
}

// Không dùng UseHttpsRedirection: emulator gọi http://10.0.2.2,
// còn khi deploy (Render) TLS được xử lý ở reverse proxy.
app.UseStaticFiles(); // phục vụ ảnh món ăn trong wwwroot/images

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
