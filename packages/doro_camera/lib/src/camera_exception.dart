/// A failure reported by the native camera layer.
///
/// [code] is a stable identifier from docs/specs/camera.md (for example `permission_denied`).
/// Callers switch on the code; [message] is for logs and is not shown to users verbatim.
class CameraException implements Exception {
  const CameraException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? 'CameraException($code)' : 'CameraException($code, $message)';
}
