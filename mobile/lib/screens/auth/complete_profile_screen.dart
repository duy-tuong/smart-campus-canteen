import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/remote/api_exception.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_layout.dart';
import 'widgets/profile_fields.dart';

/// Đã đăng nhập Firebase nhưng backend chưa có hồ sơ (404 PROFILE_NOT_FOUND) → nhập thông tin sinh viên.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _studentCode = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    // Điền lại dữ liệu từ màn Đăng ký nếu bước tạo hồ sơ ở đó bị lỗi.
    final draft = context.read<AuthProvider>().takeDraft();
    if (draft != null) {
      _fullName.text = draft.fullName;
      _studentCode.text = draft.studentCode;
      _phone.text = draft.phone ?? '';
      _error = draft.error;
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _studentCode.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().completeProfile(
            fullName: _fullName.text,
            studentCode: _studentCode.text,
            phone: _phone.text,
          );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final theme = Theme.of(context);
    return AuthLayout(
      title: 'Hoàn tất hồ sơ',
      subtitle: 'Bổ sung thông tin sinh viên để căn-tin xác nhận đơn khi bạn nhận món.',
      actions: [TextButton(onPressed: auth.signOut, child: const Text('Đăng xuất'))],
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Email'),
            subtitle: Text(auth.user?.email ?? '', style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: AppSpacing.xs),
          FormErrorBanner(profileGeneralError(_error)),
          ProfileFields(
            fullName: _fullName,
            studentCode: _studentCode,
            phone: _phone,
            error: _error,
            lastAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          BusyButton(label: 'Bắt đầu đặt món', busy: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
