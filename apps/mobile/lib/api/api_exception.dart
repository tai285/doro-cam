// ignore_for_file: prefer_initializing_formals
import 'package:meta/meta.dart';

/// An error response from services/api in the documented envelope
/// `{ "error": { "code", "message", "requestId" } }` (docs/specs/api.md), or one of Better Auth's
/// `{ "code", "message" }` bodies.
@immutable
class ApiException implements Exception {
  const ApiException({required this.status, required this.code, required this.message, this.requestId, this.retryAfter});

  final int status;
  final String code;
  final String message;
  final String? requestId;

  /// From the `Retry-After` header on 429/503.
  final Duration? retryAfter;

  bool get isUnauthenticated => status == 401;
  bool get isRateLimited => status == 429;
  bool get isServerError => status >= 500;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// The request never got an answer: offline, DNS, TLS, connection reset, timeout. Always retryable.
@immutable
class NetworkException implements Exception {
  const NetworkException(this.cause);
  final Object cause;

  @override
  String toString() => 'NetworkException($cause)';
}
