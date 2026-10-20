import 'dart:convert';
import 'dart:ui' show FrameTiming;

/// Opt-in local diagnostics. Never include account or workspace content.
/// Enable only for a diagnostic build with LINESIGHT_STARTUP_TRACE=true.
const startupTraceEnabled = bool.fromEnvironment('LINESIGHT_STARTUP_TRACE');

class StartupTrace {
  final Stopwatch _watch = Stopwatch()..start();

  void mark(String event, {String? stage, bool? ready, bool? failed}) => _emit({
    'event': event,
    if (stage != null) 'stage': stage,
    if (ready != null) 'ready': ready,
    if (failed != null) 'failed': failed,
  });

  void frame(FrameTiming timing) => _emit({
    'event': 'frame-timing',
    'frameNumber': timing.frameNumber,
    'buildUs': timing.buildDuration.inMicroseconds,
    'rasterUs': timing.rasterDuration.inMicroseconds,
    'totalSpanUs': timing.totalSpan.inMicroseconds,
    'vsyncOverheadUs': timing.vsyncOverhead.inMicroseconds,
  });

  void _emit(Map<String, Object> fields) {
    if (!startupTraceEnabled) return;
    final payload = {
      ...fields,
      'elapsedUs': _watch.elapsedMicroseconds,
      'epochMs': DateTime.now().millisecondsSinceEpoch,
    };
    // ignore: avoid_print
    print('LINESIGHT_STARTUP ${jsonEncode(payload)}');
  }
}
