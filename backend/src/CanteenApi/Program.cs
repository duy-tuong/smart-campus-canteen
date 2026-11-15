using CanteenApi.Auth;
using CanteenApi.Options;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// ---------- Cấu hình ----------
builder.Services.Configure<FirebaseOptions>(
    builder.Configuration.GetSection(FirebaseOptions.SectionName));

// ---------- Services ----------
builder.Services.AddControllers();
builder.Services.AddOpenApi();

// Firebase: credential, Admin SDK, Realtime Database (REST), xác thực JWT ID token.
builder.Services.AddFirebase(builder.Configuration);

// TODO (bước sau): đăng ký FoodService, OrderService (thư mục Services/)

var app = builder.Build();

// ---------- Pipeline ----------
if (app.Environment.IsDevelopment())
{
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
