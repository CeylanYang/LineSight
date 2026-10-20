# Startup measurements — 1.1.7

## Method

Device: disposable Android emulator `emulator-5554`, Android API 36.1. Flutter integration tests use **debug mode**. Each scenario is opened three times with a new AppStore and reopened SQLite connection. The timer includes opening SQLite, reading accounts/state, integrity checking, decoding/validation and readiness. It excludes Flutter process launch, installation, fixture generation, fixture writes and result assertions. Existing OS/database caches are not flushed.

A periodic 16 ms timer records the longest main-isolate heartbeat gap in each run. This identifies long scheduling gaps but is **not a frame-time measurement**. The table shows the median of each run's longest gap. Small samples and shared-emulator scheduling are insufficient for statistical or physical-device guarantees.

Baseline: 1.1.6 startup code. Updated: 1.1.7 worker decoding. Both use the same test and fixture generator. Exact workspace byte counts match: 47,623 bytes (small) and 22,700,202 bytes (large). The undo scenario also stores a second complete copy without metadata, exercising legacy point-summary generation. No timestamps require migration.

## Observations

| Scenario | Baseline startup median | Updated median | Change | Baseline gap median | Updated gap median |
|---|---:|---:|---:|---:|---:|
| Small workspace | 545 ms | 228 ms | −58% | 136 ms | 37 ms |
| 22.7 MB workspace | 2,886 ms | 2,574 ms | −11% | 501 ms | 211 ms |
| 22.7 MB workspace + equal undo point | 5,311 ms | 4,078 ms | −23% | 745 ms | 228 ms |

The first small baseline run was much slower than later runs (1,821 / 173 / 545 ms), so its apparent improvement is especially sensitive to startup warmup and should not be generalized.

The test verifies the full loaded model, restore-point summary, preferences, receipt, locked session and empty time archives. A SQLite trigger rejects any attempted state insertion during canonical startup. Stored workspace text is read back and compared exactly afterward. Both baseline and updated tests passed.

## Implementation and remaining costs

`lib/local_state.dart` decodes each JSON document once, validates the workspace and complete undo point, and returns the working model plus metadata. Canonical startup creates no replacement JSON strings or migration writes. `AppStore.init` invokes it through `compute`; only a required legacy migration reaches the atomic preservation/write transaction. The loaded model is published after success.

SQLite reads and chunk hashing still run through the existing storage path. Large-model memory, worker setup/transfer, legacy writes and whole-workspace business transactions still contribute to latency. This change does not establish a maximum usable device capacity or optimize every transaction.

## Reproduce and inspect

Run `flutter test integration_test/startup_profile_test.dart -d emulator-5554 --dart-define=PROFILE_LABEL=worker` on a disposable emulator. `tool/summarize_startup.py` summarizes the retained baseline/worker logs into JSON. The script reads `build/startup-baseline.log` and `build/startup-worker.log`.

The release `reports/` contains both original logs, `startup-comparison.json`, the baseline manifest and the original `store-baseline.dart.txt`. Normal release cold-launch measurements are separate checks and must not be mixed with these database-startup observations.

