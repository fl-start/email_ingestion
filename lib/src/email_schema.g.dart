// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_schema.dart';

// ignore_for_file: type=lint
class $EmailsTable extends Emails with TableInfo<$EmailsTable, Email> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _messageIdMeta =
      const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
      'message_id', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 255),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _fromAddrMeta =
      const VerificationMeta('fromAddr');
  @override
  late final GeneratedColumn<String> fromAddr = GeneratedColumn<String>(
      'from_addr', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 255),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _toAddrMeta = const VerificationMeta('toAddr');
  @override
  late final GeneratedColumn<String> toAddr = GeneratedColumn<String>(
      'to_addr', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 255),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
      'subject', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 255),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _receivedAtMeta =
      const VerificationMeta('receivedAt');
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
      'received_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, messageId, fromAddr, toAddr, subject, receivedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'emails';
  @override
  VerificationContext validateIntegrity(Insertable<Email> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_id')) {
      context.handle(_messageIdMeta,
          messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta));
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('from_addr')) {
      context.handle(_fromAddrMeta,
          fromAddr.isAcceptableOrUnknown(data['from_addr']!, _fromAddrMeta));
    } else if (isInserting) {
      context.missing(_fromAddrMeta);
    }
    if (data.containsKey('to_addr')) {
      context.handle(_toAddrMeta,
          toAddr.isAcceptableOrUnknown(data['to_addr']!, _toAddrMeta));
    } else if (isInserting) {
      context.missing(_toAddrMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
          _receivedAtMeta,
          receivedAt.isAcceptableOrUnknown(
              data['received_at']!, _receivedAtMeta));
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {messageId},
      ];
  @override
  Email map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Email(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      messageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_id'])!,
      fromAddr: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}from_addr'])!,
      toAddr: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}to_addr'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject'])!,
      receivedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}received_at'])!,
    );
  }

  @override
  $EmailsTable createAlias(String alias) {
    return $EmailsTable(attachedDatabase, alias);
  }
}

