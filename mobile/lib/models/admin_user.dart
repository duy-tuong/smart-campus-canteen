import '../core/utils/vn_time.dart';
import 'enums.dart';
import 'user_profile.dart';

/// Một tài khoản trong màn quản trị (GET /api/admin/users và /api/admin/users/{id}).
/// Các trường thống kê đơn chỉ có ở bản chi tiết.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.studentCode,
    this.phone,
    this.avatarUrl,
    this.lastLoginAt,
    this.updatedAt,
    this.orderCount,
    this.completedOrderCount,
    this.totalSpent,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['fullName'] as String,
    studentCode: json['studentCode'] as String?,
    phone: json['phone'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    role: UserRole.fromJson(json['role']),
    isActive: json['isActive'] as bool? ?? true,
    createdAt: VnTime.parse(json['createdAt'] as String),
    updatedAt: VnTime.tryParse(json['updatedAt'] as String?),
    lastLoginAt: VnTime.tryParse(json['lastLoginAt'] as String?),
    orderCount: (json['orderCount'] as num?)?.toInt(),
    completedOrderCount: (json['completedOrderCount'] as num?)?.toInt(),
    totalSpent: (json['totalSpent'] as num?)?.toInt(),
  );

  final String id;
  final String email;
  final String fullName;
  final String? studentCode;
  final String? phone;
  final String? avatarUrl;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;
  final int? orderCount;
  final int? completedOrderCount;
  final int? totalSpent;

  /// Dùng lại UserAvatar (ảnh thật hoặc chữ cái đầu).
  UserProfile get asProfile => UserProfile(
    id: id,
    email: email,
    fullName: fullName,
    role: role,
    isActive: isActive,
    createdAt: createdAt,
    studentCode: studentCode,
    phone: phone,
    avatarUrl: avatarUrl,
    lastLoginAt: lastLoginAt,
  );
}
