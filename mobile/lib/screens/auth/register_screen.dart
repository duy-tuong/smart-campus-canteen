import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../data/firebase/auth_service.dart';
import '../../data/remote/api_exception.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_layout.dart';
import 'widgets/profile_fields.dart';

/// Đăng ký tài khoản sinh viên: Firebase `createUserWithEmailAndPassword` → `POST /api/users/me`.
/// Thành công thì AuthGate tự đóng màn này và đưa vào app.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _studentCode = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  AuthFailure? _authFailure;
  ApiException? _apiError;

  @override
  void dispose() {
    for (final c in [_fullName, _studentCode, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _authFailure = null;
      _apiError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().register(
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
            studentCode: _studentCode.text,
            phone: _phone.text,
          );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _authFailure = e);
    } on ApiException catch (e) {
      // Tài khoản Firebase đã tạo; AuthGate chuyển sang màn Hoàn tất hồ sơ (điền sẵn dữ liệu + lỗi).
      if (mounted) setState(() => _apiError = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = _authFailure;
    return AuthLayout(
      title: 'Tạo tài khoản',
      subtitle: 'Dành cho sinh viên. Nhân viên căn-tin dùng tài khoản do quản trị viên cấp.',
      showBack: true,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormErrorBanner(auth != null && auth.field == null ? auth.message : profileGeneralError(_apiError)),
            ProfileFields(fullName: _fullName, studentCode: _studentCode, phone: _phone, error: _apiError),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.mail_outline_rounded),
                errorText: auth?.field == 'email' ? auth!.message : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _password,
              validator: Validators.password,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              errorText: auth?.field == 'password' ? auth!.message : null,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _confirm,
              label: 'Nhập lại mật khẩu',
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v != _password.text ? 'Mật khẩu nhập lại không khớp.' : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            BusyButton(label: 'Đăng ký', busy: _busy, onPressed: _submit),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đã có tài khoản? Đăng nhập')),
          ]),
        ),
      ),
    );
  }
}
