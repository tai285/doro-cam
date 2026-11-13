// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:doro_cam/api/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The storage server's answer to one PUT.
@immutable
class PutResult {
  const PutResult({required this.statusCode, this.etag, this.body = ''});
  final int statusCode;

  /// The `ETag` header of a successful part upload, stored per part so it can resume (SYNC-003).
  final String? etag;
  final String body;

  bool get ok => statusCode >= 200 && statusCode < 300;

  /// Providers disagree on how an expired presigned URL is rejected: S3 answers 403, Garage 400
  /// (docs/specs/upload-sync.md "Transfer"). Both mean "re-presign and retry once".
  bool get looksLikeExpiredUrl => statusCode == 400 || statusCode == 403;
}

/// Sends bytes straight to object storage through presigned URLs (ADR-0008). Never carries the API
/// bearer token: presigned URLs are self-authorizing and must not leak credentials.
class StorageUploader {
  StorageUploader(this._http, {this.timeout = const Duration(minutes: 5)});

  final http.Client _http;
  final Duration timeout;

  /// PUTs bytes `[offset, offset + length)` of [file] to [url].
  Future<PutResult> putRange(Uri url, File file, {required int offset, required int length, Map<String, String> headers = const {}}) async {
    final handle = await file.open();
    List<int> bytes;
    try {
      await handle.setPosition(offset);
      bytes = await handle.read(length);
    } finally {
      await handle.close();
    }
    if (bytes.length != length) {
      throw FileSystemException('The file is shorter than expected', file.path);
    }
    final request = http.Request('PUT', url)
      ..headers.addAll(headers)
      ..bodyBytes = bytes;
    try {
      final response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
      return PutResult(statusCode: response.statusCode, etag: response.headers['etag'], body: response.body);
    } on Object catch (error) {
      if (error is SocketException || error is http.ClientException || error is TimeoutException || error is HandshakeException || error is TlsException) {
        throw NetworkException(error);
      }
      rethrow;
    }
  }
}
