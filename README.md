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

## Danh sách REST API

Tài liệu đầy đủ (schema request/response, thử trực tiếp) có tại `/scalar` khi chạy ở môi trường Development.

### Người dùng

| Method | Endpoint | Quyền | Mô tả |
|---|---|---|---|
| GET | `/api/users/me` | Đã đăng nhập | Hồ sơ của tôi, đồng thời ghi nhận lần đăng nhập. Chưa có hồ sơ trả 404 `PROFILE_NOT_FOUND`, bị khóa trả 403 `ACCOUNT_LOCKED` |
| POST | `/api/users/me` | Đã đăng nhập | Tạo hồ sơ sinh viên sau khi đăng ký Firebase. Email lấy từ token. Trả 201, hoặc 200 nếu đã có hồ sơ. Trùng MSSV trả 409 `STUDENT_CODE_TAKEN` |
| PUT | `/api/users/me` | ActiveUser | Sửa họ tên, số điện thoại. MSSV chỉ được đặt khi đang trống, đổi MSSV đã có trả 422 `STUDENT_CODE_LOCKED` |
| POST | `/api/users/me/avatar` | ActiveUser | Upload ảnh đại diện (multipart, field `file`, JPEG/PNG/WebP, tối đa 2 MB) |
| DELETE | `/api/users/me/avatar` | ActiveUser | Gỡ ảnh đại diện |
| GET | `/api/admin/users` | Admin | Danh sách người dùng: `search` (không dấu, theo tên, email hoặc MSSV), `role`, `isActive`, `page`, `pageSize` |
| GET | `/api/admin/users/{id}` | Admin | Chi tiết người dùng kèm số đơn và tổng chi tiêu |
| PATCH | `/api/admin/users/{id}/role` | Admin | `{ "role": "staff" }`, có hiệu lực ngay. Không tự đổi quyền của mình |
| PATCH | `/api/admin/users/{id}/status` | Admin | `{ "isActive": false }` khóa cả đăng nhập Firebase, có hiệu lực ngay |

**Validate:** họ tên 2–100 ký tự (tự bỏ khoảng trắng thừa), MSSV đúng 10 chữ số, số điện thoại `0xxxxxxxxx` hoặc `+84xxxxxxxxx`.

### Thực đơn

| Method | Endpoint | Quyền | Mô tả |
|---|---|---|---|
| GET | `/api/categories` | ActiveUser | Danh mục theo thứ tự hiển thị, kèm `foodCount`. Staff/admin dùng `?includeInactive=true` để thấy cả danh mục đang ẩn |
| GET | `/api/categories/{id}` | ActiveUser | Chi tiết danh mục |
| POST | `/api/categories` | Staff/Admin | Tạo danh mục. Trùng tên (không phân biệt dấu, hoa/thường) trả 409 `CATEGORY_NAME_TAKEN` |
| PUT | `/api/categories/{id}` | Staff/Admin | Sửa danh mục, ẩn/hiện qua `isActive` |
| PUT | `/api/categories/order` | Staff/Admin | Sắp xếp lại: `{ "items": [{ "id": 1, "sortOrder": 0 }] }` |
| DELETE | `/api/categories/{id}` | Staff/Admin | Xóa mềm. Còn món bên trong trả 409 `CATEGORY_NOT_EMPTY` |
| GET | `/api/foods` | ActiveUser | Danh sách món, có phân trang (xem tham số bên dưới) |
| GET | `/api/foods/{id}` | ActiveUser | Chi tiết món kèm nhóm tùy chọn và `rowVersion` |
| POST | `/api/foods` | Staff/Admin | Tạo món, có thể kèm `optionGroups` |
| PUT | `/api/foods/{id}` | Staff/Admin | Sửa món, bắt buộc gửi `rowVersion`. Người khác đã sửa trước thì trả 409 `CONCURRENCY_CONFLICT` |
| PUT | `/api/foods/{id}/option-groups` | Staff/Admin | Thay toàn bộ nhóm tùy chọn. Cấu hình sai trả 422 `INVALID_OPTIONS` |
| PATCH | `/api/foods/{id}/availability` | Staff/Admin | `{ "isAvailable": false }` để báo hết món |
| POST | `/api/foods/{id}/image` | Staff/Admin | Upload ảnh món (multipart, field `file`, tối đa 5 MB) |
| DELETE | `/api/foods/{id}` | Staff/Admin | Xóa mềm: biến khỏi menu và danh sách yêu thích, hóa đơn và thống kê cũ giữ nguyên |
| PUT / DELETE | `/api/foods/{id}/favorite` | ActiveUser | Thêm / bỏ yêu thích. Gọi lại nhiều lần vẫn an toàn |
| GET | `/api/users/me/favorites` | ActiveUser | Món yêu thích của tôi, mới thêm trước |

