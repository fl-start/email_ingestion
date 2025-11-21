import 'dart:async';
import 'package:hashed_kv_store/hashed_kv_store.dart';
import 'package:parallel_dio_pool/parallel_dio_pool.dart';

/// Adapter that makes MultiIsolateKvStoreClient compatible with
/// the pipeline's KvStoreClient interface.
class KvStoreAdapter implements KvStoreClient {
  final MultiIsolateKvStoreClient _kvStore;

  KvStoreAdapter(this._kvStore);

  @override
  Future<KvWriteResult> writeFromStream(
    String key,
    Stream<List<int>> data, {
    String extension = 'bin',
    bool truncateExisting = true,
  }) async {
    // Track bytes written while streaming
    int bytesWritten = 0;
    final trackedStream = data.map((chunk) {
      bytesWritten += chunk.length;
      return chunk;
    });

    await _kvStore.writeFromStream(
      key,
      trackedStream,
      extension: extension,
      truncateExisting: truncateExisting,
    );

    return KvWriteResult(
      key: key,
      extension: extension,
      bytesWritten: bytesWritten,
    );
  }
}

