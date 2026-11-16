import '../core/utils/vn_time.dart';
import 'enums.dart';

/// Hồ sơ người dùng (GET /api/users/me).
class UserProfile {
  const UserProfile({
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
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        studentCode: json['studentCode'] as String?,
        phone: json['phone'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        role: UserRole.fromJson(json['role']),
        isActive: json['isActive'] as bool? ?? true,
        createdAt: VnTime.parse(json['createdAt'] as String),
        lastLoginAt: VnTime.tryParse(json['lastLoginAt'] as String?),
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
  final DateTime? lastLoginAt;

  /// Chữ cái viết tắt cho avatar mặc định: "Nguyễn Văn An" → "AN".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.last[0]}${parts.first[0]}'.toUpperCase();
  }
}
