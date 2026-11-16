import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/firebase/auth_service.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_exception.dart';
import '../data/remote/user_api.dart';
import '../models/user_profile.dart';

/// Thông tin hồ sơ đã nhập ở màn Đăng ký nhưng tạo hồ sơ thất bại — điền sẵn vào màn Hoàn tất hồ sơ.
class ProfileDraft {
  const ProfileDraft({required this.fullName, required this.studentCode, this.phone, this.error});

  final String fullName;
  final String studentCode;
  final String? phone;
  final ApiException? error;
}

enum AuthStatus {
  /// Đang chờ Firebase cho biết đã đăng nhập hay chưa (lúc mở app).
  unknown,

  signedOut,

  /// Đã đăng nhập Firebase, đang tải hồ sơ từ backend.
  loadingProfile,

  /// Đăng nhập Firebase rồi nhưng chưa có hồ sơ (404 PROFILE_NOT_FOUND) → màn Hoàn tất hồ sơ.
  needsProfile,

  /// 403 ACCOUNT_LOCKED.
  locked,

  /// Không tải được hồ sơ (mất mạng, sai địa chỉ máy chủ...) → màn lỗi có nút Thử lại.
  error,

  /// Đã có hồ sơ — vào app theo vai trò.
  ready,
}

/// Phiên đăng nhập: Firebase Auth (ai đang đăng nhập) + hồ sơ trên backend (vai trò, MSSV...).
class AuthProvider extends ChangeNotifier {
  AuthProvider({required this._auth, required this._users, required ApiClient api}) {
    _authSub = _auth.authStateChanges().listen(_onAuthUser);
    _apiSub = api.authErrors.listen(_onApiAuthError);
  }

  final AuthService _auth;
  final UserApi _users;
  late final StreamSubscription<AuthUser?> _authSub;
  late final StreamSubscription<ApiException> _apiSub;

  AuthStatus _status = AuthStatus.unknown;
  AuthUser? _user;
  UserProfile? _profile;
  Object? _error;

  /// Tăng mỗi lần tải/tạo hồ sơ — kết quả của lượt cũ về muộn sẽ bị bỏ qua.
  int _generation = 0;
  bool _registering = false;
  ProfileDraft? _draft;

  /// Lấy (một lần) bản nháp hồ sơ còn dở từ màn Đăng ký.
  ProfileDraft? takeDraft() {
    final draft = _draft;
    _draft = null;
    return draft;
  }

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  UserProfile? get profile => _profile;
  Object? get error => _error;
  bool get isSignedIn => _user != null;

  // ---------------------------- Theo dõi Firebase ----------------------------

  void _onAuthUser(AuthUser? user) {
    if (user == null) {
      _generation++;
      _user = null;
      _profile = null;
      _error = null;
      _draft = null;
      _set(AuthStatus.signedOut);
      return;
    }
    if (user.uid == _user?.uid && _status != AuthStatus.signedOut && _status != AuthStatus.unknown) return;
    _user = user;
    // Đang đăng ký: register() tự tạo hồ sơ — không GET /me song song (có thể nhận 404 về muộn).
    if (_registering) return;
    loadProfile();
  }

  /// Lỗi xác thực từ bất kỳ request REST nào (xử lý chung, từng màn không phải tự lo).
  void _onApiAuthError(ApiException e) {
    if (_user == null) return;
    if (e.isUnauthorized) {
      signOut();
    } else if (e.code == ApiErrorCodes.accountLocked) {
      _set(AuthStatus.locked);
    } else if (e.code == ApiErrorCodes.profileNotFound) {
      _profile = null;
      _set(AuthStatus.needsProfile);
    }
  }

  /// Tải hồ sơ của người đang đăng nhập (cũng là nút "Thử lại").
  Future<void> loadProfile() async {
    if (_user == null) return;
    final generation = ++_generation;
    _error = null;
    _set(AuthStatus.loadingProfile);
    try {
      final profile = await _users.getMe();
      if (generation != _generation) return;
      await _ensureRoleClaim(profile);
      if (generation != _generation) return;
      _profile = profile;
      _set(AuthStatus.ready);
    } on ApiException catch (e) {
      if (generation != _generation) return;
      switch (e.code) {
        case ApiErrorCodes.profileNotFound:
          _set(AuthStatus.needsProfile);
        case ApiErrorCodes.accountLocked:
          _set(AuthStatus.locked);
        default:
          _error = e;
          _set(AuthStatus.error);
      }
    }
  }

  /// Staff/admin: lấy token MỚI để có claim `role` (Security Rules của Realtime Database đọc claim này).
  Future<void> _ensureRoleClaim(UserProfile profile) async {
    if (!profile.role.isStaffOrAdmin) return;
    try {
      await _auth.idToken(forceRefresh: true);
    } catch (_) {
      // Không chặn đăng nhập; lần sau SDK tự làm mới token.
    }
  }

  // ---------------------------- Hành động ----------------------------

  /// Ném [AuthFailure] (thông báo tiếng Việt) nếu sai thông tin.
  Future<void> signIn(String email, String password) => _auth.signIn(email: email, password: password);

  /// Đăng ký: tạo tài khoản Firebase rồi tạo hồ sơ sinh viên trên backend.
  /// Nếu bước tạo hồ sơ lỗi (VD: trùng MSSV), người dùng vẫn đăng nhập và được đưa tới màn Hoàn tất hồ sơ.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String studentCode,
    String? phone,
  }) async {
    _registering = true;
    try {
      await _auth.register(email: email, password: password);
      _user ??= _auth.currentUser;
      await completeProfile(fullName: fullName, studentCode: studentCode, phone: phone);
    } on ApiException catch (e) {
      _draft = ProfileDraft(fullName: fullName, studentCode: studentCode, phone: phone, error: e);
      notifyListeners();
      rethrow;
    } finally {
      _registering = false;
    }
  }

  /// Tạo hồ sơ (màn Hoàn tất hồ sơ). Ném [ApiException] để form hiện lỗi theo từng ô.
  Future<void> completeProfile({required String fullName, required String studentCode, String? phone}) async {
    final generation = ++_generation;
    try {
      final profile = await _users.createMe(fullName: fullName, studentCode: studentCode, phone: phone);
      if (generation != _generation) return;
      _profile = profile;
      _set(AuthStatus.ready);
    } on ApiException {
      if (generation == _generation && _user != null) _set(AuthStatus.needsProfile);
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  /// Cập nhật hồ sơ đang hiển thị (sau khi sửa hồ sơ / đổi ảnh đại diện).
  void updateProfile(UserProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  Future<void> signOut() => _auth.signOut();

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _apiSub.cancel();
    super.dispose();
  }
}
