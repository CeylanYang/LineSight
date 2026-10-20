# Post-1.1.8 launch investigation

The accepted 1.1.8 packages and reports are immutable in `C:/Users/29668/LineSight-releases/1.1.8`. Current diagnostic changes are not a new packaged release.

## Reproduction with the accepted binary

On disposable Android emulator `emulator-5554`, the unmodified x64 1.1.8 APK was reinstalled with `adb install -r`, retaining app data. Logcat ran across installation and two force-stop/cold starts. No database reset or cache deletion was performed.

The first `am start -W` timed out (`WaitTime: 15,122 ms`). Android later reported Displayed/Fully drawn at **15,951 ms**. The second cold start passed at **7,266 ms**. The log shows package replacement work and slow dispatches in several system processes, followed by app-process initialization and rendering. This reproduces the observation; it does not identify a single cause.

Raw evidence: `build/launch-investigation/reinstall-*`. The first recorded host-memory snapshot reported about 2.0 GiB free out of 15.3 GiB visible RAM. Host/emulator scheduling, caches and package replacement activity are uncontrolled variables.

## Opt-in Dart timing

`LINESIGHT_STARTUP_TRACE=true` records fixed event names, elapsed microseconds, device epoch milliseconds, startup stage and ready/error booleans. It records no account, credential or business content. Normal builds leave this compile-time flag off. The diagnostic APK uses the normal `lib/main.dart` entrypoint and release AOT, with Android build name `1.1.8-diag`; it is separate from the accepted installable packages.

`tool/observe_android_launch.py` optionally reinstalls an APK without clearing app data, captures each cold-start result, continues recording after a timeout, and saves Android milestones, Dart timing events and screenshots. A late frame never changes a timeout into a passed wait. Output directories must be new, preserving previous observations. `--settle-seconds` can separate package replacement from launching.

The first diagnostic run, immediately after installation:

| Run | Store ready after Dart main | First frame rasterized after Dart main | Android Displayed | Cold wait |
|---|---:|---:|---:|---|
| 1 | 6,567 ms | 14,352 ms | 28,919 ms | Timeout |
| 2 | 2,318 ms | 6,030 ms | 10,686 ms | Passed |
| 3 | 2,324 ms | 5,233 ms | 8,743 ms | Passed |

The store-ready values include native plugin/SQLite opening and main-isolate scheduling; they are not isolated database CPU times. First-rasterized values reflect completion notification after rendering. App-process creation and engine initialization precede Dart main. The gap after store readiness establishes that database loading alone does not explain the launch delay. These small, variable samples do not establish an app regression or a physical-device performance guarantee.

Evidence: `build/launch-investigation/trace-immediate/observations.json` and full logs/images. `trace-inputs.json` records the exact diagnostic APK/input hashes; the corresponding main/store/trace sources were saved beside it.

The same diagnostic APK was then reinstalled, followed by a 20-second wait before launching. Both waits passed; Android Displayed values were **6,498 / 8,308 ms**. Store-ready callbacks were 1,218 / 2,055 ms after Dart main; first-rasterized callbacks were 5,323 / 5,166 ms. The first raster callback actually arrived after Android's Displayed event, illustrating why callback arrival must not be treated as the exact physical presentation time. These observations suggest installation/system activity contributes to the delay, but the small, uncontrolled sample does not establish causality. No source change was used for this comparison. Raw evidence: `trace-settled/`.

## Current source work

The app previously recreated both fixed themes on every store notification. The current source caches them for the lifetime of `LineSightApp`, while theme mode still follows preferences and navigator state still resets with the session. The new regression test passed identity reuse, visible startup stages, dark mode and session changes. **All 57 host tests passed; static analysis found no issues.** This removes repeated work; it has not been established as the cause or fix of the first-install timeout.

The second diagnostic build recorded Flutter `FrameTiming` for the first three reported frames: build, raster, total span and vsync-overhead durations. Exactly three frame records were checked for each of its three runs, verifying removal of the timing listener. All three runs reached store-ready and Android Displayed. Two `am` waits timed out and remain failures; the third passed. Actual early raster durations were substantial:

