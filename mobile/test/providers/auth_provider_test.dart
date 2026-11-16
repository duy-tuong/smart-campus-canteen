import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/data/remote/api_client.dart';
import 'package:campus_canteen/data/remote/api_exception.dart';
import 'package:campus_canteen/data/remote/user_api.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeAuthService auth;
  late FakeBackend backend;
  late ApiClient api;
  late AuthProvider provider;
  var created = false;

  const sv01 = AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn');

  AuthProvider create() {
    created = true;
    return provider = AuthProvider(auth: auth, users: UserApi(api), api: api);
  }

  /// Chờ provider đạt trạng thái mong muốn (các bước bất đồng bộ: stream → HTTP → notify).
  Future<void> waitFor(AuthStatus status) async {
    for (var i = 0; i < 100 && provider.status != status; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(provider.status, status);
  }

  setUp(() {
    auth = FakeAuthService();
    backend = FakeBackend()..addProfile(profileJson());
    api = backend.client(auth: auth);
  });

  tearDown(() {
    if (created) provider.dispose();
    created = false;
  });

  test('chưa đăng nhập → signedOut', () async {
    create();
    await waitFor(AuthStatus.signedOut);
    expect(provider.isSignedIn, isFalse);
  });

  test('đăng nhập → tải hồ sơ → ready (sinh viên, không cần làm mới token)', () async {
    create();
    await waitFor(AuthStatus.signedOut);

    await provider.signIn('sv01@smartcanteen.vn', 'Canteen@123');
    await waitFor(AuthStatus.ready);

    expect(provider.profile!.fullName, 'Nguyễn Văn An');
    expect(provider.profile!.role, UserRole.student);
    expect(auth.tokenRequests, isNot(contains(true)));
  });

  test('sai mật khẩu → AuthFailure tiếng Việt, vẫn signedOut', () async {
    create();
    await expectLater(
      provider.signIn('sv01@smartcanteen.vn', 'sai'),
      throwsA(isA<AuthFailure>().having((e) => e.message, 'message', 'Email hoặc mật khẩu không đúng.')),
    );
    await waitFor(AuthStatus.signedOut);
  });

  test('nhân viên → lấy token mới (forceRefresh) để có claim role', () async {
    backend.addProfile(profileJson(id: 'uid-staff', email: 'staff@smartcanteen.vn', role: 'staff', studentCode: null));
    create();
    await provider.signIn('staff@smartcanteen.vn', 'Canteen@123');
    await waitFor(AuthStatus.ready);
    expect(provider.profile!.role.isStaffOrAdmin, isTrue);
    expect(auth.tokenRequests, contains(true));
  });

  test('chưa có hồ sơ (404) → needsProfile → hoàn tất hồ sơ → ready', () async {
    auth = FakeAuthService(
      signedIn: const AuthUser(uid: 'uid-new', email: 'new@x.vn'),
    );
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.needsProfile);

    await provider.completeProfile(fullName: 'Trần Thị Bình', studentCode: '0023419999');
    expect(provider.status, AuthStatus.ready);
    expect(provider.profile!.studentCode, '0023419999');
  });

  test('hoàn tất hồ sơ trùng MSSV → ném lỗi, vẫn needsProfile', () async {
    backend.takenStudentCodes.add('0023410001');
    auth = FakeAuthService(signedIn: const AuthUser(uid: 'uid-new'));
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.needsProfile);

    await expectLater(
      provider.completeProfile(fullName: 'Bình', studentCode: '0023410001'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.studentCodeTaken)),
    );
    expect(provider.status, AuthStatus.needsProfile);
  });

  test('tài khoản bị khóa (403) → locked', () async {
    backend.locked.add('uid-sv01');
    auth = FakeAuthService(signedIn: sv01);
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.locked);
  });

  test('mất mạng → error; thử lại khi có mạng → ready', () async {
    backend.offline = true;
    auth = FakeAuthService(signedIn: sv01);
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.error);
    expect((provider.error as ApiException).isNetwork, isTrue);

    backend.offline = false;
    await provider.loadProfile();
    expect(provider.status, AuthStatus.ready);
  });

  test('request bất kỳ trả 401 (token hết hạn) → tự đăng xuất', () async {
    auth = FakeAuthService(signedIn: sv01);
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.ready);

    backend.expired.add('uid-sv01');
    await expectLater(api.get('/api/orders/me'), throwsA(isA<ApiException>()));
    await waitFor(AuthStatus.signedOut);
    expect(auth.signOutCount, 1);
  });

  test('request bất kỳ trả ACCOUNT_LOCKED → locked', () async {
    auth = FakeAuthService(signedIn: sv01);
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.ready);

    backend.locked.add('uid-sv01');
    await expectLater(api.get('/api/orders/me'), throwsA(isA<ApiException>()));
    await waitFor(AuthStatus.locked);
  });

  test('đăng ký: tạo Firebase + hồ sơ, không gọi GET /me song song', () async {
    create();
    await waitFor(AuthStatus.signedOut);

    await provider.register(
      email: 'moi@smartcanteen.vn',
      password: 'Canteen@123',
      fullName: 'Lê Minh Châu',
      studentCode: '0023418888',
    );
    expect(provider.status, AuthStatus.ready);
    expect(provider.profile!.fullName, 'Lê Minh Châu');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, ['POST /api/users/me']);
    expect(provider.status, AuthStatus.ready);
  });

  test('đăng ký trùng MSSV → needsProfile + bản nháp để điền lại', () async {
    backend.takenStudentCodes.add('0023410001');
    create();
    await waitFor(AuthStatus.signedOut);

    await expectLater(
      provider.register(
        email: 'moi@x.vn',
        password: 'Canteen@123',
        fullName: 'Châu',
        studentCode: '0023410001',
        phone: '0912345678',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(provider.status, AuthStatus.needsProfile);
    final draft = provider.takeDraft()!;
    expect(draft.fullName, 'Châu');
    expect(draft.phone, '0912345678');
    expect(draft.error!.code, ApiErrorCodes.studentCodeTaken);
    expect(provider.takeDraft(), isNull, reason: 'chỉ lấy một lần');
  });

  test('đăng xuất khi hồ sơ còn đang tải → kết quả về muộn bị bỏ qua', () async {
    backend.delay = const Duration(milliseconds: 50);
    auth = FakeAuthService(signedIn: sv01);
    api = backend.client(auth: auth);
    create();
    await waitFor(AuthStatus.loadingProfile);

    await provider.signOut();
    await waitFor(AuthStatus.signedOut);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(provider.status, AuthStatus.signedOut);
    expect(provider.profile, isNull);
  });

  test('lỗi Firebase được dịch sang tiếng Việt, gắn đúng ô nhập', () {
    expect(FirebaseAuthService.failureFor('email-already-in-use').field, 'email');
    expect(FirebaseAuthService.failureFor('weak-password').field, 'password');
    expect(FirebaseAuthService.failureFor('user-disabled').message, contains('bị khóa'));
    expect(FirebaseAuthService.failureFor('network-request-failed').message, contains('kết nối mạng'));
    expect(FirebaseAuthService.failureFor('xyz').message, contains('xyz'));
  });
}
