# Brand reveal — 1.1.20

The cold-start page ports the approved `LineSight_粒子聚合与触觉动效预览_v4_2.html`
to Flutter Canvas. Source SHA-256:
`300c6be3903afe68ddd80150753ad1d628ff5bdec0b0b1692dd4ff1117c1a173`.
The two diagonal reflection/glint stripes are omitted as requested. There is no
WebView, browser frame, replay button, demonstration vibration graph or fake OS UI.

## Visual and touch behavior

- The exact transparent 468 × 394 PNG and all 910 particle coordinates/seeds
  are imported by `tool/import_brand_reveal.py`. Generated constants are sorted
  once to match the reference draw order. No parsing/sorting/random generation
  occurs in the frame loop. `lib/brand_reveal.dart` reproduces easing, appearance,
  four corner anchors, orbiting ring, horizontal scan, solidification, pulse halo
  and the final solid mark against #3478F6. Narrow/landscape layouts also constrain
  the logo by height. Wordmark placement includes Android's navigation inset.
- 0–180 ms wake; 180–1050 ms adsorption; 1050–2200 ms scan/ring;
  2200–2560 ms lock; 2560–2800 ms finish. The wordmark enters at 2440 ms.
- Android's native launch surface uses the same blue, including Android 12+
  system splash. The OS splash icon is transparent so it does not flash a
  separate static logo immediately before the particle reveal.
- Native touch envelopes start at 70/470/840/1180/1460/1740/2010 ms with
  amplitudes 42/55/70/92/119/150/178 and 3 ms attack / 5 ms release.
  A separate system CLICK is scheduled at 2410 ms after the silent gap.
  Fixed-amplitude API 29+ motors use only three system ticks; older fixed-
  amplitude devices receive only the confirmation. The added VIBRATE permission
  is a normal permission and does not produce a runtime permission dialog.
- Saved app vibration preferences must be loaded before native effects begin.
  Only remaining cues are scheduled using the visual clock's elapsed position;
  elapsed cues are skipped. System touch-vibration preferences are respected.
  Backgrounding, errors, completion and disposal cancel pending effects.

## Real work during the reveal

`main()` starts `AppStore.init()` immediately after `runApp`; it does not wait
for any animation delay. Existing async SQLite opening/account reads, workspace
and preference reads, isolate validation and any required transactional migration
run while particles animate. Both themes are cached as before.

As soon as storage is ready, `AuthPage` (or the authenticated shell in embedded
use) is built and laid out offstage. Tickers, focus and semantics stay disabled
for the hidden screen. The same widget becomes visible after the reveal; it is
not built again from scratch on that transition. This preloads UI structure and
text layout, not a claim that every GPU shader in every screen is precompiled.

The gate needs **both** successful initialization and animation completion.
The production timeline waits for `waitUntilFirstFrameRasterized` and Android's
`onFlutterUiDisplayed` callback, so initial GPU/surface setup does not consume
the reveal while the native splash still covers it. On Android 12+, it also
waits until the system splash exit callback removes that cover.
Storage initialization and hidden login layout continue during this wait.
Slow initialization holds the final logo and shows/announces the real current
storage step. It never repeats the animation or invents loading percentages.
Storage failure immediately exposes the existing recovery page. Retry continues
using the existing database. Reduced motion skips the animation and brand
vibration, while real loading still completes normally. A resumed app continues
an unfinished reveal from its paused visual position and does not replay it
after completion. `showBrandReveal: true` is explicit at the production entry
point, so a database that finishes before the first widget mount cannot bypass
the cold-start reveal.

The existing collaboration feature keeps its HTTPS endpoint and manual login.
It stores no persistent cloud credentials, so this change does not fabricate an
authentication session or automatically redeem invitations. No database schema,
account format or cloud API changes are required.

## Verification

Host tests cover early/late storage completion, cold startup with already-ready
storage, hidden login prebuild, no reveal restart on notifications, saved vibration
off, reduced motion, lifecycle cancellation/resume, immediate error recovery,
live progress, and 320 px/landscape/tablet layouts with 1.5× text.

`integration_test/brand_reveal_journey_test.dart` uses a uniquely named temporary
SQLite database and in-memory visual fixtures, never the installed user's DB.
It verifies initialization/login, captures five deterministic Canvas phases,
and exercises the native channel. Screenshots and signed APK verification are
stored with `C:/Users/29668/LineSight-releases/1.1.20/`.

The HTML and Canvas share timing and source geometry; browser/Flutter text and
antialiasing can differ. Emulator screenshots cannot establish physical motor
feel or target-phone frame rate. Those require the intended phone.