| Run | First reported frame number | Build | Raster | Store-ready callback |
|---|---:|---:|---:|---:|
| 1 | 2 | 4.6 ms | 7,407 ms | 2,698 ms |
| 2 | 2 | 4.8 ms | 5,988 ms | 2,021 ms |
| 3 | 2 | 9.5 ms | 3,604 ms | 1,871 ms |

The renderer was Impeller/OpenGLES on the emulator. Raster durations can include scheduling and driver costs; these values do not isolate GPU execution or establish that a particular widget is responsible. Source/binary hashes are in `theme-trace-inputs.json`; observations and screenshots in `theme-frames/`; checked frame records in `theme-frame-summary.json`.

## Withdrawn startup-tint experiment

A third diagnostic build removed the startup panel's backdrop-filter pass while retaining tint and border. All 57 host tests and static analysis passed, and all three `am` waits passed (Android Displayed 11,846 / 6,301 / 8,278 ms). The first reported frame's raster durations were 1,928 / 1,534 / 2,066 ms.

However, this did **not** prove usable startup. The third run's initial screenshot still showed loading after the store-ready callback. The same process was observed further without restarting. Its later frame 96 took **16,393 ms in raster**, with frame records delivered about 20,243 ms after Dart main. The later screenshot finally showed onboarding; the crash buffer was empty. Initial captures also ended before all three frame callbacks arrived in runs 2 and 3, so those short capture windows cannot support a claim about complete startup.

The startup blur removal was therefore **withdrawn**. `lib/ui.dart`, `lib/screens/startup.dart` and `test/startup_layout_test.dart` were restored byte-exactly from the accepted 1.1.8 source ZIP. Theme-cache/frame-trace inputs still match their earlier recorded hashes. Evidence: `tint-withdrawal-proof.json`, `tint-frames/late-flutter.txt`, `after-3-late.png`, `tint-frame-summary.json`. All experimental binaries, sources and original observations remain available. The current retained source is the theme-cache/opt-in-trace version that passed `host-theme-cache.log` (57 tests) and `analyze-theme-cache.log`.

A renderer comparison used the same withdrawn diagnostic binary with the per-launch `enable-impeller=false` intent supported by the local Flutter tooling. Flutter explicitly logged its deprecated Impeller opt-out notice, confirming the request was applied. Both waits passed (Displayed **7,673 / 5,933 ms**), and the final screenshot showed onboarding. The first reported raster durations were still **2,584 / 2,545 ms**; later reported frames took **2,210 / 2,578 ms** in raster. Both runs supplied three frame records and reached store-ready without error. Evidence: `tint-skia/`.

This small comparison does not establish a production backend choice or isolate the underlying driver/scheduling cause. No production renderer configuration was changed. Theme reuse is retained as a verified removal of repeated work; the rendering experiment remains withdrawn.

The accepted 1.1.8 APK was restored. Its SHA-256 matches the release manifest; the cold wait passed (Android Displayed **7,778 ms**), the screenshot visibly shows complete 1.1.8 onboarding, the default Impeller/OpenGLES backend was logged, and no diagnostic startup events appeared. Evidence: `restored-release/` and `final-state-verification.json`. The only retained runtime-source differences from the accepted ZIP are `lib/main.dart` and the new `lib/startup_trace.dart`; the current source remains unpackaged.

Persistent evidence archive: `C:/Users/29668/LineSight-investigations/startup-20261014/`. It includes the original raw observations, unsuccessful waits, withdrawn diagnostic binaries/sources, retained source overlay and file hashes. Accepted 1.1.8 release artifacts were not changed.

Next: continue record-search/UI work without equating a displayed loading frame with a usable account page. First-install latency remains unresolved and should be rechecked on physical hardware before making platform-wide rendering changes. Preserve original timeout evidence and keep the broader app-development goal active. These source changes are not a new installable release.
