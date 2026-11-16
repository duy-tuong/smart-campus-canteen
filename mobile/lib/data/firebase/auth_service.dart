import 'package:firebase_auth/firebase_auth.dart';

/// Người dùng đã đăng nhập Firebase (chỉ phần app cần — tách khỏi SDK để test được).
class AuthUser {
  const AuthUser({required this.uid, this.email});

  final String uid;
  final String? email;
}

/// Lỗi xác thực đã chuyển sang tiếng Việt. [field] cho biết ô nhập liên quan ('email' / 'password').
class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message, {this.field});

  final String code;
  final String message;
  final String? field;

  @override
  String toString() => 'AuthFailure($code: $message)';
}

/// Dịch vụ xác thực (Firebase Authentication — email/mật khẩu).
abstract interface class AuthService {
  /// Phát người dùng hiện tại mỗi khi đăng nhập / đăng xuất (phần tử đầu tiên = trạng thái lúc mở app).
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  Future<void> signIn({required String email, required String password});

  /// Tạo tài khoản Firebase (đồng thời đăng nhập luôn).
  Future<void> register({required String email, required String password});

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// ID token gửi kèm REST API. [forceRefresh] = lấy token mới có claim `role` vừa được cấp.
  Future<String?> idToken({bool forceRefresh = false});
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth) {
    _auth.setLanguageCode('vi'); // email đặt lại mật khẩu bằng tiếng Việt
  }

  final FirebaseAuth _auth;

  static AuthUser? _map(User? user) => user == null ? null : AuthUser(uid: user.uid, email: user.email);

  /// Bọc `FirebaseAuth.authStateChanges()` bằng async* / yield — chuyển User của SDK sang [AuthUser].
  @override
  Stream<AuthUser?> authStateChanges() async* {
    await for (final user in _auth.authStateChanges()) {
      yield _map(user);
    }
  }

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));

  @override
  Future<void> register({required String email, required String password}) =>
      _guard(() => _auth.createUserWithEmailAndPassword(email: email.trim(), password: password));

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => _auth.currentUser?.getIdToken(forceRefresh);

  static Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw failureFor(e.code);
    }
  }

  /// Mã lỗi của Firebase Auth → câu thông báo tiếng Việt.
  static AuthFailure failureFor(String code) => switch (code) {
        'invalid-email' => AuthFailure(code, 'Email không đúng định dạng.', field: 'email'),
        // Firebase gộp "sai mật khẩu" và "không có tài khoản" thành invalid-credential để chống dò email.
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'INVALID_LOGIN_CREDENTIALS' =>
          AuthFailure(code, 'Email hoặc mật khẩu không đúng.'),
        'user-disabled' => AuthFailure(code, 'Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên căn-tin.'),
        'email-already-in-use' => AuthFailure(code, 'Email này đã được đăng ký. Hãy đăng nhập.', field: 'email'),
        'weak-password' => AuthFailure(code, 'Mật khẩu quá yếu (tối thiểu 6 ký tự).', field: 'password'),
        'too-many-requests' => AuthFailure(code, 'Thử sai quá nhiều lần. Vui lòng đợi vài phút rồi thử lại.'),
        'network-request-failed' => AuthFailure(code, 'Không có kết nối mạng. Kiểm tra Wi-Fi hoặc dữ liệu di động.'),
        'operation-not-allowed' => AuthFailure(code, 'Đăng nhập bằng email chưa được bật trên Firebase.'),
        _ => AuthFailure(code, 'Không thể xác thực ($code). Vui lòng thử lại.'),
      };
}
