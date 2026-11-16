import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// CSDL SQLite cục bộ (sqflite + path_provider) — dữ liệu dùng được khi KHÔNG có mạng:
///
///   cart_items 1──< cart_item_options           giỏ hàng (giữ lại khi tắt app), theo từng người dùng
///   orders     1──< order_items 1──< order_item_options   hóa đơn đã đặt (xem lại offline)
///   search_history                              từ khóa tìm kiếm gần đây
///
/// Bật khóa ngoại (PRAGMA foreign_keys) để xóa dòng cha thì dòng con tự xóa theo (ON DELETE CASCADE).
class DatabaseHelper {
  DatabaseHelper({DatabaseFactory? factory, this._path}) : _factory = factory ?? databaseFactory;

  static const fileName = 'canteen.db';
  static const version = 1;

  final DatabaseFactory _factory;
  final String? _path;
  Future<Database>? _opening;

  /// Mở CSDL một lần duy nhất (các lần gọi sau dùng lại kết nối).
  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final path = _path ?? p.join((await getApplicationDocumentsDirectory()).path, fileName);
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ----- Giỏ hàng -----
    batch.execute('''
      CREATE TABLE cart_items (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     TEXT    NOT NULL,
        food_id     INTEGER NOT NULL,
        food_name   TEXT    NOT NULL,
        image_url   TEXT,
        unit_price  INTEGER NOT NULL CHECK (unit_price >= 0),
        quantity    INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 50),
        note        TEXT    NOT NULL DEFAULT '',
        options_key TEXT    NOT NULL DEFAULT '',
        created_at  INTEGER NOT NULL,
        UNIQUE (user_id, food_id, options_key, note)
      )''');
    batch.execute('''
      CREATE TABLE cart_item_options (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        cart_item_id INTEGER NOT NULL REFERENCES cart_items(id) ON DELETE CASCADE,
        option_id    INTEGER NOT NULL,
        group_name   TEXT    NOT NULL,
        option_name  TEXT    NOT NULL,
        extra_price  INTEGER NOT NULL CHECK (extra_price >= 0)
      )''');
    batch.execute('CREATE INDEX idx_cart_items_user ON cart_items(user_id)');
    batch.execute('CREATE INDEX idx_cart_item_options_item ON cart_item_options(cart_item_id)');

    // ----- Lịch sử đơn (Id = GUID của backend, trùng với SQL Server và Firebase) -----
    batch.execute('''
      CREATE TABLE orders (
        id              TEXT    PRIMARY KEY,
        user_id         TEXT    NOT NULL,
        pickup_code     TEXT    NOT NULL,
        pickup_date     TEXT,
        status          TEXT    NOT NULL,
        payment_method  TEXT    NOT NULL,
        payment_status  TEXT    NOT NULL,
        subtotal        INTEGER NOT NULL DEFAULT 0,
        discount_amount INTEGER NOT NULL DEFAULT 0,
        total_amount    INTEGER NOT NULL,
        total_items     INTEGER NOT NULL DEFAULT 0,
        items_preview   TEXT    NOT NULL DEFAULT '',
        voucher_code    TEXT,
        note            TEXT,
        cancel_reason   TEXT,
        pickup_time     INTEGER,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL,
        synced_at       INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE order_items (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id      TEXT    NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        food_id       INTEGER,
        food_name     TEXT    NOT NULL,
        image_url     TEXT,
        unit_price    INTEGER NOT NULL,
        options_price INTEGER NOT NULL DEFAULT 0,
        quantity      INTEGER NOT NULL CHECK (quantity > 0),
        line_total    INTEGER NOT NULL,
        note          TEXT
      )''');
    batch.execute('''
      CREATE TABLE order_item_options (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        order_item_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
        group_name    TEXT    NOT NULL,
        option_name   TEXT    NOT NULL,
        extra_price   INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('CREATE INDEX idx_orders_user_created ON orders(user_id, created_at DESC)');
    batch.execute('CREATE INDEX idx_order_items_order ON order_items(order_id)');
    batch.execute('CREATE INDEX idx_order_item_options_item ON order_item_options(order_item_id)');

    // ----- Lịch sử tìm kiếm -----
    batch.execute('''
      CREATE TABLE search_history (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     TEXT    NOT NULL,
        keyword     TEXT    NOT NULL,
        searched_at INTEGER NOT NULL,
        UNIQUE (user_id, keyword)
      )''');

    await batch.commit(noResult: true);
  }

  /// Nâng cấp schema giữa các phiên bản app (thêm bước `if (oldVersion < N) ...` khi tăng [version]).
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {}
}
