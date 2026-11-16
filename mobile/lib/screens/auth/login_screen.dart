import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../data/firebase/auth_service.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_layout.dart';

/// Đăng nhập bằng email + mật khẩu (Firebase Auth).
/// Đăng nhập thành công thì AuthGate (đang nghe authStateChanges) tự chuyển màn — màn này không điều hướng.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.showDemoAccounts = kDebugMode});

  /// Bản debug: hiện nút chọn nhanh tài khoản demo.
  final bool showDemoAccounts;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  AuthFailure? _failure;

  static const _demoPassword = 'Canteen@123';
  static const _demoAccounts = [
    ('Sinh viên', 'sv01@smartcanteen.vn'),
    ('Nhân viên', 'staff@smartcanteen.vn'),
    ('Quản trị', 'admin@smartcanteen.vn'),
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().signIn(_emailController.text, _passwordController.text);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo(String email) {
    _emailController.text = email;
    _passwordController.text = _demoPassword;
    setState(() => _failure = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _failure;

    return AuthLayout(
      title: 'Chào mừng trở lại',
      subtitle: 'Đăng nhập để đặt món và theo dõi đơn của bạn.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormErrorBanner(failure?.field == null ? failure?.message : null),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.mail_outline_rounded),
                errorText: failure?.field == 'email' ? failure!.message : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              controller: _passwordController,
              validator: Validators.password,
              errorText: failure?.field == 'password' ? failure!.message : null,
              onSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.forgotPassword, arguments: _emailController.text),
                child: const Text('Quên mật khẩu?'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            BusyButton(label: 'Đăng nhập', busy: _busy, onPressed: _submit),
            const SizedBox(height: AppSpacing.md),
            // Wrap (không phải Row): màn hẹp / chữ lớn thì tự xuống dòng thay vì tràn.
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Chưa có tài khoản?', style: theme.textTheme.bodyMedium),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                child: const Text('Đăng ký'),
              ),
            ]),
            if (widget.showDemoAccounts) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('Tài khoản demo', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Wrap(alignment: WrapAlignment.center, spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                for (final (label, email) in _demoAccounts)
                  ActionChip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 18),
                    label: Text(label),
                    onPressed: _busy ? null : () => _fillDemo(email),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
