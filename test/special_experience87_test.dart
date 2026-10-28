import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:linesight_flutter/editions/special/special_activity.dart';
import 'package:linesight_flutter/editions/special/special_media.dart';
import 'package:linesight_flutter/editions/special/special_vip.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class MemoryVideo extends VideoPlayerPlatform {
  int next = 0;
  final positions = <int, Duration>{};
  final seeks = <Duration>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => ++next;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 30),
      size: const Size(1280, 720),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

class FailingExperienceStore extends AppStore {
  bool failWrites = true;
  @override
  Future<void> updateSpecialExperience(
    String actor,
    Map<String, dynamic> Function(Map<String, dynamic>) update,
  ) async {
    if (failWrites) throw StateError('storage unavailable');
    await super.updateSpecialExperience(actor, update);
  }
}

class FailOnceVideo extends MemoryVideo {
  bool fail = true;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (fail) {
      fail = false;
      return Stream.error(
        PlatformException(
          code: 'video_error',
          message: 'private decoder details',
        ),
      );
    }
    return super.videoEventsFor(playerId);
  }
}

class RewardWriteStore extends AppStore {
  bool fail = false;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<void> claimSpecialReward(String action, {int points = 20}) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('private database details');
    await super.claimSpecialReward(action, points: points);
  }
}

class DelayedExperienceStore extends AppStore {
  Completer<void>? gate;
  @override
  Future<void> updateSpecialExperience(
    String actor,
    Map<String, dynamic> Function(Map<String, dynamic>) update,
  ) async {
    await gate?.future;
    await super.updateSpecialExperience(actor, update);
  }
}

