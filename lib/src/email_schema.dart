import 'package:drift/drift.dart';

part 'email_schema.g.dart';

class Emails extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get messageId => text().withLength(min: 1, max: 255)();
  TextColumn get fromAddr => text().withLength(min: 1, max: 255)();
  TextColumn get toAddr => text().withLength(min: 1, max: 255)();
  TextColumn get subject => text().withLength(min: 1, max: 255)();
  DateTimeColumn get receivedAt => dateTime()();
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {messageId},
  ];
}

@DriftDatabase(tables: [Emails])
class EmailDatabase extends _$EmailDatabase {
  EmailDatabase(DatabaseConnection connection) : super.connect(connection);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Handle migrations if needed
    },
  );

  /// Insert email metadata (without body - body is stored in KV)
  Future<int> insertEmail({
    required String messageId,
    required String fromAddr,
    required String toAddr,
    required String subject,
    required DateTime receivedAt,
  }) {
    return into(emails).insert(
      EmailsCompanion.insert(
        messageId: messageId,
        fromAddr: fromAddr,
        toAddr: toAddr,
        subject: subject,
        receivedAt: receivedAt,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Get total count of emails
  Future<int> getEmailCount() async {
    final result = await (selectOnly(emails)..addColumns([emails.id.count()]))
        .getSingle();
    return result.read(emails.id.count()) ?? 0;
  }

  /// Fetch a window of emails for infinite scroll
  Future<List<Email>> fetchEmailWindow({
    required int offset,
    required int limit,
  }) {
    return (select(emails)
          ..orderBy([(e) => OrderingTerm.desc(e.receivedAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get email by Message-ID
  Future<Email?> getEmailByMessageId(String messageId) {
    return (select(emails)..where((e) => e.messageId.equals(messageId)))
        .getSingleOrNull();
  }
}

