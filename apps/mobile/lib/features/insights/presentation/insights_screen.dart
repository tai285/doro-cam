import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/features/albums/presentation/albums_screens.dart';
import 'package:doro_cam/features/shared/remote_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final insightsProvider = FutureProvider.autoDispose<InsightsDto>(
  (ref) => ref.watch(remoteApiProvider).insights(),
);
final suggestionsProvider = FutureProvider.autoDispose<List<SuggestionDto>>(
  (ref) => ref.watch(remoteApiProvider).suggestions(),
);

/// Photography statistics and preset suggestions, calculated on the server from your own photos' settings
/// (ANL-*, PRE-*). Every claim shows the numbers behind it; nothing is applied unless you accept.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final suggestions = ref.watch(suggestionsProvider);
    final api = ref.read(remoteApiProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to settings',
          location: AppRoutes.settings,
        ),
        title: const Text('Insights'),
      ),
      body: insights.when(
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading insights'),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(friendlyRemoteError(e), key: const Key('remote-error')),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('remote-retry'),
                  onPressed: () => ref.invalidate(insightsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (data.total == 0)
                const Text(
                  'Take some photos and your habits will show up here.',
                  key: Key('insights-empty'),
                )
              else
                Text(
                  'Based on ${data.total} memories.',
                  key: const Key('insights-total'),
                ),
              if (data.findings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'What we noticed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final f in data.findings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• ${f.$2}', key: Key('finding-${f.$1}')),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Suggested presets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...suggestions.when(
                loading: () => const <Widget>[LinearProgressIndicator()],
                error: (e, _) => <Widget>[Text(friendlyRemoteError(e))],
                data: (items) => items.isEmpty
                    ? const <Widget>[
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No suggestions yet. When you often shoot with the same combination, we’ll offer it as a preset.',
                            key: Key('suggestions-empty'),
                          ),
                        ),
                      ]
                    : <Widget>[
                        for (final s in items)
                          Card(
                            key: Key('suggestion-${s.patternKey}'),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    s.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text(s.explanation),
                                  Text(
                                    'Based on ${s.supportingCount} of ${s.of} photos. Nothing changes unless you accept.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  Wrap(
                                    children: <Widget>[
                                      TextButton(
                                        key: Key('accept-${s.patternKey}'),
                                        onPressed: () async {
                                          await api.acceptSuggestion(
                                            s.patternKey,
                                          );
                                          ref.invalidate(suggestionsProvider);
                                        },
                                        child: const Text('Save as preset'),
                                      ),
                                      TextButton(
                                        key: Key('dismiss-${s.patternKey}'),
                                        onPressed: () async {
                                          await api.dismissSuggestion(
                                            s.patternKey,
                                          );
                                          ref.invalidate(suggestionsProvider);
                                        },
                                        child: const Text('Not now'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
              ),
              if (data.total > 0) ...<Widget>[
                const SizedBox(height: 16),
                for (final entry in data.distributions.entries)
                  if (entry.value.isNotEmpty)
                    _Distribution(title: entry.key, buckets: entry.value),
                if (data.trend.isNotEmpty) ...<Widget>[
                  Text(
                    'Over time',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final t in data.trend) Text('${t.$1}: ${t.$2} photos'),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bars for the eye and the numbers for everyone, so the data never depends on seeing the shapes.
class _Distribution extends StatelessWidget {
  const _Distribution({required this.title, required this.buckets});

  final String title;
  final List<BucketDto> buckets;

  @override
  Widget build(BuildContext context) {
    final max = buckets.fold<int>(1, (m, b) => b.count > m ? b.count : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        for (final b in buckets)
          Semantics(
            label:
                '${b.label}: ${b.count} photos, ${(b.share * 100).round()} percent',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: Text(b.label, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(value: b.count / max),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${b.count} · ${(b.share * 100).round()}%',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
