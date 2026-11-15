# Smart Campus Canteen E-Menu

Ứng dụng đặt món và quản lý menu căn-tin trường học. Đây là bài tập lớn môn Lập trình Ứng dụng cho Mobile (Flutter & Dart).

Sinh viên xem thực đơn, đặt món trước và theo dõi trạng thái chế biến theo thời gian thực (Đã nhận → Đang nấu → Mời nhận món). Nhân viên căn-tin cập nhật trạng thái đơn và quản lý thực đơn.

## Kiến trúc

```
┌──────────── Flutter App (mobile/) ────────────┐
│ UI responsive · Light/Dark · Provider          │
│ SQLite (sqflite): hóa đơn + giỏ hàng offline   │
│   │ http + Bearer ID token        │ StreamBuilder (chỉ đọc)
└───┼───────────────────────────────┼───────────┘
    ▼                               │
┌──────────────────────────┐        │
│ ASP.NET Core Web API     │  ghi   ▼
│ (backend/) - .NET 10     ├──► Firebase Realtime Database
│ xác minh token, nghiệp vụ│    orders/{id}: trạng thái realtime
└────────────┬─────────────┘
             │ EF Core
             ▼
      SQL Server (SmartCanteenDb)
      Categories · Foods · Users · Orders · OrderItems
            ▲
     Firebase Auth (Email/Password) cấp ID token cho app
```

| Thành phần | Vai trò |
|---|---|
| ASP.NET Core Web API | REST API cho thực đơn và đơn hàng. Xác minh Firebase ID token, tính tiền phía server, kiểm soát luồng trạng thái |
| SQL Server (EF Core) | **Nguồn dữ liệu chính**: thực đơn, hồ sơ người dùng, toàn bộ đơn hàng và chi tiết đơn |
| Firebase Auth | Đăng ký, đăng nhập, duy trì phiên (`authStateChanges`). Vai trò staff dùng custom claim |
| Firebase Realtime Database | Bản sao các đơn đang xử lý để đẩy trạng thái realtime tới app. Chỉ backend được ghi |
| SQLite (sqflite) | Lịch sử hóa đơn và giỏ hàng trên thiết bị, dùng được offline (CRUD đầy đủ) |
| Provider | Trạng thái giỏ hàng, theme, menu, người dùng |

Một đơn hàng dùng **cùng một `Id` (GUID)** ở cả ba nơi: SQL Server `Orders.Id`, Firebase `orders/{id}` và SQLite `orders.id`.

### Lược đồ SQL Server (14 bảng)

```
Người dùng  Users
Thực đơn    Categories 1──< Foods 1──< FoodOptionGroups 1──< FoodOptions
            Users >──< Foods  (qua Favorites, khóa chính kép)
Khuyến mãi  Vouchers 1──< Orders
Đơn hàng    Users 1──< Orders 1──< OrderItems 1──< OrderItemOptions
                      Orders 1──< OrderStatusHistory >── Users (người đổi trạng thái)
                      Orders 1──< Payments
Tương tác   Reviews (Users, Foods, Orders) · Notifications (Users)
```

| Nguyên tắc | Cách áp dụng |
|---|---|
| Hành vi khi xóa có chủ đích | Xóa đơn → xóa chi tiết, tùy chọn, lịch sử, thanh toán (`Cascade`). Không xóa được danh mục còn món, user/voucher đã có đơn (`Restrict`). Xóa món → hóa đơn cũ giữ nguyên, `FoodId = NULL` (`SetNull`) |
| Xóa mềm | `Categories`, `Foods` có `IsDeleted`. Món đã bán không xóa vật lý để thống kê doanh thu vẫn đúng |
| Lưu cứng dữ liệu lịch sử | `OrderItems`, `OrderItemOptions` lưu tên và giá tại thời điểm đặt, không phụ thuộc menu hiện tại |
| CHECK | Giá > 0; `TotalAmount = Subtotal - DiscountAmount`; `LineTotal = (UnitPrice + OptionsPrice) × Quantity`; rating 1–5; % giảm ≤ 100; `EndAt > StartAt`; đơn hủy phải có lý do; `Paid` phải có `PaidAt`… |
| UNIQUE | Email, mã sinh viên (filtered, cho phép NULL), mã voucher, tên món trong danh mục, mỗi món chỉ đánh giá 1 lần / đơn |
| Chống ghi đè đồng thời | `RowVersion` trên `Foods`, `Vouchers`, `Orders` |
| Thời gian | `datetime2(3)` UTC, `CreatedAt`/`UpdatedAt` tự gán khi `SaveChanges` |
| Index | Theo truy vấn thật: đơn của tôi, bảng đơn theo trạng thái, doanh thu theo ngày, món bán chạy, thông báo chưa đọc |

