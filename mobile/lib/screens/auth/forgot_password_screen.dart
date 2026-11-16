import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../data/firebase/auth_service.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_layout.dart';

/// Quên mật khẩu: Firebase gửi email chứa liên kết đặt lại mật khẩu.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  AuthFailure? _failure;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().sendPasswordReset(_email.text);
      if (mounted) setState(() => _sentTo = _email.text.trim());
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return AuthLayout(
      title: 'Quên mật khẩu',
      subtitle: 'Nhập email đã đăng ký, chúng tôi sẽ gửi liên kết để đặt mật khẩu mới.',
      showBack: true,
      child: AnimatedSwitcher(
        duration: AppDurations.normal,
        child: sentTo != null
            ? _SentView(key: const ValueKey('sent'), email: sentTo, onResend: () => setState(() => _sentTo = null))
            : Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormErrorBanner(_failure?.field == null ? _failure?.message : null),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (_) => _submit(),
                    validator: Validators.email,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      errorText: _failure?.field == 'email' ? _failure!.message : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BusyButton(label: 'Gửi liên kết', busy: _busy, onPressed: _submit),
                ]),
              ),
      ),
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({super.key, required this.email, required this.onResend});

  final String email;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = context.appColors.success;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: success.withValues(alpha: 0.10), borderRadius: AppRadius.lgAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.mark_email_read_rounded, color: success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Nếu email '),
              TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: ' đã đăng ký, bạn sẽ nhận được liên kết đặt lại mật khẩu trong vài phút. Nhớ xem cả mục Spam.'),
            ])),
          ),
        ]),
      ),
      const SizedBox(height: AppSpacing.lg),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Quay lại đăng nhập')),
      const SizedBox(height: AppSpacing.xs),
      TextButton(onPressed: onResend, child: Text('Gửi lại', style: theme.textTheme.labelLarge)),
    ]);
  }
}
