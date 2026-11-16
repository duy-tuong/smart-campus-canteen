import 'dart:async';
import 'dart:convert';

import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/data/remote/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Firebase Auth giả: giữ người dùng trong bộ nhớ, phát sự kiện như authStateChanges() thật.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? signedIn, this.password = 'Canteen@123'}) : _user = signedIn;

  final String password;
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  final List<bool> tokenRequests = [];
  int signOutCount = 0;
  String? lastResetEmail;

  /// Email đã có tài khoản (đăng ký lại sẽ báo email-already-in-use).
  final Set<String> existingEmails = {'sv01@smartcanteen.vn'};

  static String uidFor(String email) => 'uid-${email.split('@').first}';

  void emit(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != this.password) throw FirebaseAuthService.failureFor('invalid-credential');
    emit(AuthUser(uid: uidFor(email.trim()), email: email.trim()));
  }

  @override
  Future<void> register({required String email, required String password}) async {
    if (existingEmails.contains(email.trim())) throw FirebaseAuthService.failureFor('email-already-in-use');
    emit(AuthUser(uid: uidFor(email.trim()), email: email.trim()));
  }

  @override
  Future<void> sendPasswordReset(String email) async => lastResetEmail = email;

  @override
  Future<void> signOut() async {
    signOutCount++;
    emit(null);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    tokenRequests.add(forceRefresh);
    return _user == null ? null : 'token-${_user!.uid}';
  }

  Future<void> dispose() => _changes.close();
}

/// Hồ sơ JSON giống backend trả về.
Map<String, Object?> profileJson({
  String id = 'uid-sv01',
  String email = 'sv01@smartcanteen.vn',
  String fullName = 'Nguyễn Văn An',
  String role = 'student',
  String? studentCode = '0023410001',
}) =>
    {
      'id': id,
      'email': email,
      'fullName': fullName,
      'studentCode': studentCode,
      'phone': null,
      'avatarUrl': null,
      'role': role,
      'isActive': true,
      'createdAt': '2026-11-01T02:00:00Z',
      'lastLoginAt': null,
    };

http.Response jsonResponse(Object? body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response problem(int status, String code, String detail, {Map<String, List<String>>? errors}) =>
    jsonResponse({'status': status, 'title': detail, 'detail': detail, 'code': code, 'errors': ?errors}, status);

/// Backend giả cho /api/users/me: hồ sơ lưu theo uid (lấy từ token dạng `token-{uid}`).
class FakeBackend {
  final Map<String, Map<String, Object?>> profiles = {};
  final Set<String> locked = {};

  /// uid có token hết hạn → 401.
  final Set<String> expired = {};
  final Set<String> takenStudentCodes = {};
  final List<String> calls = [];
  bool offline = false;

  /// Trả lời trễ (để thử tình huống kết quả về muộn).
  Duration delay = Duration.zero;

  void addProfile(Map<String, Object?> json) => profiles[json['id'] as String] = json;

  ApiClient client({required AuthService auth}) => ApiClient(
        baseUrl: () => 'http://api.test',
        tokenProvider: auth.idToken,
        httpClient: MockClient(_handle),
      );

  Future<http.Response> _handle(http.Request request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    calls.add('${request.method} ${request.url.path}');
    if (request.url.path == '/api/health') return http.Response('{"status":"ok"}', 200);
    if (offline) throw http.ClientException('offline');

    final token = request.headers['Authorization']?.replaceFirst('Bearer token-', '');
    if (token == null || expired.contains(token)) return problem(401, 'UNAUTHORIZED', 'Chưa đăng nhập.');
    if (locked.contains(token)) return problem(403, 'ACCOUNT_LOCKED', 'Tài khoản đã bị khóa.');

    if (request.url.path == '/api/users/me' && request.method == 'GET') {
      final profile = profiles[token];
      return profile == null
          ? problem(404, 'PROFILE_NOT_FOUND', 'Tài khoản chưa có hồ sơ.')
          : jsonResponse(profile, 200);
    }
    if (request.url.path == '/api/users/me' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final code = body['studentCode'] as String;
      if (takenStudentCodes.contains(code)) {
        return problem(409, 'STUDENT_CODE_TAKEN', 'Mã số sinh viên đã được sử dụng.');
      }
      final profile = profileJson(id: token, email: '$token@test', fullName: body['fullName'] as String, studentCode: code);
      profiles[token] = profile;
      return jsonResponse(profile, 201);
    }
    return problem(404, 'NOT_FOUND', 'Không tìm thấy.');
  }
}