Cấu hình chi tiết từng bảng nằm trong `backend/src/CanteenApi/Data/Configurations/`.

**Kiểm thử ràng buộc:** `backend/sql/constraint-tests.sql` cố tình chèn 19 trường hợp dữ liệu sai, và mọi trường hợp đều phải bị chặn. Mỗi test được rollback nên không làm thay đổi dữ liệu.

```bash
sqlcmd -S localhost -E -C -I -d SmartCanteenDb -f 65001 -i backend/sql/constraint-tests.sql
```

## Cấu trúc thư mục

```
├── mobile/     Flutter app (package vn.edu.smartcanteen.app)
├── backend/    ASP.NET Core Web API (SmartCanteen.slnx → src/CanteenApi)
├── firebase/   Security Rules cho Realtime Database (deploy bằng Firebase CLI)
└── docs/       Báo cáo, slide, sơ đồ, ảnh chụp màn hình
```

## Yêu cầu môi trường

- Flutter 3.44+ (Dart 3.12+)
- .NET SDK 10
- SQL Server 2019+ (Developer/Express) hoặc LocalDB
- Node.js 20+ (cho Firebase CLI và FlutterFire CLI)
- Android Studio kèm Android Emulator

## Chạy backend

```bash
cd backend
dotnet tool restore      # cài dotnet-ef theo backend/dotnet-tools.json
dotnet run --project src/CanteenApi --launch-profile http
```

Ở môi trường Development, backend **tự áp dụng migration** khi khởi động: database `SmartCanteenDb` được tạo nếu chưa có.

Chuỗi kết nối mặc định nằm trong `appsettings.Development.json` (`Server=localhost`, Windows Authentication). Nếu máy bạn dùng instance khác, ví dụ SQL Express hoặc LocalDB, thì ghi đè bằng user-secrets:

```bash
cd backend/src/CanteenApi
dotnet user-secrets set "ConnectionStrings:CanteenDb" "Server=.\SQLEXPRESS;Database=SmartCanteenDb;Trusted_Connection=True;TrustServerCertificate=True"
# hoặc LocalDB: Server=(localdb)\MSSQLLocalDB;Database=SmartCanteenDb;Trusted_Connection=True
```

Khi sửa model, tạo migration mới:

```bash
cd backend
dotnet ef migrations add <TenMigration> --project src/CanteenApi --output-dir Data/Migrations
```

- Health check: http://localhost:5265/api/health
- Tài liệu API (Scalar): http://localhost:5265/scalar

Cấu hình Firebase lưu bằng **user-secrets**, không ghi vào `appsettings.json`:

```bash
cd backend/src/CanteenApi
dotnet user-secrets set "Firebase:ProjectId" "<project-id>"
dotnet user-secrets set "Firebase:DatabaseUrl" "https://<project-id>-default-rtdb.asia-southeast1.firebasedatabase.app"
dotnet user-secrets set "Firebase:CredentialPath" "<đường-dẫn-ngoài-repo>/service-account.json"
# Web API key (khóa công khai, lấy giá trị apiKey trong mobile/lib/firebase_options.dart) — dùng cho /api/dev/token
dotnet user-secrets set "Firebase:WebApiKey" "<apiKey>"
```

> ⚠️ File service account key **không bao giờ được commit** vào repo.

### Xác thực & phân quyền

- **Gửi token:** app gửi Firebase ID token trong header `Authorization: Bearer <idToken>`.
- **Mặc định mọi endpoint đều yêu cầu đăng nhập**, có hồ sơ trong bảng `Users` và tài khoản không bị khóa. Endpoint công khai phải ghi rõ `[AllowAnonymous]`.
- **Vai trò lấy từ SQL Server**, cache 60 giây. Admin đổi vai trò hoặc khóa tài khoản là có hiệu lực ngay ở request kế tiếp, không cần đợi app làm mới token.

| Policy | Điều kiện |
|---|---|
| `SignedIn` | Chỉ cần token hợp lệ (dùng cho bước tạo hồ sơ sau khi đăng ký) |
| `ActiveUser` (mặc định) | Token hợp lệ, đã có hồ sơ, không bị khóa |
| `StaffOrAdmin` | `ActiveUser` với vai trò staff hoặc admin |
| `AdminOnly` | `ActiveUser` với vai trò admin |

