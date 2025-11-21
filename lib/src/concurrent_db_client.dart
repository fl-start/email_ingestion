import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'email_schema.dart';

/// Request to DB isolate
class DbQueryRequest {
  final int requestId;
  final String type; // 'count', 'window', 'byMessageId'
  final Map<String, dynamic> payload;

  DbQueryRequest({
    required this.requestId,
    required this.type,
    required this.payload,
  });
}

/// Response from DB isolate
class DbQueryResponse {
  final int requestId;
  final String type;
  final TransferableTypedData? payload;
  final String? error;

  DbQueryResponse.success({
    required this.requestId,
    required this.type,
    this.payload,
  }) : error = null;

  DbQueryResponse.error({
    required this.requestId,
    required this.type,
    required this.error,
  }) : payload = null;
}

/// Entry point for DB worker isolate (must be top-level)
void dbWorkerIsolateEntry(List<SendPort> ports) async {
  final initPort = ports[0];
  final resultPort = ports[1];

  final receivePort = ReceivePort();
  // Send worker's receive port back via init port
  initPort.send(receivePort.sendPort);

  EmailDatabase? db;
  int lastAcceptedRequestId = 0;
  bool cancelAll = false;

  void send(DbQueryResponse resp) {
    // Send responses to result port
    resultPort.send(resp);
  }

  await for (final msg in receivePort) {
    if (msg is! DbQueryRequest) continue;

    if (msg.type == 'cancelAll') {
      cancelAll = true;
      lastAcceptedRequestId = msg.requestId;
      continue;
    }

    cancelAll = false;
    lastAcceptedRequestId = msg.requestId;

    try {
      if (msg.type == 'init') {
        final dbPath = msg.payload['dbPath'] as String;
        final file = File(dbPath);

        // Wait for file to exist (with timeout)
        var attempts = 0;
        while (!file.existsSync() && attempts < 50) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }

        if (!file.existsSync()) {
          send(DbQueryResponse.error(
            requestId: msg.requestId,
            type: 'init',
            error: 'Database file does not exist: $dbPath',
          ));
          continue;
        }

        // Open database - Drift will create schema automatically
        final executor = NativeDatabase(file);
        db = EmailDatabase(DatabaseConnection(executor));

        // Ensure schema is created by checking if tables exist
        // If not, they'll be created on first query/insert
        try {
          // Run a simple query to ensure schema is initialized
          try {
            await db.getEmailCount();
          } catch (e) {
            // Table might not exist yet - that's okay
            // It will be created when first email is inserted
          }
        } catch (e) {
          // Database might be new - that's fine
          // Schema will be created on first insert
        }

        send(DbQueryResponse.success(
          requestId: msg.requestId,
          type: 'init',
        ));
      } else if (msg.type == 'count') {
        if (db == null) {
          send(DbQueryResponse.error(
            requestId: msg.requestId,
            type: 'count',
            error: 'Database not initialized',
          ));
          continue;
        }

        int count = 0;
        try {
          count = await db.getEmailCount();
        } catch (e) {
          // If table doesn't exist yet, return 0
          if (e.toString().contains('no such table') ||
              e.toString().contains('does not exist')) {
            count = 0;
          } else {
            rethrow;
          }
        }

        if (msg.requestId != lastAcceptedRequestId || cancelAll) continue;

        final jsonBytes = Uint8List.fromList(
          utf8.encode('{"count": $count}'),
        );
        final ttd = TransferableTypedData.fromList([jsonBytes]);
        send(DbQueryResponse.success(
          requestId: msg.requestId,
          type: 'count',
          payload: ttd,
        ));
      } else if (msg.type == 'window') {
        if (db == null) {
          send(DbQueryResponse.error(
            requestId: msg.requestId,
            type: 'window',
            error: 'Database not initialized',
          ));
          continue;
        }

        final offset = msg.payload['offset'] as int;
        final limit = msg.payload['limit'] as int;

        List<Email> rows = [];
        try {
          rows = await db.fetchEmailWindow(offset: offset, limit: limit);
        } catch (e) {
          // If table doesn't exist yet, return empty list
          if (e.toString().contains('no such table') ||
              e.toString().contains('does not exist')) {
            rows = [];
          } else {
            rethrow;
          }
        }

        if (msg.requestId != lastAcceptedRequestId || cancelAll) continue;

        // Convert to JSON
        final listMaps = rows
            .map((r) => {
                  'id': r.id,
                  'messageId': r.messageId,
                  'fromAddr': r.fromAddr,
                  'toAddr': r.toAddr,
                  'subject': r.subject,
                  'receivedAt': r.receivedAt.toIso8601String(),
                })
            .toList();

        final jsonString = jsonEncode({'rows': listMaps});
        final jsonBytes = Uint8List.fromList(utf8.encode(jsonString));
        final ttd = TransferableTypedData.fromList([jsonBytes]);
        send(DbQueryResponse.success(
          requestId: msg.requestId,
          type: 'window',
          payload: ttd,
        ));
      }
    } catch (e, st) {
      send(DbQueryResponse.error(
        requestId: msg.requestId,
        type: msg.type,
        error: '$e\n$st',
      ));
    }
  }
}

