import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// CRUD lịch sử tìm kiếm (bảng search_history) — gợi ý "Tìm gần đây" khi mở ô tìm kiếm.
class SearchHistoryDao {
  SearchHistoryDao(this._helper, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DatabaseHelper _helper;
  final DateTime Function() _clock;

  /// Giữ tối đa bấy nhiêu từ khóa mỗi người (xóa bớt từ cũ nhất).
  static const maxEntries = 20;

  /// Lưu từ khóa. Tìm lại từ đã có → chỉ cập nhật thời điểm (đưa lên đầu danh sách).
  Future<void> add(String userId, String keyword) async {
    final value = keyword.trim();
    if (value.isEmpty) return;

    final db = await _helper.database;
    await db.transaction((txn) async {
      await txn.insert('search_history', {
        'user_id': userId,
        'keyword': value,
        'searched_at': _clock().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete(
        '''
        DELETE FROM search_history
        WHERE user_id = ? AND id NOT IN (
          SELECT id FROM search_history WHERE user_id = ? ORDER BY searched_at DESC, id DESC LIMIT ?
        )''',
        [userId, userId, maxEntries],
      );
    });
  }

  /// Từ khóa gần đây nhất trước.
  Future<List<String>> recent(String userId, {int limit = 8}) async {
    final db = await _helper.database;
    final rows = await db.query(
      'search_history',
      columns: ['keyword'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => r['keyword'] as String).toList();
  }

  Future<void> remove(String userId, String keyword) async {
    final db = await _helper.database;
    await db.delete('search_history', where: 'user_id = ? AND keyword = ?', whereArgs: [userId, keyword.trim()]);
  }

  Future<void> clear(String userId) async {
    final db = await _helper.database;
    await db.delete('search_history', where: 'user_id = ?', whereArgs: [userId]);
  }
}