**Tham số `GET /api/foods`:** `q` (tìm không dấu theo tên và mô tả, ví dụ `com ga` ra "Cơm gà"), `categoryId`, `minPrice`, `maxPrice`, `availableOnly`, `sort` (`name` mặc định, `popular` theo số lượng bán 30 ngày, `price_asc`, `price_desc`, `rating`, `newest`), `page`, `pageSize` (tối đa 50).

**Trường tính toán của món:**

| Trường | Ý nghĩa |
|---|---|
| `remainingToday` | Số suất còn lại hôm nay = `dailyLimit` − số lượng đã đặt hôm nay. Tính theo giờ Việt Nam, bỏ qua đơn bị hủy. Bằng `null` nếu món không giới hạn suất |
| `isSoldOut` | `true` khi món tạm hết hoặc đã hết suất hôm nay |
| `hasOptions` | Món có nhóm tùy chọn |
| `isFavorite` | Món nằm trong danh sách yêu thích của người đang xem |

**Quy tắc tùy chọn:**
- tên nhóm không trùng trong một món, tên tùy chọn không trùng trong một nhóm;
- nhóm bắt buộc khi và chỉ khi `minSelect ≥ 1`;
- `minSelect ≤ maxSelect ≤ số tùy chọn`;
- giá cộng thêm từ 0 đến 200.000đ.

### Báo giá & voucher

| Method | Endpoint | Quyền | Mô tả |
|---|---|---|---|
| POST | `/api/orders/quote` | ActiveUser | Báo giá giỏ hàng cho màn Thanh toán, **không tạo đơn**. Giá lấy từ database, client chỉ gửi `foodId`, `quantity`, `optionIds`, `note`. Trả các dòng đã tính giá, `errors` theo từng dòng, kết quả voucher, `canOrder` |
| GET | `/api/vouchers/available` | ActiveUser | Voucher tôi đang dùng được, kèm `remainingForMe` |
| GET | `/api/admin/vouchers` | Staff/Admin | Danh sách voucher (`q`, `isActive`, phân trang) kèm `usedCount`, `orderCount` |
| POST | `/api/admin/vouchers` | Staff/Admin | Tạo voucher (mã tự viết hoa). Trùng mã trả 409 `VOUCHER_CODE_TAKEN` |
| PUT | `/api/admin/vouchers/{id}` | Staff/Admin | Sửa voucher, bắt buộc `rowVersion`. Mã đã dùng thì không đổi được mã/kiểu giảm (422 `VOUCHER_IN_USE`) |
| PATCH | `/api/admin/vouchers/{id}/status` | Staff/Admin | `{ "isActive": false }` |
| DELETE | `/api/admin/vouchers/{id}` | Staff/Admin | Chỉ xóa được voucher chưa dùng, đã dùng trả 409 `VOUCHER_IN_USE` |

**Lỗi theo dòng giỏ hàng** (trong `errors[]` của báo giá): `ITEM_UNAVAILABLE` (món đã ẩn/xóa/tạm hết), `OPTION_INVALID` (thiếu nhóm bắt buộc, vượt số lựa chọn, tùy chọn tạm hết hoặc không thuộc món, chọn trùng), `ITEM_SOLD_OUT` (vượt số suất còn lại hôm nay, cộng dồn các dòng cùng món, kèm `remaining`).