**Thử API có token trên Scalar** (chỉ ở Development):
1. Mở `/scalar` và gọi `POST /api/dev/token` với `{ "email": "sv01@smartcanteen.vn", "password": "Canteen@123" }`.
2. Copy `idToken` dán vào ô **Bearer** của Scalar. Token có hạn 1 giờ.
3. Gọi `GET /api/dev/whoami` để xem uid và vai trò hiện tại.

### Định dạng lỗi

Mọi lỗi đều trả về chuẩn RFC 7807 (`application/problem+json`) với trường `code` cố định. App dựa vào `code` để xử lý, không dựa vào câu chữ.

```json
{
  "type": "https://httpstatuses.io/403",
  "title": "Không có quyền truy cập",
  "status": 403,
  "detail": "Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên.",
  "code": "ACCOUNT_LOCKED",
  "traceId": "00-...-00"
}
```

| HTTP | `code` | Khi nào |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Dữ liệu gửi lên sai. Có thêm `errors: { "field": ["..."] }` |
| 400 | `INVALID_FILE` | Ảnh sai định dạng hoặc quá dung lượng |
| 401 | `UNAUTHORIZED` | Thiếu token, token sai hoặc hết hạn |
| 403 | `PROFILE_NOT_FOUND` | Đã đăng ký Firebase nhưng chưa tạo hồ sơ |
| 403 | `ACCOUNT_LOCKED` | Tài khoản bị khóa |
| 403 | `FORBIDDEN` | Không đủ quyền (ví dụ sinh viên gọi API của staff) |
| 404 | `NOT_FOUND` | Không tìm thấy |
| 409 | `CONCURRENCY_CONFLICT` | Dữ liệu đã bị người khác sửa (`RowVersion`) |
| 409 | `DUPLICATE`, `*_TAKEN` | Trùng dữ liệu duy nhất |
| 422 | (theo nghiệp vụ) | Vi phạm quy tắc nghiệp vụ |
| 500 | `INTERNAL_ERROR` | Lỗi hệ thống. Chi tiết chỉ ghi vào log theo `traceId`, không trả về client |

### Khởi tạo dữ liệu demo (chỉ chạy ở môi trường Development)

Các endpoint `/api/dev/*` trả về 404 ở môi trường khác và không xuất hiện trong tài liệu API.

| Method | Endpoint | Mô tả |
|---|---|---|
| POST | `/api/dev/seed` | Nạp menu (4 danh mục, 18 món, 13 nhóm tùy chọn, 34 tùy chọn) và 3 voucher từ `SeedData/menu.json`. Thêm `?reset=true` để **xóa toàn bộ dữ liệu nghiệp vụ** (SQL Server và Firebase) rồi nạp lại |
| POST | `/api/dev/accounts` | Tạo tài khoản demo trong Firebase Auth, gán vai trò và tạo hồ sơ trong bảng `Users`. Chạy lại nhiều lần không bị trùng |
| POST | `/api/dev/role?email=...&role=Staff` | Đổi vai trò một tài khoản (`Student`, `Staff`, `Admin`) |

```bash
curl -X POST http://localhost:5265/api/dev/seed
curl -X POST http://localhost:5265/api/dev/accounts
```

**Tài khoản demo** (mật khẩu chung: `Canteen@123`):

| Email | Vai trò |
|---|---|
| admin@smartcanteen.vn | Admin |
| staff@smartcanteen.vn | Staff |
| sv01@smartcanteen.vn | Student (MSSV 0023410001) |
| sv02@smartcanteen.vn | Student (MSSV 0023410002) |

**Voucher mẫu:** `TANSV10` (giảm 10%, tối đa 15k, đơn từ 30k), `GIAM5K` (giảm 5k, đơn từ 40k), `COMTRUA20` (giảm 20%, tối đa 20k, đơn từ 60k).

## Chạy mobile

```bash
cd mobile
flutter pub get
flutter run
```

Địa chỉ backend khi chạy local:

- Android Emulator: `http://10.0.2.2:5265`
- Điện thoại thật cùng mạng Wi-Fi: `http://<IP-LAN-của-máy>:5265`

## Deploy Firebase Security Rules

```bash
cd firebase
firebase deploy --only database
```