/// Client for concurrent database queries using isolates
class ConcurrentDbClient {
  final String dbPath;
  final int workerCount;
  final List<SendPort> _workers = [];
  final ReceivePort _resultPort = ReceivePort();
  final Map<int, Completer<DbQueryResponse>> _pending = {};
  int _nextRequestId = 0;
  int _currentWorkerIndex = 0;

  ConcurrentDbClient({
    required this.dbPath,
    this.workerCount = 4,
  });

  Future<void> start() async {
    _resultPort.listen(_handleMessage);

    for (int i = 0; i < workerCount; i++) {
      try {
        final initPort = ReceivePort();
        // Pass both the init port and result port to the isolate
        await Isolate.spawn(
          dbWorkerIsolateEntry,
          [initPort.sendPort, _resultPort.sendPort],
        ).timeout(const Duration(seconds: 5));

        final workerPort = await initPort.first.timeout(
          const Duration(seconds: 5),
        ) as SendPort;
        _workers.add(workerPort);

        // Initialize this worker
        final initReq = DbQueryRequest(
          requestId: _nextRequestId++,
          type: 'init',
          payload: {'dbPath': dbPath},
        );
        final completer = Completer<DbQueryResponse>();
        _pending[initReq.requestId] = completer;
        workerPort.send(initReq);

        final response = await completer.future.timeout(
          const Duration(seconds: 10),
        );

        if (response.error != null) {
          throw Exception('Worker $i init failed: ${response.error}');
        }
      } catch (e) {
        throw Exception('Failed to start worker $i: $e');
      }
    }
  }

  void _handleMessage(dynamic msg) {
    if (msg is! DbQueryResponse) return;
    final completer = _pending.remove(msg.requestId);
    completer?.complete(msg);
  }

  SendPort _pickWorker() {
    final worker = _workers[_currentWorkerIndex];
    _currentWorkerIndex = (_currentWorkerIndex + 1) % _workers.length;
    return worker;
  }

  Future<DbQueryResponse> _sendRequest(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final requestId = _nextRequestId++;
    final completer = Completer<DbQueryResponse>();
    _pending[requestId] = completer;

    final worker = _pickWorker();
    worker.send(DbQueryRequest(
      requestId: requestId,
      type: type,
      payload: payload,
    ));

    return completer.future;
  }

  Future<int> getEmailCount() async {
    final resp = await _sendRequest('count', {});
    if (resp.error != null) throw Exception(resp.error);
    final bytes = resp.payload!.materialize().asUint8List();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return json['count'] as int;
  }

  Future<List<Map<String, dynamic>>> fetchEmailWindow({
    required int offset,
    required int limit,
  }) async {
    final resp = await _sendRequest('window', {
      'offset': offset,
      'limit': limit,
    });
    if (resp.error != null) throw Exception(resp.error);
    final bytes = resp.payload!.materialize().asUint8List();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return (json['rows'] as List).cast<Map<String, dynamic>>();
  }

  void dispose() {
    _resultPort.close();
    for (final worker in _workers) {
      worker.send(null); // shutdown
    }
  }
}
