import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/debouncer.dart';
import '../../data/local/search_history_dao.dart';
import '../../data/remote/menu_api.dart';
import '../../models/menu.dart';
import '../../models/paged_result.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'menu_actions.dart';

/// Tìm món. Không bao giờ để màn hình trống:
///  - chưa gõ → "Tìm gần đây" (SQLite: search_history) + "Món bán chạy";
///  - đang gõ → kết quả từ API (debounce 400ms, tìm không dấu: "com ga" ra "Cơm gà").
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer();

  late final SearchHistoryDao _history = context.read<SearchHistoryDao>();
  late final MenuApi _api = context.read<MenuApi>();
  late final String _userId = context.read<AuthProvider>().user!.uid;

  late Future<List<String>> _recentFuture;
  late final Future<PagedResult<FoodSummary>> _popularFuture;
  Future<PagedResult<FoodSummary>>? _resultsFuture;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _recentFuture = _history.recent(_userId);
    _popularFuture = _api.foods(const FoodQuery(sort: FoodSort.popular), pageSize: 8);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final text = _controller.text.trim();
    if (text == _keyword) return;
    if (text.isEmpty) {
      _debouncer.cancel();
      setState(() {
        _keyword = '';
        _resultsFuture = null;
      });
      return;
    }
    // Đợi người dùng ngừng gõ 400ms mới gọi API.
    _debouncer.run(() {
      if (!mounted) return;
      setState(() {
        _keyword = text;
        _resultsFuture = _api.foods(FoodQuery(q: text, sort: FoodSort.popular), pageSize: 30);
      });
    });
  }

  Future<void> _saveKeyword([String? keyword]) async {
    final value = (keyword ?? _controller.text).trim();
    if (value.isEmpty) return;
    await _history.add(_userId, value);
    _refreshRecent();
  }

  /// Đọc lại lịch sử tìm kiếm. setState dạng khối — closure KHÔNG được trả về Future.
  void _refreshRecent() {
    if (!mounted) return;
    setState(() {
      _recentFuture = _history.recent(_userId);
    });
  }

  void _retrySearch() => setState(() {
    _resultsFuture = _api.foods(FoodQuery(q: _keyword, sort: FoodSort.popular), pageSize: 30);
  });

  void _useKeyword(String keyword) {
    _controller
      ..text = keyword
      ..selection = TextSelection.collapsed(offset: keyword.length);
    _saveKeyword(keyword);
  }

  Future<void> _removeKeyword(String keyword) async {
    await _history.remove(_userId, keyword);
    _refreshRecent();
  }

  Future<void> _clearHistory() async {
    await _history.clear(_userId);
    _refreshRecent();
  }

  void _open(FoodSummary food) {
    if (_keyword.isNotEmpty) _saveKeyword(_keyword);
    openFoodDetail(context, food);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _saveKeyword(),
          decoration: InputDecoration(
            hintText: 'Tìm món: cơm gà, trà sữa...',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(tooltip: 'Xóa', icon: const Icon(Icons.close_rounded), onPressed: _controller.clear),
            ),
          ),
        ),
      ),
      body: MaxWidthBox(child: _resultsFuture == null ? _suggestions(context) : _results(context)),
    );
  }

  Widget _suggestions(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        FutureBuilder<List<String>>(
          future: _recentFuture,
          builder: (context, snapshot) {
            final recent = snapshot.data ?? const [];
            if (recent.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader('Tìm gần đây', actionLabel: 'Xóa tất cả', onAction: _clearHistory),
                for (final keyword in recent)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(keyword),
                    onTap: () => _useKeyword(keyword),
                    trailing: IconButton(
                      tooltip: 'Xóa "$keyword"',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => _removeKeyword(keyword),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
            );
          },
        ),
        const SectionHeader('Món bán chạy'),
        const SizedBox(height: AppSpacing.xs),
        FutureBuilder<PagedResult<FoodSummary>>(
          future: _popularFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(padding: AppSpacing.pagePadding, child: SkeletonBox(height: 40));
            }
            final foods = snapshot.data?.items ?? const <FoodSummary>[];
            if (foods.isEmpty) {
              return Padding(
                padding: AppSpacing.pagePadding,
                child: Text('Chưa tải được gợi ý.', style: theme.textTheme.bodySmall),
              );
            }
            return Padding(
              padding: AppSpacing.pagePadding,
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final food in foods)
                    ActionChip(
                      avatar: Icon(Icons.local_fire_department_rounded, size: 18, color: theme.colorScheme.primary),
                      label: Text(food.name),
                      onPressed: () => openFoodDetail(context, food),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    return AsyncValueView<PagedResult<FoodSummary>>(
      future: _resultsFuture,
      onRetry: _retrySearch,
      isEmpty: (page) => page.items.isEmpty,
      empty: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Không tìm thấy “$_keyword”',
        message: 'Thử từ khóa ngắn hơn, hoặc gõ không dấu như "com ga".',
      ),
      builder: (context, page) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        itemCount: page.items.length,
        itemBuilder: (context, i) {
          final food = page.items[i];
          final unavailable = food.isSoldOut || !food.isAvailable;
          return ListTile(
            onTap: () => _open(food),
            leading: AppNetworkImage(food.imageUrl, width: 56, height: 56, borderRadius: AppRadius.mdAll),
            title: Text(food.name),
            subtitle: Row(
              children: [
                RatingLabel(average: food.averageRating, count: food.ratingCount),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    '· ${food.categoryName}${unavailable ? ' · Hết món' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: PriceText(food.price),
          );
        },
      ),
    );
  }
}
