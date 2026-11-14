import 'package:doro_cam/app/app.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/platform/bootstrap.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await bootstrap();
  runApp(
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        dataLayerProvider.overrideWithValue(runtime.data),
        tokenStoreProvider.overrideWithValue(runtime.tokens),
      ],
      child: const DoroCamApp(),
    ),
  );
}
