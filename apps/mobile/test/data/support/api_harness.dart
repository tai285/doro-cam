import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Starts the REAL services/api (real Postgres and Garage S3 from `pnpm infra:up`) for integration
/// tests, through apps/mobile/tool/test_api_server.ts. Needs Docker's Postgres and Garage running
/// and Node 24; run the tests inside WSL (see CLAUDE.md).
class ApiHarness {
  ApiHarness._(this._process, this.baseUrl);

  final Process _process;
  final Uri baseUrl;
  int _users = 0;

  static Future<ApiHarness> start({int? quotaBytes}) async {
    final root = Directory.current.parent.parent; // apps/mobile -> repo root
    final port = await _freePort();
    final process = await Process.start(
      'node',
      ['../../apps/mobile/tool/test_api_server.ts'],
      workingDirectory: '${root.path}/services/api',
      environment: {'PORT': '$port', if (quotaBytes != null) 'STORAGE_QUOTA_BYTES': '$quotaBytes'},
    );
    final ready = Completer<void>();
    final log = StringBuffer();
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      log.writeln(line);
      if (line.startsWith('READY') && !ready.isCompleted) {
        ready.complete();
      }
    });
    process.stderr.transform(utf8.decoder).listen(log.write);
    unawaited(process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('The test API server exited with $code:\n$log'));
      }
    }));
    await ready.future.timeout(const Duration(seconds: 90), onTimeout: () {
      process.kill();
      throw StateError('The test API server did not start in time:\n$log');
    });
    return ApiHarness._(process, Uri.parse('http://127.0.0.1:$port'));
  }

  /// Creates an account whose email is verified, returning its credentials.
  Future<({String email, String password})> createUser({String? name}) async {
    final n = _users++;
    final email = 'mobile-$n-${DateTime.now().microsecondsSinceEpoch}@example.test';
    const password = 'correct-horse-battery';
    final response = await http.post(
      baseUrl.replace(path: '/__test/users'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'name': name ?? 'Mobile Tester', 'password': password}),
    );
    if (response.statusCode != 200) {
      throw StateError('Could not create a test user: ${response.statusCode} ${response.body}');
    }
    return (email: email, password: password);
  }

  Future<void> stop() async {
    _process.kill(ProcessSignal.sigterm);
    await _process.exitCode.timeout(const Duration(seconds: 15), onTimeout: () {
      _process.kill(ProcessSignal.sigkill);
      return -1;
    });
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}

/// Wraps a real HTTP client and breaks storage requests on a schedule, to simulate flaky networks.
class FaultyClient extends http.BaseClient {
  FaultyClient(this._inner, {this.storagePort = 9000});

  final http.Client _inner;
  final int storagePort;

  /// 1-based storage request numbers that fail before reaching the server.
  final Set<int> dropBefore = {};

  /// 1-based storage request numbers that reach the server but whose response is lost.
  final Set<int> dropAfter = {};
  int storageRequests = 0;
  int dropped = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.port != storagePort) {
      return _inner.send(request);
    }
    final n = ++storageRequests;
    if (dropBefore.contains(n)) {
      dropped++;
      throw const SocketException('connection refused (simulated)');
    }
    final response = await _inner.send(request);
    if (dropAfter.contains(n)) {
      dropped++;
      await response.stream.drain<void>();
      throw const SocketException('connection reset by peer (simulated)');
    }
    return response;
  }
}
