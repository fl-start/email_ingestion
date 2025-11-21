import 'dart:async';
import 'package:dio/dio.dart';
import 'package:parallel_dio_pool/parallel_dio_pool.dart';
import 'package:hashed_kv_store/hashed_kv_store.dart';
import 'package:multi_identity_drift/multi_identity_drift.dart';
import 'email_schema.dart';

/// Result of email ingestion
class EmailIngestionResult {
  final String messageId;
  final bool httpSuccess;
  final bool kvSuccess;
  final bool dbSuccess;
  final String? error;

  EmailIngestionResult({
    required this.messageId,
    required this.httpSuccess,
    required this.kvSuccess,
    required this.dbSuccess,
    this.error,
  });

  bool get success => httpSuccess && kvSuccess && dbSuccess;
}

/// Composable pipeline: dio.pipe(kv).pipe(db)
/// 
/// This pipeline:
/// 1. Fetches emails using parallel_dio_pool
/// 2. Streams body to KV store (hashed_kv_store)
/// 3. Inserts metadata to SQLite database (multi_identity_drift)
class EmailIngestionPipeline {
  final ParallelDioClient _dioClient;
  final MultiIsolateKvStoreClient _kvStore;
  final IdentityDbHandle<EmailDatabase> _dbHandle;
  final String _baseUrl;

  EmailIngestionPipeline({
    required ParallelDioClient dioClient,
    required MultiIsolateKvStoreClient kvStore,
    required IdentityDbHandle<EmailDatabase> dbHandle,
    required String baseUrl,
  })  : _dioClient = dioClient,
        _kvStore = kvStore,
        _dbHandle = dbHandle,
        _baseUrl = baseUrl;

  /// Ingest a single email
  /// 
  /// Fetches email body from server, stores in KV, then inserts metadata in DB
  Future<EmailIngestionResult> ingestEmail({
    required String messageId,
    required String fromAddr,
    required String toAddr,
    required String subject,
    required DateTime receivedAt,
  }) async {
    try {
      // Step 1: Fetch email body via HTTP
      // URL encode the message ID to handle special characters
      final encodedMessageId = Uri.encodeComponent(messageId);
      final url = '$_baseUrl/emails/$encodedMessageId/body';
      final request = ParallelDioRequest(
        method: 'GET',
        url: url,
        options: Options(responseType: ResponseType.stream),
        tag: messageId,
      );

      final resultsStream = _dioClient.executeAll([request]);
      final httpResult = await resultsStream.first;

      if (!httpResult.isSuccess || httpResult.response == null) {
        return EmailIngestionResult(
          messageId: messageId,
          httpSuccess: false,
          kvSuccess: false,
          dbSuccess: false,
          error: 'HTTP failed: ${httpResult.errorKind}',
        );
      }

      // Step 2: Pipe HTTP stream to KV store
      final response = httpResult.response!;
      final body = response.data;

      if (body is! ResponseBody) {
        return EmailIngestionResult(
          messageId: messageId,
          httpSuccess: false,
          kvSuccess: false,
          dbSuccess: false,
          error: 'Invalid response body type',
        );
      }

      try {
        await _kvStore.writeFromStream(
          messageId,
          body.stream,
          extension: 'eml',
        );
      } catch (e) {
        return EmailIngestionResult(
          messageId: messageId,
          httpSuccess: true,
          kvSuccess: false,
          dbSuccess: false,
          error: 'KV write failed: $e',
        );
      }

      // Step 3: Insert metadata to database (only if KV succeeded)
      try {
        await _dbHandle.db.insertEmail(
          messageId: messageId,
          fromAddr: fromAddr,
          toAddr: toAddr,
          subject: subject,
          receivedAt: receivedAt,
        );
      } catch (e) {
        return EmailIngestionResult(
          messageId: messageId,
          httpSuccess: true,
          kvSuccess: true,
          dbSuccess: false,
          error: 'DB insert failed: $e',
        );
      }

      return EmailIngestionResult(
        messageId: messageId,
        httpSuccess: true,
        kvSuccess: true,
        dbSuccess: true,
      );
    } catch (e, st) {
      return EmailIngestionResult(
        messageId: messageId,
        httpSuccess: false,
        kvSuccess: false,
        dbSuccess: false,
        error: '$e\n$st',
      );
    }
  }

  /// Ingest multiple emails in parallel
  /// 
  /// Returns a stream of results as they complete
  Stream<EmailIngestionResult> ingestEmails(
    List<EmailMetadata> emails,
  ) async* {
    // Create requests for all emails
    final requests = emails.map((email) {
      final encodedMessageId = Uri.encodeComponent(email.messageId);
      final url = '$_baseUrl/emails/$encodedMessageId/body';
      return ParallelDioRequest(
        method: 'GET',
        url: url,
        options: Options(responseType: ResponseType.stream),
        tag: email,
      );
    }).toList();

    // Execute all HTTP requests in parallel
    final httpStream = _dioClient.executeAll(requests);

    await for (final httpResult in httpStream) {
      final email = httpResult.tag as EmailMetadata;
      EmailIngestionResult result;

      if (!httpResult.isSuccess || httpResult.response == null) {
        result = EmailIngestionResult(
          messageId: email.messageId,
          httpSuccess: false,
          kvSuccess: false,
          dbSuccess: false,
          error: 'HTTP failed: ${httpResult.errorKind}',
        );
        yield result;
        continue;
      }

      // Pipe to KV store
      final response = httpResult.response!;
      final body = response.data;

      if (body is! ResponseBody) {
        result = EmailIngestionResult(
          messageId: email.messageId,
          httpSuccess: false,
          kvSuccess: false,
          dbSuccess: false,
          error: 'Invalid response body',
        );
        yield result;
        continue;
      }

      bool kvSuccess = false;
      try {
        await _kvStore.writeFromStream(
          email.messageId,
          body.stream,
          extension: 'eml',
        );
        kvSuccess = true;
      } catch (e) {
        result = EmailIngestionResult(
          messageId: email.messageId,
          httpSuccess: true,
          kvSuccess: false,
          dbSuccess: false,
          error: 'KV write failed: $e',
        );
        yield result;
        continue;
      }

      // Insert to database
      bool dbSuccess = false;
      try {
        await _dbHandle.db.insertEmail(
          messageId: email.messageId,
          fromAddr: email.fromAddr,
          toAddr: email.toAddr,
          subject: email.subject,
          receivedAt: email.receivedAt,
        );
        dbSuccess = true;
      } catch (e) {
        result = EmailIngestionResult(
          messageId: email.messageId,
          httpSuccess: true,
          kvSuccess: true,
          dbSuccess: false,
          error: 'DB insert failed: $e',
        );
        yield result;
        continue;
      }

      result = EmailIngestionResult(
        messageId: email.messageId,
        httpSuccess: true,
        kvSuccess: kvSuccess,
        dbSuccess: dbSuccess,
      );
      yield result;
    }
  }
}

/// Email metadata (from server, before ingestion)
class EmailMetadata {
  final String messageId;
  final String fromAddr;
  final String toAddr;
  final String subject;
  final DateTime receivedAt;

  EmailMetadata({
    required this.messageId,
    required this.fromAddr,
    required this.toAddr,
    required this.subject,
    required this.receivedAt,
  });

  factory EmailMetadata.fromJson(Map<String, dynamic> json) {
    return EmailMetadata(
      messageId: json['Message-ID'] as String,
      fromAddr: json['From'] as String,
      toAddr: json['To'] as String,
      subject: json['Subject'] as String,
      receivedAt: DateTime.parse(json['Received_at'] as String),
    );
  }
}