**Voucher:**
- Mã lỗi: `VOUCHER_INVALID`, `VOUCHER_EXPIRED` (hết hạn hoặc chưa bắt đầu), `VOUCHER_MIN_ORDER` (kèm số tiền còn thiếu), `VOUCHER_EXHAUSTED`, `VOUCHER_USER_LIMIT` (đơn đã hủy không tính lượt).
- Voucher không hợp lệ không chặn đặt hàng, chỉ không được giảm.
- Giảm theo % được làm tròn xuống 100đ và không vượt `maxDiscount`.
- Lượt dùng được giữ bằng **một câu UPDATE có điều kiện** (`UsedCount < UsageLimit`), nên nhiều người dùng cùng lúc không vượt giới hạn (có test 10 request song song, chỉ đúng 3 lượt thành công).

**Thời gian:** mọi thời điểm trong API là UTC dạng ISO 8601 có hậu tố `Z`, ví dụ `2026-11-16T03:00:00Z`. App tự đổi sang giờ Việt Nam khi hiển thị.

### Đặt món & đơn hàng

| Method | Endpoint | Quyền | Mô tả |
|---|---|---|---|
| POST | `/api/orders` | ActiveUser | Đặt món. Body: `items[]`, `voucherCode?`, `paymentMethod` (`cash` hoặc `bankTransfer`), `pickupTime?`, `note?`. **Bắt buộc header `Idempotency-Key`** (GUID). Trả 201, hoặc 200 nếu key đã dùng |
| GET | `/api/orders/me` | ActiveUser | Đơn của tôi: `status` = `active` / `completed` / `cancelled`, phân trang, mới nhất trước, kèm `itemsPreview` |
| GET | `/api/orders/{id}` | Chủ đơn hoặc Staff/Admin | Chi tiết: món + tùy chọn, dòng thời gian trạng thái, thanh toán, thông tin khách, `canCancel`. Người khác gọi thì trả 404 |
| GET | `/api/orders` | Staff/Admin | Bảng đơn theo ngày (`date`, mặc định hôm nay), `status` (nhiều giá trị), `paymentStatus`, `q` (`#015`, tên không dấu, MSSV). Đơn cần giao sớm nhất lên đầu |

**Quy tắc khi đặt món:**
- **Giờ mở cửa:** ngoài giờ trả 422 `CANTEEN_CLOSED`.
- **Giờ hẹn lấy món:** phải trong hôm nay, trong giờ mở cửa, và không sớm hơn bây giờ + max(thời gian chế biến lâu nhất, 10 phút). Sai thì trả 422 `PICKUP_TIME_INVALID`.
- **Số đơn đang xử lý:** mỗi người tối đa 3 đơn chưa hoàn thành, vượt thì trả 422 `TOO_MANY_ACTIVE_ORDERS`.
- **Giỏ hàng:** món hoặc tùy chọn không hợp lệ, hoặc hết suất, trả 422 `ORDER_ITEMS_INVALID` kèm `items[]` (lỗi theo dòng như khi báo giá).
- **Voucher:** gửi mã sai khi đặt món thì báo lỗi `VOUCHER_*`. Hệ thống không âm thầm tính đủ tiền.
- **Chuyển khoản:** chưa bật payOS thì trả 422 `PAYMENT_METHOD_UNAVAILABLE`.

**Chống bán quá suất và trùng mã:**
- Đơn được tạo trong một transaction có **khóa ứng dụng của SQL Server** (`sp_getapplock`), nên các đơn được tạo tuần tự.
- Test 10 request song song với món còn 5 suất cho kết quả đúng 5 đơn, mã `001`–`005`.
- Khi tạm tắt khóa, test này FAIL. Như vậy test thật sự kiểm tra được khóa.

**Mã nhận món:** số thứ tự trong ngày theo giờ Việt Nam (`001`, `002`…), sang ngày mới bắt đầu lại từ `001`. Database đảm bảo không trùng bằng `UNIQUE(PickupDate, PickupCode)`.

**Giờ dự kiến xong:** bây giờ + thời gian chế biến lâu nhất + 2 phút cho mỗi đơn đang chờ trước. Nếu có giờ hẹn muộn hơn thì lấy giờ hẹn.

