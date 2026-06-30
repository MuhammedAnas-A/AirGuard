import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SensorReading {
  final int? id;
  final double co2;
  final double o2;
  final DateTime timestamp;

  SensorReading({
    this.id,
    required this.co2,
    required this.o2,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'co2': co2,
      'o2': o2,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory SensorReading.fromMap(Map<String, dynamic> map) {
    return SensorReading(
      id: map['id'] as int?,
      co2: (map['co2'] as num).toDouble(),
      o2: (map['o2'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'airguard.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sensor_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            co2 REAL NOT NULL,
            o2 REAL NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> insertReading(double co2, double o2) async {
    final db = await database;
    await db.insert('sensor_readings', {
      'co2': co2,
      'o2': o2,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Returns readings filtered by time range.
  /// [fromTime] and [toTime] are optional bounds.
  Future<List<SensorReading>> getReadings({
    DateTime? fromTime,
    DateTime? toTime,
  }) async {
    final db = await database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (fromTime != null && toTime != null) {
      whereClause = 'timestamp >= ? AND timestamp <= ?';
      whereArgs = [
        fromTime.millisecondsSinceEpoch,
        toTime.millisecondsSinceEpoch,
      ];
    } else if (fromTime != null) {
      whereClause = 'timestamp >= ?';
      whereArgs = [fromTime.millisecondsSinceEpoch];
    } else if (toTime != null) {
      whereClause = 'timestamp <= ?';
      whereArgs = [toTime.millisecondsSinceEpoch];
    }

    final maps = await db.query(
      'sensor_readings',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) => SensorReading.fromMap(m)).toList();
  }

  /// Get readings from the last N minutes.
  Future<List<SensorReading>> getReadingsLastMinutes(int minutes) async {
    final from = DateTime.now().subtract(Duration(minutes: minutes));
    return getReadings(fromTime: from);
  }
}
