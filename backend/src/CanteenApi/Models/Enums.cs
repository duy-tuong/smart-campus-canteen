namespace CanteenApi.Models;

// Tất cả enum được lưu trong SQL Server dưới dạng chuỗi (nvarchar(20)) để dễ đọc trong SSMS
// và không bị lệch dữ liệu khi thêm/sắp xếp lại giá trị enum. Cấu hình tại CanteenDbContext.

/// <summary>Vai trò người dùng (đồng bộ với custom claim "role" của Firebase).</summary>
public enum UserRole
{
    Student,
    Staff,
    Admin,
}

/// <summary>Trạng thái chế biến đơn hàng.</summary>
public enum OrderStatus
{
    Received,   // Đã nhận
    Cooking,    // Đang nấu
    Ready,      // Mời nhận món
    Completed,  // Đã lấy món
    Cancelled,  // Đã hủy
}

/// <summary>Phương thức thanh toán.</summary>
public enum PaymentMethod
{
    Cash,          // Tiền mặt tại quầy
    BankTransfer,  // Chuyển khoản (mô phỏng)
}

/// <summary>Trạng thái giao dịch thanh toán.</summary>
public enum PaymentStatus
{
    Pending,
    Paid,
    Failed,
    Refunded,
}

/// <summary>Kiểu giảm giá của voucher.</summary>
public enum DiscountType
{
    Percent,  // Giảm theo %, giới hạn bởi MaxDiscount
    Fixed,    // Giảm số tiền cố định
}

/// <summary>Loại thông báo.</summary>
public enum NotificationType
{
    OrderStatus,
    Promotion,
    System,
}
