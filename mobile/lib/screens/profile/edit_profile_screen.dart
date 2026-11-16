import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../data/device/image_source_service.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/user_api.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';
import '../auth/widgets/auth_layout.dart';
import '../auth/widgets/profile_fields.dart';
import 'account_screen.dart';

/// Sửa hồ sơ: họ tên, số điện thoại; MSSV chỉ được nhập khi chưa có (đã có thì khóa — khớp backend);
/// đổi / gỡ ảnh đại diện (chụp hoặc chọn ảnh, nén trên máy rồi tải lên multipart).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final UserProfile _initial = context.read<AuthProvider>().profile!;
  late final _fullName = TextEditingController(text: _initial.fullName);
  late final _phone = TextEditingController(text: _initial.phone ?? '');
  late final _studentCode = TextEditingController(text: _initial.studentCode ?? '');
  bool _saving = false;
  bool _uploading = false;
  ApiException? _error;

  bool get _studentCodeLocked => _initial.studentCode != null;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _studentCode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final profile = await context.read<UserApi>().updateMe(
        fullName: _fullName.text,
        phone: _phone.text,
        studentCode: _studentCodeLocked ? null : _studentCode.text,
      );
      auth.updateProfile(profile);
      messenger.showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ.')));
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    final profile = context.read<AuthProvider>().profile!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (profile.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Gỡ ảnh đại diện'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final users = context.read<UserApi>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'remove') {
        setState(() => _uploading = true);
        await users.removeAvatar();
        auth.updateProfile(await users.getMe());
        messenger.showSnackBar(const SnackBar(content: Text('Đã gỡ ảnh đại diện.')));
        return;
      }
      final image = await context.read<ImageSourceService>().pick(
        choice == 'camera' ? PickSource.camera : PickSource.gallery,
      );
      if (image == null) return;
      setState(() => _uploading = true);
      auth.updateProfile(await users.uploadAvatar(image.bytes, image.fileName));
      messenger.showSnackBar(const SnackBar(content: Text('Đã cập nhật ảnh đại diện.')));
    } on PlatformException {
      messenger.showSnackBar(const SnackBar(content: Text('Không mở được camera / thư viện ảnh.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ của tôi')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: MaxWidthBox(
          maxWidth: 480,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      UserAvatar(profile: profile, size: 104),
                      if (_uploading) const Positioned.fill(child: CircularProgressIndicator(strokeWidth: 3)),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filled(
                          tooltip: 'Đổi ảnh đại diện',
                          onPressed: _uploading ? null : _changeAvatar,
                          icon: const Icon(Icons.photo_camera_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  profile.email,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),
                FormErrorBanner(profileGeneralError(_error)),
                TextFormField(
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.fullName,
                  decoration: InputDecoration(
                    labelText: 'Họ và tên',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    errorText: profileFieldError(_error, 'fullName'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _studentCode,
                  readOnly: _studentCodeLocked,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  validator: _studentCodeLocked || profile.role.isStaffOrAdmin
                      ? null
                      : (v) => (v == null || v.isEmpty) ? null : Validators.studentCode(v),
                  decoration: InputDecoration(
                    labelText: 'Mã số sinh viên',
                    prefixIcon: const Icon(Icons.school_outlined),
                    suffixIcon: _studentCodeLocked ? const Icon(Icons.lock_outline_rounded) : null,
                    helperText: _studentCodeLocked ? 'MSSV đã xác nhận — liên hệ căn-tin nếu cần đổi.' : null,
                    errorText: profileFieldError(_error, 'studentCode'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  validator: Validators.optionalPhone,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại (không bắt buộc)',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    errorText: profileFieldError(_error, 'phone'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                BusyButton(label: 'Lưu thay đổi', busy: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
