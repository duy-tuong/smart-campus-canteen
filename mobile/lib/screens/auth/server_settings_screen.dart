import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../data/remote/api_client.dart';
import '../../providers/settings_provider.dart';

enum _CheckState { idle, checking, ok, failed }

/// Cài đặt địa chỉ backend — đổi được khi chạy APK trên điện thoại thật (IP laptop trong cùng Wi-Fi)
/// mà không cần build lại.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  _CheckState _check = _CheckState.idle;
  String? _checkedUrl;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: context.read<SettingsProvider>().apiBaseUrl)
      ..addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Sửa địa chỉ → kết quả kiểm tra cũ không còn đúng.
  void _onUrlChanged() {
    if (_check != _CheckState.idle && AppConfig.normalizeBaseUrl(_urlController.text) != _checkedUrl) {
      setState(() => _check = _CheckState.idle);
    }
  }

  Future<bool> _testConnection() async {
    if (!_formKey.currentState!.validate()) return false;
    FocusScope.of(context).unfocus();
    final url = AppConfig.normalizeBaseUrl(_urlController.text);
    setState(() {
      _check = _CheckState.checking;
      _checkedUrl = url;
    });
    final ok = await context.read<ApiClient>().checkHealth(baseUrl: url);
    if (!mounted) return ok;
    setState(() => _check = ok ? _CheckState.ok : _CheckState.failed);
    return ok;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = _check == _CheckState.ok && _checkedUrl == AppConfig.normalizeBaseUrl(_urlController.text)
        ? true
        : await _testConnection();
    if (!mounted) return;
    if (!ok) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Không kết nối được'),
          content: const Text('Máy chủ không phản hồi ở địa chỉ này. Vẫn lưu địa chỉ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Sửa lại')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vẫn lưu')),
          ],
        ),
      );
      if (saveAnyway != true) return;
    }

    await settings.setApiBaseUrl(_urlController.text);
    messenger.showSnackBar(const SnackBar(content: Text('Đã lưu địa chỉ máy chủ.')));
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _reset() async {
    await context.read<SettingsProvider>().resetApiBaseUrl();
    _urlController.text = AppConfig.defaultApiBaseUrl;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDefault = context.watch<SettingsProvider>().isUsingDefaultServer;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt máy chủ')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: MaxWidthBox(
            maxWidth: 560,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Địa chỉ backend', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'App lấy thực đơn, đặt món và thanh toán qua máy chủ này.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    validator: Validators.serverUrl,
                    onFieldSubmitted: (_) => _testConnection(),
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ máy chủ',
                      hintText: 'http://192.168.1.10:5265',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CheckResult(state: _check),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _check == _CheckState.checking ? null : _testConnection,
                    icon: _check == _CheckState.checking
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('Kiểm tra kết nối'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(onPressed: _check == _CheckState.checking ? null : _save, child: const Text('Lưu')),
                  if (!isDefault) ...[
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(onPressed: _reset, child: const Text('Khôi phục mặc định')),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const _HelpCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckResult extends StatelessWidget {
  const _CheckResult({required this.state});

  final _CheckState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (IconData? icon, Color? color, String? text) = switch (state) {
      _CheckState.ok => (Icons.check_circle_rounded, colors.success, 'Kết nối thành công'),
      _CheckState.failed => (
        Icons.error_rounded,
        colors.cancelled,
        'Không kết nối được — kiểm tra địa chỉ, backend và Wi-Fi',
      ),
      _ => (null, null, null),
    };
    return AnimatedSwitcher(
      duration: AppDurations.normal,
      child: icon == null
          ? const SizedBox(key: ValueKey('none'), height: 20)
          : Row(
              key: ValueKey(state),
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(text!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
                ),
              ],
            ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget row(IconData icon, String title, String body) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(body, style: muted),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              Icons.phone_android_rounded,
              'Máy ảo Android',
              'http://10.0.2.2:5265 — trỏ về máy tính đang chạy backend.',
            ),
            row(
              Icons.wifi_rounded,
              'Điện thoại thật',
              'Dùng IP Wi-Fi của laptop (xem bằng lệnh ipconfig), ví dụ http://192.168.1.10:5265. '
                  'Điện thoại và laptop phải chung mạng, tường lửa Windows mở cổng 5265.',
            ),
          ],
        ),
      ),
    );
  }
}
