import '../../models/user_profile.dart';
import 'api_client.dart';

/// REST: hồ sơ của người dùng đang đăng nhập (/api/users/me).
class UserApi {
  UserApi(this._api);

  final ApiClient _api;

  /// 404 PROFILE_NOT_FOUND nếu chưa tạo hồ sơ; 403 ACCOUNT_LOCKED nếu bị khóa.
  Future<UserProfile> getMe() async => UserProfile.fromJson(await _api.get('/api/users/me') as Map<String, dynamic>);

  /// Tạo hồ sơ sinh viên sau khi đăng ký Firebase (email lấy từ token).
  Future<UserProfile> createMe({required String fullName, required String studentCode, String? phone}) async =>
      UserProfile.fromJson(await _api.post('/api/users/me', body: {
        'fullName': fullName.trim(),
        'studentCode': studentCode.trim(),
        'phone': _optional(phone),
      }) as Map<String, dynamic>);

  Future<UserProfile> updateMe({required String fullName, String? phone, String? studentCode}) async =>
      UserProfile.fromJson(await _api.put('/api/users/me', body: {
        'fullName': fullName.trim(),
        'phone': _optional(phone),
        'studentCode': _optional(studentCode),
      }) as Map<String, dynamic>);

  static String? _optional(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();
}
