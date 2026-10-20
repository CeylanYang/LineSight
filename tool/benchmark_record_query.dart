import 'dart:convert';
import 'dart:io';

import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_query.dart';
import '../test_support/csv_fixtures.dart';

// Desktop Dart microbenchmark: no Flutter frames, Android or file I/O timing.
// Run: dart run tool/benchmark_record_query.dart
typedef QueryOutput = ({List<Inspection> records, Set<String> ids});

void main() {
  final workspace = csvFixture();
  const samples = 60;
  final cases = <Map<String, Object?>>[];
  for (final query in ['', '质', 'NO-MATCH', 'CSV-000001 csv-1']) {
    QueryOutput original() {
      final normalized = query.toLowerCase();
      final records =
          workspace.inspections
              .where(
                (r) =>
                    !r.archived &&
                    (normalized.isEmpty ||
                        '${r.serial} ${r.id} ${r.defect} ${r.recipeName} ${r.note} ${r.operatorName}'
                            .toLowerCase()
                            .contains(normalized)),
              )
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
      return (records: records, ids: records.map((r) => r.id).toSet());
    }

    final cache = RecordQueryCache();
    var revision = 0;
    QueryOutput cached() {
      final result = cache.resolve(
        workspace: workspace,
        revision: revision,
        session: 0,
        query: query,
      );
      return (records: result.records, ids: result.ids);
    }

    final expected = original().records.map((r) => r.id).toList();
    void verify(QueryOutput result) {
      if (result.records.length != expected.length ||
          result.ids.length != expected.length) {
        throw StateError('Count mismatch');
      }
      for (var i = 0; i < expected.length; i++) {
        if (result.records[i].id != expected[i] ||
            !result.ids.contains(expected[i])) {
          throw StateError('Order or ID mismatch');
        }
      }
    }

    for (var i = 0; i < 15; i++) {
      verify(original());
      revision++;
      verify(cached());
      verify(cached());
    }
    final baseline = <int>[], hits = <int>[], misses = <int>[];
    void measure(List<int> timings, QueryOutput Function() work) {
      final watch = Stopwatch()..start();
      final result = work();
      watch.stop();
      timings.add(watch.elapsedMicroseconds);
      verify(result);
    }

    void miss() {
      revision++;
      measure(misses, cached);
    }

    for (var i = 0; i < samples; i++) {
      // Alternate order to reduce systematic warm-up/order bias.
      if (i.isEven) {
        measure(baseline, original);
        miss();
        measure(hits, cached);
      } else {
        measure(hits, cached);
        miss();
        measure(baseline, original);
      }
    }
    Map<String, num> summary(List<int> values) {
      final sorted = values.toList()..sort();
      return {
        'median_us': (sorted[29] + sorted[30]) / 2,
        'p95_us': sorted[56],
        'min_us': sorted.first,
        'max_us': sorted.last,
      };
    }

    cases.add({
      'query': query,
      'matches': expected.length,
      'original_filter_sort_ids': summary(baseline),
      'cache_hit': summary(hits),
      'cache_miss_revision_changed': summary(misses),
      'all_sample_ids_and_order_verified': true,
    });
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'scope':
          'Windows desktop Dart JIT query work only; not Android UI latency',
      'utc': DateTime.now().toUtc().toIso8601String(),
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'records': workspace.inspections.length,
      'note_characters_per_record': 2000,
      'samples_per_case_and_path': samples,
      'warmups_per_case': 15,
      'cases': cases,
      'limits': [
        'Stopwatch microsecond resolution; zero does not mean zero work.',
        'Heap and frame times were not measured.',
        'Changed searches and data still scan synchronously.',
        'Fixture notes share a string; this is not a heap-retention benchmark.',
      ],
    }),
  );
}
