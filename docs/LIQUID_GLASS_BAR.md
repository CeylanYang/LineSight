# Liquid glass navigation — 1.1.19

The four phone navigation destinations now use a floating glass bar inspired by
[wzhdgithub/LiquidGlassBar](https://github.com/wzhdgithub/LiquidGlassBar).
The owner selected a Flutter implementation because this application is Flutter,
whereas that repository provides a Jetpack Compose module. No Kotlin code or
AGSL shader from that GPL repository is copied or linked into this application.

## Implementation

- `lib/liquid_glass_bar.dart`: independently implemented pointer tracking,
  200 ms press enlargement (1.39×), horizontal drag, velocity prediction (0.22 s),
  spring settling and bounded 4 px overscroll, accessible buttons and RTL.
- Real backdrop blur (4 px), refraction, saturation, highlights and dispersion
  use `liquid_glass_renderer` **0.2.0-dev.4** (MIT, Tim Lehmann/whynotmake.it).
  This version supports the installed Flutter 3.44.4. The package's 1.x line
  requires a newer Flutter/Dart SDK and is intentionally not selected.
- The bar and selected capsule sample the content painted before them; the
  capsule is painted above the icon row so its lens samples the icons as well.
- `ImageFilter.isShaderFilterSupported` selects the renderer's frosted-glass
  fallback when shader filters are unavailable. Disabling the existing glass
  setting uses opaque surfaces without backdrop effects. Reduced motion removes
  press enlargement and settling animation. Keyboard and screen-reader selection
  use the same destination callback as pointer interaction.
- `AppShell` extends the scrolling content behind the floating bar. `PageBody`
  adds the Scaffold-provided bottom inset to its trailing padding, so the final
  row remains reachable. Wide layouts retain the existing navigation rail.
- Chinese/English labels, appearance, authentication and business data retain
  their existing state and behavior. No database schema or permission changes.

This is a Flutter adaptation, not the Compose library's exact renderer. It does
not add accelerometer-driven highlights. Real refraction needs a Flutter backend
that supports shader filters; the fallback preserves navigation and gestures.
Physical-device performance still requires testing on the target phone.

## Build and checks

The normal build initially failed to fetch Gradle artifacts because of TLS
handshake errors from plugins.gradle.org, Maven Central and dl.google.com.
The optional, explicitly supplied `tool/gradle_mirrors.init.gradle` redirects
those repositories to the same Aliyun mirrors already used by the Android
project, plus the Flutter download mirror, including Flutter's included Gradle build. It does not change global
Gradle settings or the Flutter SDK.

```powershell
$env:JAVA_HOME = 'C:/Program Files/Java/jdk-21'
$glassDefine = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('LINESIGHT_API_BASE_URL=https://47.111.81.94/api/v1/'))
flutter build apk --release --config-only --target-platform android-arm64,android-x64 --split-per-abi
android/gradlew.bat -p android -I ../tool/gradle_mirrors.init.gradle '-Ptarget-platform=android-arm64,android-x64' -Psplit-per-abi=true '-Ptarget=lib/main.dart' "-Pdart-defines=$glassDefine" assembleRelease
```

The built-in collaboration endpoint is retained from the accepted 1.1.18 APK.

Host validation: `flutter analyze` clean; all **93** host tests passed, including
four dedicated tests covering single selection, cancellation/multitouch, bounded
drag in both directions, reduced motion and unsupported-renderer fallback.
Existing navigation/layout tests now locate `LiquidGlassBar`.

`integration_test/liquid_glass_journey_test.dart` uses an in-memory workspace and
never opens the installed user database. It exercises all four destinations,
press, drag and captures light/dark screenshots. Device results and delivered
APK hashes are recorded alongside the release artifacts.

## Completed Android evidence

Both ARM64/x64 Release APKs and the UI-test Debug APK built successfully. The
Android API 36 journey passed (one scenario plus the runner teardown entry).
Six screenshots were visually reviewed: four Chinese destinations, held capsule,
and a separate dark-palette fixture. The existing production theme remains light.
Impeller/OpenGLES was observed, so this run exercised the real shader path.
Software-GPU emulator skipped-frame logs were retained; phone performance was
not measured. The renderer emits SkSL compatibility warnings during compilation;
its real shader path uses Impeller, with FakeGlass selected on unsupported backends.

The normal x64 release was then installed with `adb install -r` and launched
successfully. UID 10219 was retained; normal activity launch reported 5798 ms,
which is not a measure of usable-page latency. Installed package SHA-256 matched
the delivered x64 APK. The built-in service URL was verified in the ARM64 AOT
binary, and both the old 1.1.18 and new release certificates matched.

Delivery: `D:/ENT207/deliverables/LineSight-1.1.19/`.
Full APKs, reports, screenshots and artifact hashes:
`C:/Users/29668/LineSight-releases/1.1.19/`.
