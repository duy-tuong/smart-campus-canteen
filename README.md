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

### Lược đồ SQL Server

```
Categories 1 ──< Foods
Users      1 ──< Orders 1 ──< OrderItems >── 1 Foods (FoodId NULL khi món bị xóa)
```

- Xóa danh mục còn món → bị chặn (`Restrict`).
- Xóa đơn → xóa luôn chi tiết đơn (`Cascade`).
- Xóa món → chi tiết đơn cũ giữ tên và giá, `FoodId = NULL` (`SetNull`).
- Có các ràng buộc `CHECK` cho giá, số lượng và tổng tiền.

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
```

> ⚠️ File service account key **không bao giờ được commit** vào repo.

### Endpoint khởi tạo dữ liệu (chỉ chạy ở môi trường Development)

| Method | Endpoint | Mô tả |
|---|---|---|
| POST | `/api/admin/seed` | Nạp danh mục và món ăn từ `SeedData/menu.json` vào SQL Server. Thêm `?reset=true` để xóa menu cũ và nạp lại |
| POST | `/api/admin/staff?email=...` | Cấp quyền nhân viên căn-tin (custom claim `role=staff`) cho tài khoản đã đăng ký |

```bash
curl -X POST http://localhost:5265/api/admin/seed
curl -X POST "http://localhost:5265/api/admin/staff?email=staff@canteen.vn"
```

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