class Email extends DataClass implements Insertable<Email> {
  final int id;
  final String messageId;
  final String fromAddr;
  final String toAddr;
  final String subject;
  final DateTime receivedAt;
  const Email(
      {required this.id,
      required this.messageId,
      required this.fromAddr,
      required this.toAddr,
      required this.subject,
      required this.receivedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_id'] = Variable<String>(messageId);
    map['from_addr'] = Variable<String>(fromAddr);
    map['to_addr'] = Variable<String>(toAddr);
    map['subject'] = Variable<String>(subject);
    map['received_at'] = Variable<DateTime>(receivedAt);
    return map;
  }

  EmailsCompanion toCompanion(bool nullToAbsent) {
    return EmailsCompanion(
      id: Value(id),
      messageId: Value(messageId),
      fromAddr: Value(fromAddr),
      toAddr: Value(toAddr),
      subject: Value(subject),
      receivedAt: Value(receivedAt),
    );
  }

  factory Email.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Email(
      id: serializer.fromJson<int>(json['id']),
      messageId: serializer.fromJson<String>(json['messageId']),
      fromAddr: serializer.fromJson<String>(json['fromAddr']),
      toAddr: serializer.fromJson<String>(json['toAddr']),
      subject: serializer.fromJson<String>(json['subject']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageId': serializer.toJson<String>(messageId),
      'fromAddr': serializer.toJson<String>(fromAddr),
      'toAddr': serializer.toJson<String>(toAddr),
      'subject': serializer.toJson<String>(subject),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  Email copyWith(
          {int? id,
          String? messageId,
          String? fromAddr,
          String? toAddr,
          String? subject,
          DateTime? receivedAt}) =>
      Email(
        id: id ?? this.id,
        messageId: messageId ?? this.messageId,
        fromAddr: fromAddr ?? this.fromAddr,
        toAddr: toAddr ?? this.toAddr,
        subject: subject ?? this.subject,
        receivedAt: receivedAt ?? this.receivedAt,
      );
  Email copyWithCompanion(EmailsCompanion data) {
    return Email(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      fromAddr: data.fromAddr.present ? data.fromAddr.value : this.fromAddr,
      toAddr: data.toAddr.present ? data.toAddr.value : this.toAddr,
      subject: data.subject.present ? data.subject.value : this.subject,
      receivedAt:
          data.receivedAt.present ? data.receivedAt.value : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Email(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddr: $toAddr, ')
          ..write('subject: $subject, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, messageId, fromAddr, toAddr, subject, receivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Email &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.fromAddr == this.fromAddr &&
          other.toAddr == this.toAddr &&
          other.subject == this.subject &&
          other.receivedAt == this.receivedAt);
}

class EmailsCompanion extends UpdateCompanion<Email> {
  final Value<int> id;
  final Value<String> messageId;
  final Value<String> fromAddr;
  final Value<String> toAddr;
  final Value<String> subject;
  final Value<DateTime> receivedAt;
  const EmailsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.fromAddr = const Value.absent(),
    this.toAddr = const Value.absent(),
    this.subject = const Value.absent(),
    this.receivedAt = const Value.absent(),
  });
  EmailsCompanion.insert({
    this.id = const Value.absent(),
    required String messageId,
    required String fromAddr,
    required String toAddr,
    required String subject,
    required DateTime receivedAt,
  })  : messageId = Value(messageId),
        fromAddr = Value(fromAddr),
        toAddr = Value(toAddr),
        subject = Value(subject),
        receivedAt = Value(receivedAt);
  static Insertable<Email> custom({
    Expression<int>? id,
    Expression<String>? messageId,
    Expression<String>? fromAddr,
    Expression<String>? toAddr,
    Expression<String>? subject,
    Expression<DateTime>? receivedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (fromAddr != null) 'from_addr': fromAddr,
      if (toAddr != null) 'to_addr': toAddr,
      if (subject != null) 'subject': subject,
      if (receivedAt != null) 'received_at': receivedAt,
    });
  }

  EmailsCompanion copyWith(
      {Value<int>? id,
      Value<String>? messageId,
      Value<String>? fromAddr,
      Value<String>? toAddr,
      Value<String>? subject,
      Value<DateTime>? receivedAt}) {
    return EmailsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      fromAddr: fromAddr ?? this.fromAddr,
      toAddr: toAddr ?? this.toAddr,
      subject: subject ?? this.subject,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (fromAddr.present) {
      map['from_addr'] = Variable<String>(fromAddr.value);
    }
    if (toAddr.present) {
      map['to_addr'] = Variable<String>(toAddr.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmailsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddr: $toAddr, ')
          ..write('subject: $subject, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$EmailDatabase extends GeneratedDatabase {
  _$EmailDatabase(QueryExecutor e) : super(e);
  _$EmailDatabase.connect(DatabaseConnection c) : super.connect(c);
  $EmailDatabaseManager get managers => $EmailDatabaseManager(this);
  late final $EmailsTable emails = $EmailsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [emails];
}

typedef $$EmailsTableCreateCompanionBuilder = EmailsCompanion Function({
  Value<int> id,
  required String messageId,
  required String fromAddr,
  required String toAddr,
  required String subject,
  required DateTime receivedAt,
});
typedef $$EmailsTableUpdateCompanionBuilder = EmailsCompanion Function({
  Value<int> id,
  Value<String> messageId,
  Value<String> fromAddr,
  Value<String> toAddr,
  Value<String> subject,
  Value<DateTime> receivedAt,
});

class $$EmailsTableFilterComposer
    extends Composer<_$EmailDatabase, $EmailsTable> {
  $$EmailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fromAddr => $composableBuilder(
      column: $table.fromAddr, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toAddr => $composableBuilder(
      column: $table.toAddr, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
      column: $table.receivedAt, builder: (column) => ColumnFilters(column));
}

class $$EmailsTableOrderingComposer
    extends Composer<_$EmailDatabase, $EmailsTable> {
  $$EmailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageId => $composableBuilder(
      column: $table.messageId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fromAddr => $composableBuilder(
      column: $table.fromAddr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toAddr => $composableBuilder(
      column: $table.toAddr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
      column: $table.receivedAt, builder: (column) => ColumnOrderings(column));
}

class $$EmailsTableAnnotationComposer
    extends Composer<_$EmailDatabase, $EmailsTable> {
  $$EmailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get fromAddr =>
      $composableBuilder(column: $table.fromAddr, builder: (column) => column);

  GeneratedColumn<String> get toAddr =>
      $composableBuilder(column: $table.toAddr, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
      column: $table.receivedAt, builder: (column) => column);
}

class $$EmailsTableTableManager extends RootTableManager<
    _$EmailDatabase,
    $EmailsTable,
    Email,
    $$EmailsTableFilterComposer,
    $$EmailsTableOrderingComposer,
    $$EmailsTableAnnotationComposer,
    $$EmailsTableCreateCompanionBuilder,
    $$EmailsTableUpdateCompanionBuilder,
    (Email, BaseReferences<_$EmailDatabase, $EmailsTable, Email>),
    Email,
    PrefetchHooks Function()> {
  $$EmailsTableTableManager(_$EmailDatabase db, $EmailsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmailsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmailsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> messageId = const Value.absent(),
            Value<String> fromAddr = const Value.absent(),
            Value<String> toAddr = const Value.absent(),
            Value<String> subject = const Value.absent(),
            Value<DateTime> receivedAt = const Value.absent(),
          }) =>
              EmailsCompanion(
            id: id,
            messageId: messageId,
            fromAddr: fromAddr,
            toAddr: toAddr,
            subject: subject,
            receivedAt: receivedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String messageId,
            required String fromAddr,
            required String toAddr,
            required String subject,
            required DateTime receivedAt,
          }) =>
              EmailsCompanion.insert(
            id: id,
            messageId: messageId,
            fromAddr: fromAddr,
            toAddr: toAddr,
            subject: subject,
            receivedAt: receivedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EmailsTableProcessedTableManager = ProcessedTableManager<
    _$EmailDatabase,
    $EmailsTable,
    Email,
    $$EmailsTableFilterComposer,
    $$EmailsTableOrderingComposer,
    $$EmailsTableAnnotationComposer,
    $$EmailsTableCreateCompanionBuilder,
    $$EmailsTableUpdateCompanionBuilder,
    (Email, BaseReferences<_$EmailDatabase, $EmailsTable, Email>),
    Email,
    PrefetchHooks Function()>;

class $EmailDatabaseManager {
  final _$EmailDatabase _db;
  $EmailDatabaseManager(this._db);
  $$EmailsTableTableManager get emails =>
      $$EmailsTableTableManager(_db, _db.emails);
}