### Thanh toán chuyển khoản (payOS)

| Method | Endpoint | Quyền | Mô tả |
|---|---|---|---|
| POST | `/api/orders` với `paymentMethod: "bankTransfer"` | ActiveUser | Tạo đơn kèm link payOS. `payment` trả về `qrCode` (chuỗi VietQR để app vẽ QR), `checkoutUrl`, `transferContent`, số tài khoản, `expiresAt` (15 phút) |
| POST | `/api/orders/{id}/payment/sync` | Chủ đơn hoặc Staff | Hỏi payOS ngay (nút "Tôi đã chuyển khoản"), trả chi tiết đơn |
| POST | `/api/orders/{id}/payment/confirm` | Staff/Admin | Xác nhận tay đã nhận tiền, đồng thời hủy link payOS để khách không trả thêm |
| POST | `/api/payments/payos/webhook` | payOS gọi (ẩn danh) | Chữ ký được xác thực bằng checksum key. Sai chữ ký trả 400 `INVALID_WEBHOOK` |
| POST | `/api/admin/payos/confirm-webhook` | Admin | Đăng ký URL webhook với payOS (cần URL public) |
| GET | `/payment/result` | Ẩn danh | Trang `returnUrl`/`cancelUrl`: kiểm tra ngay với payOS, báo người dùng quay lại app |

**Luồng thanh toán:**
1. Đơn được tạo và commit trước (đã giữ suất và voucher).
2. Sau đó backend tạo link payOS, **không giữ khóa trong lúc gọi mạng**.
3. Nếu payOS lỗi: đơn tự hủy (hoàn suất, hoàn voucher) và trả 502 `PAYMENT_PROVIDER_ERROR`.

**Ba đường xác nhận đã nhận tiền**, cùng đi qua một hàm idempotent `MarkPaidAsync`:
- **Webhook:** payOS gọi vào khi có URL public.
- **Poller chạy nền:** hỏi payOS mỗi 10 giây (`Workers:PaymentPollSeconds`). Đường này **bắt buộc khi chạy local**, vì payOS không gọi được vào `localhost`.
- **Staff xác nhận tay.**

Hàm `MarkPaidAsync` bảo đảm:
- webhook gửi lại hoặc chạy song song với poller vẫn chỉ ghi nhận một lần (`RowVersion` + UNIQUE `TransactionRef`);
- chuyển khoản thiếu tiền thì không chuyển sang Paid;
- tiền về sau khi đơn đã hủy thì ghi `Refunded` để staff hoàn tiền thủ công.

`orderCode` gửi payOS = `yyMMdd × 10000 + số thứ tự trong ngày` (ví dụ `2611160015`). Nội dung chuyển khoản = `SC` + 7 số cuối (≤ 9 ký tự theo giới hạn payOS).

**Cấu hình payOS:**
1. Lấy Client ID / API Key / Checksum Key tại my.payos.vn, mục **Kênh thanh toán**.
2. Lưu vào user-secrets (**không commit**):

```bash
cd backend/src/CanteenApi
dotnet user-secrets set "PayOS:ClientId" "<Client ID>"
dotnet user-secrets set "PayOS:ApiKey" "<API Key>"
dotnet user-secrets set "PayOS:ChecksumKey" "<Checksum Key>"
dotnet user-secrets set "PayOS:Enabled" "true"
```

Muốn nhận webhook khi chạy local:
1. Mở tunnel, ví dụ `cloudflared tunnel --url http://localhost:5265`.
2. Đặt `Canteen:PublicBaseUrl` bằng URL tunnel.
3. Admin gọi `POST /api/admin/payos/confirm-webhook`.

Không có tunnel thì poller vẫn tự xác nhận, chậm tối đa khoảng 10 giây.

### Cấu hình vận hành căn-tin (`appsettings.json`)

| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `Canteen:OpenTime` / `CloseTime` | `06:30` / `19:00` | Giờ nhận đơn (giờ Việt Nam) |
| `Canteen:MaxActiveOrdersPerUser` | 3 | Số đơn đang xử lý tối đa mỗi người |
| `Canteen:MaxLinesPerOrder` | 20 | Số dòng món tối đa mỗi đơn |
| `Canteen:UnpaidTransferTimeoutMinutes` | 15 | Đơn chuyển khoản chưa trả quá hạn này sẽ tự hủy |
| `Canteen:MinPickupLeadMinutes` | 10 | Giờ hẹn lấy món tối thiểu sau lúc đặt |
| `Canteen:PublicBaseUrl` | (trống) | URL public (tunnel) cho returnUrl/webhook payOS |
| `PayOS:Enabled` | `false` | Bật thanh toán chuyển khoản qua payOS. Khóa đặt trong user-secrets |

Ghi đè cấu hình bằng biến môi trường (dùng `__` thay cho `:`), không cần sửa file. Ví dụ để demo sau 19:00:

```bash
Canteen__CloseTime=23:59 dotnet run --project src/CanteenApi --launch-profile http
```

## Kiểm thử tự động

```bash
cd backend
dotnet test
```

Bộ test nằm trong `backend/tests/CanteenApi.Tests` (xUnit), gồm **147 test, chạy khoảng 10 giây**. Test chạy **toàn bộ backend thật trong bộ nhớ** (`WebApplicationFactory`): routing, phân quyền, validate, EF Core và SQL Server thật. Chỉ một số phần được thay thế:

| Thành phần | Trong test |
|---|---|
| SQL Server | Database riêng `SmartCanteenDb_Test`, tạo lại bằng migration mỗi lượt chạy, nạp lại dữ liệu mẫu trước **mỗi** test. Đổi chuỗi kết nối bằng biến môi trường `CANTEEN_TEST_DB` |
| Xác thực Firebase | `TestAuthHandler` đọc danh tính giả từ header (`X-Test-Uid`, `X-Test-Role`…) |
| Firebase Admin | `FakeFirebaseAuthService`: không gọi mạng, ghi lại thao tác gán vai trò và khóa tài khoản để kiểm tra |
| payOS | `FakePaymentGateway`: không gọi mạng, dựng được kịch bản đã trả tiền, payOS lỗi, webhook sai chữ ký |
| Đồng hồ | `TestClock` cố định 10:00 ngày 16/11/2026 giờ Việt Nam, có thể tua sang ngày khác |
| `wwwroot` | Thư mục tạm, tự xóa sau khi chạy (ảnh upload không làm bẩn source) |

Không cần file service account và không cần Internet.

| Nhóm test | Nội dung chính |
|---|---|
| `Unit/VietnamTimeTests` | Ranh giới ngày theo giờ Việt Nam (00:00 VN = 17:00 UTC hôm trước) |
| `Unit/ImageSignatureTests` | Nhận diện JPEG/PNG/WebP bằng magic bytes. Chặn file text đổi đuôi, GIF, SVG |
| `Api/AuthorizationTests` | 401/403 có mã lỗi rõ ràng. **Không tin claim role trong token** (token tự nhận admin vẫn bị chặn). Đổi vai trò có hiệu lực ngay |
| `Api/UsersTests` | Tạo hồ sơ (gọi lại an toàn), trùng MSSV, validate, khóa MSSV, đăng nhập không đổi `UpdatedAt`, ảnh đại diện thay/gỡ có dọn file |
| `Api/AdminUsersTests` | Phân trang, tìm không dấu, lọc, đổi vai trò và khóa tài khoản đồng bộ sang Firebase, không tự sửa chính mình |
| `Api/CategoriesTests` | Hiển thị theo vai trò, trùng tên không dấu, sắp xếp, xóa mềm, tạo lại tên đã xóa |
| `Api/FoodsTests` | Tìm/lọc/sắp xếp. **Số suất còn lại tính theo giờ Việt Nam qua nửa đêm**, bỏ đơn hủy, sang ngày mới tính lại. Bán chạy 30 ngày. Chống ghi đè khi sửa đồng thời. Tùy chọn. Xóa mềm giữ lịch sử đơn. Yêu thích theo từng người |

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