void main() {
  AppStore make() => AppStore()
    ..preferences = {'specialEdition': true, 'reduceMotion': true}
    ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
  Future<void> mount(
    WidgetTester t,
    AppStore s,
    String section, {
    String language = 'zh',
  }) async {
    await t.pumpWidget(
      AppScope(
        store: s,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: SpecialActivityPage(section: section),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('reader restores the new actor and ignores an old save receipt', (
    t,
  ) async {
    final s = DelayedExperienceStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await s.updateSpecialExperience(
      'local/u1',
      (_) => {'chapter': 2, 'readerFont': 22},
    );
    await s.updateSpecialExperience(
      'local/u2',
      (_) => {'chapter': 1, 'readerFont': 18},
    );
    await mount(t, s, 'books');
    expect(find.text('第三章 · 下班以后'), findsOneWidget);
    s.gate = Completer<void>();
    await t.tap(find.byTooltip('添加书签'));
    await t.pump();
    s.user = const LocalUser('u2', 'other', '小周', 'operator', true);
    s.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('第二章 · 交接班的纸飞机'), findsOneWidget);
    expect(find.text('第三章 · 下班以后'), findsNothing);
    expect(t.widget<Slider>(find.byType(Slider)).value, 18);
    s.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('书签已保存，下次继续读'), findsNothing);
    expect(s.specialExperienceFor('local/u1')['chapter'], 2);
    expect(s.specialExperienceFor('local/u2')['chapter'], 1);
    await t.tap(find.byTooltip('添加书签'));
    await t.pumpAndSettle();
    expect(find.text('书签已保存，下次继续读'), findsOneWidget);
    expect(s.specialExperienceFor('local/u2')['chapter'], 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('video switches actor and restores their own episode and seek', (
    t,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final video = MemoryVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    final s = make();
    addTearDown(s.dispose);
    await s.updateSpecialExperience(
      'local/u1',
      (_) => {
        'videoProgress': {'episode': 0, 'position': 8000},
      },
    );
    await s.updateSpecialExperience(
      'local/u2',
      (_) => {
        'videoProgress': {'episode': 3, 'position': 4000},
      },
    );
    await mount(t, s, 'video');
    expect(video.seeks.last, const Duration(seconds: 8));
    s.user = const LocalUser('u2', 'other', '小周', 'operator', true);
    s.notifyListeners();
    await t.pumpAndSettle();
    expect(video.seeks.last, const Duration(seconds: 4));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '第 4 集')).selected,
      isTrue,
    );
    expect(
      (s.specialExperienceFor('local/u1')['videoProgress'] as Map)['episode'],
      0,
    );
    expect(
      (s.specialExperienceFor('local/u2')['videoProgress'] as Map)['episode'],
      3,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('workout switches actor without copying elapsed time', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await s.updateSpecialExperience(
      'local/u1',
      (_) => {
        'runningDraft': {'seconds': 18, 'name': '慢跑'},
      },
    );
    await s.updateSpecialExperience(
      'local/u2',
      (_) => {
        'runningDraft': {'seconds': 44, 'name': '快走'},
      },
    );
    await mount(t, s, 'running');
    expect(find.text('00:18'), findsOneWidget);
    s.user = const LocalUser('u2', 'other', '小周', 'operator', true);
    s.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('00:44'), findsOneWidget);
    expect(find.text('00:18'), findsNothing);
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '快走')).selected,
      isTrue,
    );
    await t.tap(find.text('结束并保存'));
    await t.pumpAndSettle();
    expect(
      (s.specialExperienceFor('local/u2')['workouts'] as List)
          .single['seconds'],
      44,
    );
    expect(s.specialExperienceFor('local/u1')['workouts'], isNull);
    expect(
      (s.specialExperienceFor('local/u1')['runningDraft'] as Map)['seconds'],
      18,
    );
    expect(t.takeException(), isNull);
  });

  for (final field in ['选择取车日期', '选择还车日期']) {
    testWidgets('rental $field ignores confirmation after page is removed', (
      t,
    ) async {
      final s = make();
      addTearDown(s.dispose);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await t.pumpWidget(
        AppScope(
          store: s,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, __) => show
                  ? const SpecialActivityPage(section: 'rental')
                  : const Scaffold(body: Text('已返回')),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text(field));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      visible.value = false;
      await t.pumpAndSettle();
      expect(find.byType(SpecialPlanBody), findsNothing);
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('已返回'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  for (final (kind, englishName) in [
    ('finance', 'Flexible funds'),
    ('insurance', 'City commute'),
  ]) {
    testWidgets(
      '$kind saved plans survive language change and undo in English',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final s = make();
        addTearDown(s.dispose);
        await mount(t, s, kind);
        await t.ensureVisible(find.text('收藏这个方案'));
        await t.pumpAndSettle();
        await t.tap(find.text('收藏这个方案'));
        await t.pumpAndSettle();
        final canonical = Map<String, dynamic>.from(
          (s.specialExperienceFor('local/u1')['plans'] as List).single,
        );
        await mount(t, s, kind, language: 'en');
        expect(find.text(englishName), findsWidgets);
        await t.ensureVisible(find.text('Save this plan'));
        await t.pumpAndSettle();
        await t.tap(find.text('Save this plan'));
        await t.pumpAndSettle();
        expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
        expect(
          (s.specialExperienceFor('local/u1')['plans'] as List)
              .single['detail'],
          canonical['detail'],
        );
        await t.ensureVisible(find.byTooltip('Remove plan'));
        await t.pumpAndSettle();
        expect(find.text('My plans'), findsOneWidget);
        expect(
          find.textContaining(
            kind == 'finance' ? 'installments · ¥' : 'Budget ¥',
          ),
          findsOneWidget,
        );
        await t.tap(find.byTooltip('Remove plan'));
        await t.pumpAndSettle();
        expect(find.text('Plan removed'), findsOneWidget);
        expect((s.specialExperienceFor('local/u1')['plans'] as List), isEmpty);
        await t.tap(find.text('Undo'));
        await t.pumpAndSettle();
        expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final section in ['video', 'drama']) {
    testWidgets(
      'English $section restores bookmarks and keeps reward across languages',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final original = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = MemoryVideo();
        addTearDown(() => VideoPlayerPlatform.instance = original);
        final s = make();
        addTearDown(s.dispose);
        await s.updateSpecialExperience(
          'local/u1',
          (_) => {
            '${section}Progress': {'episode': 0, 'position': 4000},
          },
        );
        await mount(t, s, section, language: 'en');
        expect(find.text('Play'), findsOneWidget);
        expect(find.text("Episode 1 · The Bee's Busy Morning"), findsOneWidget);
        await t.ensureVisible(find.text('Claim 20 points'));
        await t.pumpAndSettle();
        await t.tap(find.text('Claim 20 points'));
        await t.pumpAndSettle();
        expect(s.specialPointsBalance, 2360);
        expect(find.text("Today's episode points claimed"), findsOneWidget);
        await t.tap(find.text('Bookmark episode'));
        await t.pumpAndSettle();
        expect(s.specialExperienceFor('local/u1')['${section}Episode'], 0);
        await t.ensureVisible(find.byTooltip('Next episode'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Next episode'));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(
          find.text("Episode 2 · The Butterfly's Afternoon"),
          findsOneWidget,
        );
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Open bookmarked episode 1'));
        await t.pumpAndSettle();
        await t.tap(find.text('Open bookmarked episode 1'));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(find.text("Episode 1 · The Bee's Busy Morning"), findsOneWidget);
        await mount(t, s, section);
        expect(find.text('本集今日积分已领'), findsOneWidget);
        expect(s.specialPointsBalance, 2360);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('English playback failure hides decoder details and retries', (
    t,
  ) async {
    final original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = FailOnceVideo();
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'video', language: 'en');
    expect(find.textContaining('private decoder'), findsNothing);
    await t.tap(find.text('Unable to prepare playback. Tap to retry.'));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(
      find.text('Unable to prepare playback. Tap to retry.'),
      findsNothing,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language stocks reject sub-minimum input and clear stale results',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final s = make();
        addTearDown(s.dispose);
        await mount(t, s, 'stocks', language: language);
        final calculate = find.text(
          language == 'en' ? 'Calculate sample return' : '计算样例收益',
        );
        await t.enterText(find.byType(TextField), '1000');
        await t.ensureVisible(calculate);
        await t.pumpAndSettle();
        await t.tap(calculate);
        await t.pumpAndSettle();
        final result = find.textContaining(
          language == 'en' ? 'Final value ¥' : '期末价值 ¥',
        );
        expect(result, findsOneWidget);
        expect(
          find.text(language == 'en' ? 'Month 0' : '第 0 月'),
          findsOneWidget,
        );
        await t.enterText(find.byType(TextField), '0.5');
        await t.pumpAndSettle();
        expect(result, findsNothing);
        await t.ensureVisible(calculate);
        await t.pumpAndSettle();
        await t.tap(calculate);
        await t.pumpAndSettle();
        expect(
          find.text(
            language == 'en'
                ? 'Enter an amount from 1 to 100000000.'
                : '请输入 1～100000000 的金额',
          ),
          findsOneWidget,
        );
        expect(result, findsNothing);
        await t.enterText(find.byType(TextField), '1');
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(find.byType(TextField)).decoration!.errorText,
          isNull,
        );
        await t.ensureVisible(calculate);
        await t.pumpAndSettle();
        await t.tap(calculate);
        await t.pumpAndSettle();
        expect(result, findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'leaving rewards center prevents its delayed promotion covering another service',
    (t) async {
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'hub', language: 'en');
      expect(find.text('Rewards center'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('special-service-finance')));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 1200));
      await t.pumpAndSettle();
      expect(find.text('Finance'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      Navigator.of(t.element(find.byType(SpecialPlanBody))).pop();
      await t.pumpAndSettle();
      expect(find.text('Rewards center'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'English rewards promotion opens its calculator and internal titles stay readable',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'hub', language: 'en');
      expect(find.text('Puzzle pieces'), findsOneWidget);
      expect(find.text('Short dramas'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1200));
      await t.pumpAndSettle();
      expect(find.text('Ad · Make today special'), findsOneWidget);
      await t.tap(find.text('Open calculator'));
      await t.pumpAndSettle();
      expect(find.text('Finance'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      await mount(t, s, 'ledger', language: 'en');
      expect(find.text('Points history'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await mount(t, s, 'invite', language: 'en');
      expect(find.text('Invite colleagues'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'English membership retries failed claim and does not downgrade',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = FailingExperienceStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true}
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(s.dispose);
      await mount(t, s, 'vip', language: 'en');
      await t.tap(find.widgetWithText(ChoiceChip, 'Diamond member'));
      await t.pumpAndSettle();
      final claim = find.byKey(const ValueKey('claim-special-vip'));
      await t.ensureVisible(claim);
      await t.pumpAndSettle();
      await t.tap(claim);
      await t.pumpAndSettle();
      expect(
        find.text('Unable to claim reward. Please retry.'),
        findsOneWidget,
      );
      expect(s.specialExperienceFor('local/u1')['vip'], isNull);
      s.failWrites = false;
      await t.tap(claim);
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['vip'], 1);
      expect(find.text('Current membership: Diamond member'), findsOneWidget);
      await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Platinum member'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Platinum member'));
      await t.pumpAndSettle();
      await t.ensureVisible(claim);
      await t.pumpAndSettle();
      await t.tap(claim);
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['vip'], 1);
      await t.ensureVisible(find.text('Daily member gifts'));
      await t.pumpAndSettle();
      await t.tap(find.text('Daily member gifts'));
      await t.pumpAndSettle();
      expect(find.text('Daily check-in rewards'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('English avatar badge opens the owned membership', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await s.updateSpecialExperience('local/u1', (_) => {'vip': 2});
    await t.pumpWidget(
      AppScope(
        store: s,
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Center(child: SpecialVipAvatar(child: CircleAvatar())),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Supreme member'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('special-vip-avatar-badge')));
    await t.pumpAndSettle();
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Current membership: Supreme member'), findsOneWidget);
    expect(
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Supreme member'))
          .selected,
      isTrue,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'English rental selects dates and deduplicates a canonical saved trip',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = make();
      addTearDown(s.dispose);
      final today = DateTime.now().toIso8601String().split('T').first;
      await s.updateSpecialExperience(
        'local/u1',
        (_) => {
          'plans': [
            {
              'kind': 'rental',
              'name': '经济型',
              'detail': '杭州 · $today · 1 天 · ¥129',
              'date': today,
            },
          ],
        },
      );
      await mount(t, s, 'rental', language: 'en');
      expect(find.text('Car rental'), findsOneWidget);
      expect(find.text('Hangzhou · $today · Days: 1 · ¥129'), findsOneWidget);
      for (final label in ['Select pickup date', 'Select return date']) {
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.text('Save trip plan'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save trip plan'));
      await t.pumpAndSettle();
      expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
      expect(
        (s.specialExperienceFor('local/u1')['plans'] as List).single['detail'],
        '杭州 · $today · 1 天 · ¥129',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'English workout clear and save failures preserve timer and history',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = FailingExperienceStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true}
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true)
        ..failWrites = false;
      addTearDown(s.dispose);
      await s.updateSpecialExperience(
        'local/u1',
        (_) => {
          'runningDraft': {'seconds': 18, 'name': '慢跑'},
          'workouts': [
            {'name': '自由跑', 'seconds': 11, 'date': '2026-01-01T09:00:00'},
          ],
        },
      );
      s.failWrites = true;
      await mount(t, s, 'running', language: 'en');
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Jogging'), findsOneWidget);
      expect(find.text('Free run · 11 sec'), findsOneWidget);
      await t.tap(find.text('Clear current timer'));
      await t.pumpAndSettle();
      expect(find.text('Saved workouts will be kept.'), findsOneWidget);
      await t.tap(find.text('Keep timer'));
      await t.pumpAndSettle();
      expect(find.text('00:18'), findsOneWidget);
      await t.tap(find.text('Finish and save'));
      await t.pumpAndSettle();
      expect(
        find.text('Save failed. Your elapsed time is retained. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('00:18'), findsOneWidget);
      await t.tap(find.text('Clear current timer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear timer'));
      await t.pumpAndSettle();
      expect(find.text('Unable to clear. Please retry.'), findsOneWidget);
      expect(find.text('00:18'), findsOneWidget);
      s.failWrites = false;
      await t.tap(find.text('Clear current timer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear timer'));
      await t.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);
      expect(s.specialExperienceFor('local/u1')['runningDraft'], isNull);
      expect(
        (s.specialExperienceFor('local/u1')['workouts'] as List).length,
        1,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'English health records water and returns from walking with value intact',
    (t) async {
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'health', language: 'en');
      expect(find.text('Health'), findsOneWidget);
      await t.tap(find.text('Drink water +200 ml'));
      await t.pumpAndSettle();
      expect(find.text('200 / 2000 ml'), findsOneWidget);
      await t.tap(find.text('Undo one glass'));
      await t.pumpAndSettle();
      expect(find.text('0 / 2000 ml'), findsOneWidget);
      await t.tap(find.text('Drink water +200 ml'));
      await t.pumpAndSettle();
      await t.tap(find.text('Take a relaxing walk'));
      await t.pumpAndSettle();
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
      Navigator.of(t.element(find.byType(SpecialExerciseBody))).pop();
      await t.pumpAndSettle();
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('200 / 2000 ml'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'English reader completes chapters and retains position when language changes',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'books', language: 'en');
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Small-Town Workdays'), findsOneWidget);
      expect(
        find.textContaining('At dawn, the workshop lights'),
        findsOneWidget,
      );
      expect(find.text('第一章 · 今天的第一束光'), findsNothing);
      await t.tap(find.text('Chapter 2'));
      await t.pumpAndSettle();
      expect(find.text('Chapter 2 · The Paper Plane'), findsOneWidget);
      expect(find.textContaining('A little paper plane'), findsOneWidget);
      await t.tap(find.byTooltip('Add bookmark'));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['chapter'], 1);
      final font = t.widget<Slider>(find.byType(Slider)).value;
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Next chapter'));
      await t.pumpAndSettle();
      await t.tap(find.text('Next chapter'));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['chapter'], 2);
      expect(find.text('Book complete'), findsOneWidget);
      await mount(t, s, 'books', language: 'zh');
      expect(find.text('第三章 · 下班以后'), findsOneWidget);
      expect(t.widget<Slider>(find.byType(Slider)).value, font);
      expect(find.text('全书读完啦'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'English puzzle preserves missing piece on save failure and retries',
    (t) async {
      final s = FailingExperienceStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true}
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(s.dispose);
      await mount(t, s, 'fragments', language: 'en');
      await t.tap(find.text('Collect\npiece 1'));
      await t.pumpAndSettle();
      expect(find.text('Piece was not saved. Please retry.'), findsOneWidget);
      expect(s.specialExperienceFor('local/u1')['pieces'], isNull);
      expect(find.text('Gift puzzle · 0/6 collected'), findsOneWidget);
      expect(t.takeException(), isNull);
      s.failWrites = false;
      await t.tap(find.text('Collect\npiece 1'));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['pieces'], [0]);
      expect(find.text('Gift puzzle · 1/6 collected'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '✓ Piece 1'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('redemption disables while pending and remains completed', (
    t,
  ) async {
    final s = RewardWriteStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..gate = Completer<void>();
    addTearDown(s.dispose);
    await mount(t, s, 'points');
    final gift = find.widgetWithText(OutlinedButton, '新人礼券 · 100 积分');
    await t.ensureVisible(gift);
    await t.pumpAndSettle();
    await t.tap(gift);
    await t.pump();
    expect(t.widget<OutlinedButton>(gift).onPressed, isNull);
    expect(s.calls, 1);
    s.gate!.complete();
    await t.pumpAndSettle();
    expect(s.specialPointsBalance, 2240);
    final done = find.widgetWithText(OutlinedButton, '新人礼券 · 今日已兑换');
    expect(t.widget<OutlinedButton>(done).onPressed, isNull);
    await t.pumpWidget(const SizedBox());
    await mount(t, s, 'points');
    await t.ensureVisible(done);
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(done).onPressed, isNull);
    expect((s.specialActivity['history'] as List).length, 1);
  });

  testWidgets('English rewards handle failure retry and low balance', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = RewardWriteStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..fail = true;
    addTearDown(s.dispose);
    await mount(t, s, 'points', language: 'en');
    expect(find.text('Daily check-in rewards'), findsOneWidget);
    final gift = find.widgetWithText(
      OutlinedButton,
      'Welcome voucher · 100 points',
    );
    await t.ensureVisible(gift);
    await t.pumpAndSettle();
    await t.tap(gift);
    await t.pumpAndSettle();
    expect(find.text('Redemption failed. Please retry.'), findsOneWidget);
    expect(find.textContaining('private database'), findsNothing);
    expect(s.specialPointsBalance, 2340);
    expect(t.widget<OutlinedButton>(gift).onPressed, isNotNull);
    s.fail = false;
    await t.tap(gift);
    await t.pumpAndSettle();
    expect(s.specialPointsBalance, 2240);
    await t.pumpWidget(const SizedBox());
    s.preferences = {
      'specialEdition': true,
      'reduceMotion': true,
      'specialActivity': {'points': 0},
    };
    await mount(t, s, 'points', language: 'en');
    await t.ensureVisible(gift);
    await t.pumpAndSettle();
    await t.tap(gift);
    await t.pumpAndSettle();
    expect(
      find.text('Not enough points. Complete daily activities to earn more.'),
      findsOneWidget,
    );
    expect(s.calls, 2);
    expect(s.specialPointsBalance, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'empty reward history has an action instead of reopening itself',
    (t) async {
      final s = make();
      addTearDown(s.dispose);
      await mount(t, s, 'ledger', language: 'en');
      expect(find.text('Reward and redemption history'), findsNothing);
      expect(
        find.text('No rewards yet. Check in to get started.'),
        findsOneWidget,
      );
      await t.tap(find.text('Check in'));
      await t.pumpAndSettle();
      await t.tap(find.text('Check in now'));
      await t.pumpAndSettle();
      Navigator.of(t.element(find.byType(SpecialRewardsBody).last)).pop();
      await t.pumpAndSettle();
      expect(find.text('Daily check-in'), findsOneWidget);
      expect(find.text('20 points'), findsOneWidget);
      expect(
        find.text('No rewards yet. Check in to get started.'),
        findsNothing,
      );
      expect(find.text('Reward and redemption history'), findsNothing);
    },
  );

  testWidgets(
    'English reader and water failures show actionable translated feedback',
    (t) async {
      final s = FailingExperienceStore()
        ..preferences = {'specialEdition': true, 'reduceMotion': true}
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(s.dispose);
      await mount(t, s, 'books', language: 'en');
      await t.tap(find.byTooltip('Add bookmark'));
      await t.pumpAndSettle();
      expect(
        find.text('Reading progress was not saved. Tap the bookmark to retry.'),
        findsOneWidget,
      );
      s.failWrites = false;
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byTooltip('Add bookmark'));
      await t.pumpAndSettle();
      expect(
        find.text('Bookmark saved. Continue reading next time.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      s.failWrites = true;
      await mount(t, s, 'health', language: 'en');
      await t.tap(find.text('Drink water +200 ml'));
      await t.pumpAndSettle();
      expect(
        find.text('Water intake was not saved. Please retry.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('reader reports failed bookmark and can retry', (t) async {
    final s = FailingExperienceStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await mount(t, s, 'books');
    await t.tap(find.byTooltip('添加书签'));
    await t.pumpAndSettle();
    expect(find.text('阅读进度未保存，请点书签重试'), findsOneWidget);
    expect(find.text('书签已保存，下次继续读'), findsNothing);
    expect(t.takeException(), isNull);
    s.failWrites = false;
    await t.pump(const Duration(seconds: 5));
    await t.tap(find.byTooltip('添加书签'));
    await t.pumpAndSettle();
    expect(find.text('书签已保存，下次继续读'), findsOneWidget);
    expect(s.specialExperienceFor('local/u1')['chapter'], 0);
  });

  testWidgets('water failure preserves value and retry supports undo', (
    t,
  ) async {
    final s = FailingExperienceStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await mount(t, s, 'health');
    await t.tap(find.text('喝一杯水 +200ml'));
    await t.pumpAndSettle();
    expect(find.text('饮水记录未保存，请重试'), findsOneWidget);
    expect(find.text('0 / 2000 ml'), findsOneWidget);
    expect(t.takeException(), isNull);
    s.failWrites = false;
    await t.tap(find.text('喝一杯水 +200ml'));
    await t.pumpAndSettle();
    expect(find.text('200 / 2000 ml'), findsOneWidget);
    await t.tap(find.text('撤销一杯'));
    await t.pumpAndSettle();
    expect(find.text('0 / 2000 ml'), findsOneWidget);
  });

  testWidgets('daily reward shows claimed status and cannot credit twice', (
    t,
  ) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'coins');
    await t.tap(find.text('立即签到'));
    await t.pumpAndSettle();
    expect(s.specialPointsBalance, 2360);
    expect(find.text('今日已签到'), findsOneWidget);
    final b = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, '今日已签到'),
    );
    expect(b.onPressed, isNull);
    await t.pumpWidget(const SizedBox());
    await mount(t, s, 'coins');
    expect(find.text('今日已签到'), findsOneWidget);
    expect(s.specialPointsBalance, 2360);
  });
  testWidgets('same plan saves once; removal can be undone', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'finance');
    for (var i = 0; i < 2; i++) {
      await t.ensureVisible(find.text('收藏这个方案'));
      await t.pumpAndSettle();
      await t.tap(find.text('收藏这个方案'));
      await t.pumpAndSettle();
    }
    expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
    await t.ensureVisible(find.byTooltip('移除方案'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('移除方案'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['plans'], isEmpty);
    expect(find.text('还没有收藏，选好上面的方案再保存吧'), findsOneWidget);
    await t.tap(find.text('撤销'));
    await t.pumpAndSettle();
    expect((s.specialExperienceFor('local/u1')['plans'] as List).length, 1);
  });
  testWidgets('plan undo cannot restore another account after switching', (
    t,
  ) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'finance');
    await t.ensureVisible(find.text('收藏这个方案'));
    await t.tap(find.text('收藏这个方案'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byTooltip('移除方案'));
    await t.tap(find.byTooltip('移除方案'));
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['plans'], isEmpty);
    final undo = t
        .widget<SnackBarAction>(find.byType(SnackBarAction))
        .onPressed;
    s.user = const LocalUser('u2', 'other', 'Other', 'operator', true);
    s.notifyListeners();
    await t.pumpAndSettle();
    undo();
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['plans'], isEmpty);
    expect(s.specialExperienceFor('local/u2')['plans'] ?? [], isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('pending video bookmark keeps clicked episode while switching', (
    t,
  ) async {
    final original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = MemoryVideo();
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final s = DelayedExperienceStore()
      ..preferences = {'specialEdition': true, 'reduceMotion': true}
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await mount(t, s, 'video');
    s.gate = Completer<void>();
    await t.ensureVisible(find.text('收藏本集'));
    await t.pumpAndSettle();
    await t.tap(find.text('收藏本集'));
    await t.pump();
    expect(
      t
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '收藏本集'))
          .onPressed,
      isNull,
    );
    await t.tap(find.byTooltip('下一集'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('第 2 集 ·'), findsOneWidget);
    s.gate!.complete();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(s.specialExperienceFor('local/u1')['videoEpisode'], 0);
    expect(find.text('已收藏，第 1 集等你回来'), findsOneWidget);
    expect(find.text('打开收藏第 1 集'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '收藏本集'))
          .onPressed,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'video bookmark failure preserves old favorite and permits retry',
    (t) async {
      final original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = MemoryVideo();
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final s = FailingExperienceStore()
        ..preferences = {
          'specialEdition': true,
          'reduceMotion': true,
          'specialExperiences': {
            'local/u1': {'videoEpisode': 4},
          },
        }
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(s.dispose);
      await mount(t, s, 'video');
      await t.ensureVisible(find.text('收藏本集'));
      await t.pumpAndSettle();
      await t.tap(find.text('收藏本集'));
      await t.pumpAndSettle();
      expect(find.text('收藏失败，请重试'), findsOneWidget);
      expect(s.specialExperienceFor('local/u1')['videoEpisode'], 4);
      s.failWrites = false;
      await t.ensureVisible(find.text('收藏本集'));
      await t.pumpAndSettle();
      await t.tap(find.text('收藏本集'));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['videoEpisode'], 0);
      expect(find.text('打开收藏第 1 集'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('video restores episode and seek position without autoplay', (
    t,
  ) async {
    final original = VideoPlayerPlatform.instance;
    final video = MemoryVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final s = make();
    addTearDown(s.dispose);
    await s.updateSpecialExperience(
      'local/u1',
      (state) => {
        'videoProgress': {'episode': 3, 'position': 8000},
      },
    );
    await mount(t, s, 'video');
    expect(find.byType(SpecialMediaBody), findsOneWidget);
    expect(video.seeks, contains(const Duration(seconds: 8)));
    expect(find.textContaining('第 4 集 ·'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(
      (s.specialExperienceFor('local/u1')['videoProgress'] as Map)['position'],
      8000,
    );
  });
  testWidgets(
    'paused workout restores, finishes once and unlocks daily reward',
    (t) async {
      final s = make();
      addTearDown(s.dispose);
      await s.updateSpecialExperience(
        'local/u1',
        (state) => {
          'runningDraft': {'seconds': 18, 'name': '慢跑'},
        },
      );
      await mount(t, s, 'running');
      expect(find.text('00:18'), findsOneWidget);
      expect(find.text('上次的运动已暂停，可以继续'), findsOneWidget);
      await t.tap(find.text('结束并保存'));
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['runningDraft'], isNull);
      expect(
        (s.specialExperienceFor('local/u1')['workouts'] as List)
            .single['seconds'],
        18,
      );
      await t.tap(find.text('领取今日运动 20 积分'));
      await t.pumpAndSettle();
      expect(s.specialPointsBalance, 2360);
      expect(find.text('今日运动积分已领取'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(s.specialExperienceFor('local/u1')['runningDraft'], isNull);
    },
  );
  testWidgets('reading task has a real, daily-deduplicated reward', (t) async {
    final s = make();
    addTearDown(s.dispose);
    await mount(t, s, 'books');
    await t.ensureVisible(find.text('读完本章，领取 20 积分'));
    await t.pumpAndSettle();
    await t.tap(find.text('读完本章，领取 20 积分'));
    await t.pumpAndSettle();
    expect(s.specialPointsBalance, 2360);
    expect(find.text('本章今日积分已领取'), findsOneWidget);
  });
}
