import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/shared/theme/tier_tokens.dart';
import 'package:uniflex/shared/widgets/avatar/app_avatar.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/widgets/buttons/app_icon_button.dart';
import 'package:uniflex/shared/widgets/buttons/primary_button.dart';
import 'package:uniflex/shared/widgets/cards/app_card.dart';
import 'package:uniflex/shared/widgets/lists/app_list_group.dart';
import 'package:uniflex/shared/widgets/navigation/app_glass_nav_bar.dart';
import 'package:uniflex/shared/widgets/notice/app_inline_notice.dart';
import 'package:uniflex/shared/widgets/sheets/app_sheet.dart';
import 'package:uniflex/shared/widgets/status/app_status_label.dart';
import 'package:uniflex/shared/widgets/tabs/app_segmented_tabs.dart';
import 'package:uniflex/shared/widgets/tier/tier_header.dart';

import 'ui_harness.dart';

void main() {
  group('AppButton', () {
    forEachVariant('every variant renders without overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        Column(
          children: [
            for (final v in AppButtonVariant.values) ...[
              AppButton(
                  label: 'Place order ${v.name}', onPressed: () {}, variant: v),
              const SizedBox(height: 8),
              AppButton(
                label: 'A rather long label that must not overflow ${v.name}',
                onPressed: () {},
                variant: v,
                size: AppButtonSize.small,
                icon: AppIcons.add,
              ),
              const SizedBox(height: 8),
            ],
            const AppButton(label: 'Disabled', onPressed: null),
            const SizedBox(height: 8),
            AppButton(label: 'Loading', onPressed: () {}, isLoading: true),
          ],
        ),
        dark: dark,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium is 52 high, small is 40 high', (tester) async {
      await pumpUi(
        tester,
        Column(children: [
          AppButton(label: 'M', onPressed: () {}),
          const SizedBox(height: 8),
          AppButton(label: 'S', onPressed: () {}, size: AppButtonSize.small),
        ]),
      );
      expect(tester.getSize(find.byType(AppButton).first).height, 52);
      expect(tester.getSize(find.byType(AppButton).last).height, 40);
    });

    testWidgets('a double tap fires once (sync callback)', (tester) async {
      var fired = 0;
      await pumpUi(tester, AppButton(label: 'Pay', onPressed: () => fired++));
      await tester.tap(find.text('Pay'));
      await tester.tap(find.text('Pay'));
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('a second tap while an async action runs is ignored',
        (tester) async {
      var fired = 0;
      await pumpUi(
        tester,
        PrimaryButton(
          label: 'Pay',
          onPressed: () async {
            fired++;
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
        ),
      );
      await tester.tap(find.text('Pay'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Pay'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fired, 1);
      await tester.pump(const Duration(seconds: 1)); // let the future finish
    });

    testWidgets('loading keeps the same width and blocks taps', (tester) async {
      var fired = 0;
      await pumpUi(
        tester,
        Column(children: [
          AppButton(
              label: 'Save changes', onPressed: () => fired++, expand: false),
        ]),
      );
      final idle = tester.getSize(find.byType(AppButton)).width;
      await pumpUi(
        tester,
        Column(children: [
          AppButton(
            label: 'Save changes',
            onPressed: () => fired++,
            isLoading: true,
            expand: false,
          ),
        ]),
      );
      expect(tester.getSize(find.byType(AppButton)).width, idle);
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      expect(fired, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('null onPressed does nothing', (tester) async {
      await pumpUi(tester, const AppButton(label: 'Off', onPressed: null));
      await tester.tap(find.text('Off'), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppIconButton fires once on a double tap', (tester) async {
      var fired = 0;
      await pumpUi(
        tester,
        AppIconButton(
          icon: AppIcons.bell,
          onPressed: () => fired++,
          badgeColor: AppColors.light.statusAmber,
        ),
      );
      await tester.tap(find.byType(AppIconButton));
      await tester.tap(find.byType(AppIconButton));
      await tester.pump();
      expect(fired, 1);
      expect(find.byKey(const ValueKey('icon-badge')), findsOneWidget);
    });
  });

  group('AppDialog', () {
    forEachVariant('secondary + confirm + danger, no overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'open',
            onPressed: () => AppDialog.show(
              context,
              title: 'Cancel this order?',
              body: 'Your delivery fee will be refunded in full.',
              secondaryLabel: 'Keep order',
              confirmLabel: 'Cancel order',
              destructive: true,
            ),
          ),
        ),
        dark: dark,
        textScale: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this order?'), findsOneWidget);
      expect(find.text('Keep order'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);
    });

    testWidgets('confirm pops true, secondary pops false', (tester) async {
      bool? result;
      await pumpUi(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'open',
            onPressed: () async => result = await AppDialog.show(
              context,
              title: 'T',
              secondaryLabel: 'Back',
              confirmLabel: 'Do it',
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Do it'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('the destructive confirm is the solid dangerSolid button',
        (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'open',
            onPressed: () => AppDialog.show(
              context,
              title: 'T',
              secondaryLabel: 'Back',
              confirmLabel: 'Delete',
              destructive: true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(find
          .ancestor(of: find.text('Delete'), matching: find.byType(Material))
          .first);
      expect(material.color, AppColors.light.dangerSolid);
    });
  });

  group('AppCard / AppListGroup / AppInlineNotice / AppSheet', () {
    forEachVariant('render without overflow', (tester, dark, scale) async {
      await pumpUi(
        tester,
        Column(
          children: [
            const AppCard(child: Text('A plain card with some body text.')),
            const SizedBox(height: 12),
            AppCard(large: true, onTap: () {}, child: const Text('Tappable')),
            const SizedBox(height: 12),
            AppListGroup(children: [
              AppListRow(
                title: 'Edit profile',
                subtitle: 'Name, photo and nickname',
                leadingIcon: AppIcons.profile,
                onTap: () {},
              ),
              const AppListRow(
                title: 'Notifications and a very long title that wraps around',
                leadingIcon: AppIcons.bell,
                trailing: Text('On'),
              ),
              const AppListRow(title: 'Plain row'),
            ]),
            const SizedBox(height: 12),
            const AppInlineNotice(
              text: 'Delivery to your hostel takes about twenty minutes today.',
            ),
            const SizedBox(height: 12),
            const AppInlineNotice(text: 'That did not work.', isError: true),
          ],
        ),
        dark: dark,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppListRow is at least 56 high', (tester) async {
      await pumpUi(
        tester,
        const AppListGroup(children: [AppListRow(title: 'Row')]),
      );
      expect(tester.getSize(find.byType(AppListRow)).height,
          greaterThanOrEqualTo(56));
    });

    testWidgets('AppSheet shows a 36x4 handle', (tester) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => AppButton(
            label: 'open',
            onPressed: () => AppSheet.show(
              context,
              builder: (_) => const Text('Sheet body'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('sheet-handle'))),
          const Size(36, 4));
    });
  });

  group('AppSegmentedTabs', () {
    forEachVariant('renders with counts, no overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        AppSegmentedTabs(
          labels: const ['Cart', 'Preparing', 'Completed'],
          counts: const [2, 1, 14],
          index: 0,
          onChanged: (_) {},
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('tapping changes the index and the highlight slides',
        (tester) async {
      var index = 0;
      late StateSetter setOuter;
      await pumpUi(
        tester,
        StatefulBuilder(builder: (context, set) {
          setOuter = set;
          return AppSegmentedTabs(
            labels: const ['One', 'Two', 'Three'],
            index: index,
            onChanged: (i) => set(() => index = i),
          );
        }),
      );
      final start =
          tester.getTopLeft(find.byKey(const ValueKey('segment-highlight'))).dx;
      await tester.tap(find.text('Three'));
      await tester.pump();
      expect(index, 2);
      await tester.pumpAndSettle();
      final end =
          tester.getTopLeft(find.byKey(const ValueKey('segment-highlight'))).dx;
      expect(end, greaterThan(start + 100));
      expect(setOuter, isNotNull);
    });

    testWidgets('follows a TabController and drives it', (tester) async {
      late TabController controller;
      await pumpUi(
        tester,
        _WithController(onController: (c) => controller = c),
      );
      expect(controller.index, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
    });
  });

  group('AppStatusLabel', () {
    forEachVariant('all tones render', (tester, dark, scale) async {
      await pumpUi(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in StatusTone.values)
              AppStatusLabel(tone: t, text: 'Status ${t.name}'),
          ],
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('status-dot')), findsNWidgets(4));
    });

    testWidgets('dot colours follow the tone', (tester) async {
      await pumpUi(
        tester,
        Column(children: [
          for (final t in StatusTone.values)
            AppStatusLabel(tone: t, text: t.name),
        ]),
      );
      final dots = tester
          .widgetList<Container>(find.byKey(const ValueKey('status-dot')))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      const c = AppColors.light;
      expect(dots, [c.statusAmber, c.brand, c.textTertiary, c.dangerText]);
    });
  });

  group('AppAvatar / TierHeader', () {
    forEachVariant('every tier + unknown renders', (tester, dark, scale) async {
      await pumpUi(
        tester,
        Column(
          children: [
            for (final tier in [
              'Bronze',
              'Silver',
              'Gold',
              'Platinum',
              'Mythic',
              null
            ]) ...[
              TierHeader(
                tier: tier,
                name: 'Adaeze Okafor-Williams',
                nickname: 'adaeze',
                initial: 'A',
              ),
              const SizedBox(height: 12),
            ],
            const Row(children: [
              AppAvatar(initial: 'B'),
              SizedBox(width: 8),
              AppAvatar(initial: 'C', size: 64, tier: 'Silver'),
            ]),
          ],
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('tier-header')), findsNWidgets(6));
    });

    testWidgets('unknown tier = plain surface, no tint, no ring',
        (tester) async {
      await pumpUi(
        tester,
        const TierHeader(
            tier: 'Mythic', name: 'N', nickname: 'n', initial: 'N'),
      );
      expect(TierTokens.of('Mythic', Brightness.light), isNull);
      expect(TierTokens.of(null, Brightness.dark), isNull);
      expect(find.byKey(const ValueKey('avatar-ring')), findsNothing);
      final box = tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('tier-header')));
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, AppColors.light.surface);
      expect(deco.border!.top.color, AppColors.light.border);
    });

    testWidgets('a known tier uses its border and ring', (tester) async {
      await pumpUi(
        tester,
        const TierHeader(
            tier: 'platinum', name: 'N', nickname: 'n', initial: 'N'),
      );
      final deco = tester
          .widget<DecoratedBox>(find.byKey(const ValueKey('tier-header')))
          .decoration as BoxDecoration;
      expect(deco.border!.top.color,
          TierTokens.of('Platinum', Brightness.light)!.border);
      expect(find.byKey(const ValueKey('avatar-ring')), findsOneWidget);
    });
  });

  group('AppGlassNavBar', () {
    const items = [
      AppGlassNavItem(label: 'Home', icon: AppIcons.home),
      AppGlassNavItem(label: 'Orders', icon: AppIcons.orders, badgeCount: 3),
      AppGlassNavItem(label: 'Wallet', icon: AppIcons.wallet),
      AppGlassNavItem(label: 'Profile', icon: AppIcons.profile),
    ];

    Future<void> pumpBar(
        WidgetTester tester, int index, ValueChanged<int> onTap,
        {bool dark = false, double scale = 1.0, int count = 4}) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme_.dark : AppTheme_.light,
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: w!,
          ),
          home: Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: AppGlassNavBar(
              items: items.take(count).toList(),
              currentIndex: index,
              onTap: onTap,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('renders (${dark ? 'dark' : 'light'}, x$scale)',
            (tester) async {
          await pumpBar(tester, 0, (_) {}, dark: dark, scale: scale);
          expect(find.byKey(const ValueKey('glass-nav')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('is 68 high, 16 from the sides, 22 above the bottom',
        (tester) async {
      await pumpBar(tester, 0, (_) {});
      final r = tester.getRect(find.byKey(const ValueKey('glass-nav')));
      expect(r.height, 68);
      expect(r.left, 16);
      expect(r.right, 390 - 16);
      expect(844 - r.bottom, 22);
    });

    testWidgets('tapping an item calls back with its index', (tester) async {
      final taps = <int>[];
      await pumpBar(tester, 0, taps.add);
      await tester.tap(find.text('Wallet'));
      await tester.tap(find.text('Orders'));
      await tester.tap(find.text('Profile'));
      expect(taps, [2, 1, 3]);
    });

    testWidgets('the capsule follows the index (and slides)', (tester) async {
      var index = 0;
      late StateSetter set;
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme_.light,
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: StatefulBuilder(builder: (context, s) {
              set = s;
              return AppGlassNavBar(
                items: items,
                currentIndex: index,
                onTap: (i) => s(() => index = i),
              );
            }),
          ),
        ),
      );
      final cap = find.byKey(const ValueKey('nav-capsule'));
      final x0 = tester.getCenter(cap).dx;
      set(() => index = 3);
      await tester.pump(); // frame that starts the animation
      await tester.pump(const Duration(milliseconds: 140));
      final mid = tester.getCenter(cap).dx;
      await tester.pumpAndSettle();
      final x3 = tester.getCenter(cap).dx;
      expect(mid, greaterThan(x0)); // moving…
      expect(mid, lessThan(x3)); // …not there yet
      // Final centre sits over the 4th item.
      final profile = tester.getCenter(find.text('Profile')).dx;
      expect((x3 - profile).abs(), lessThan(2));
    });

    testWidgets('works with a single tab (kitchen staff)', (tester) async {
      await pumpBar(tester, 0, (_) {}, count: 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has exactly one BackdropFilter inside a RepaintBoundary',
        (tester) async {
      await pumpBar(tester, 0, (_) {});
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.ancestor(
            of: find.byType(BackdropFilter),
            matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
    });

    testWidgets('skips the slide when animations are disabled', (tester) async {
      var index = 0;
      late StateSetter set;
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme_.light,
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: w!,
          ),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: StatefulBuilder(builder: (context, s) {
              set = s;
              return AppGlassNavBar(
                  items: items, currentIndex: index, onTap: (_) {});
            }),
          ),
        ),
      );
      final cap = find.byKey(const ValueKey('nav-capsule'));
      final x0 = tester.getCenter(cap).dx;
      set(() => index = 3);
      await tester.pump(); // one frame, no time
      expect(tester.getCenter(cap).dx, greaterThan(x0 + 100));
    });
  });
}

/// Local alias so the nav tests can read like the others.
// ignore: camel_case_types
class AppTheme_ {
  static ThemeData get light => _t(Brightness.light);
  static ThemeData get dark => _t(Brightness.dark);
  static ThemeData _t(Brightness b) => ThemeData(
        brightness: b,
        extensions: [b == Brightness.dark ? AppColors.dark : AppColors.light],
      );
}

class _WithController extends StatefulWidget {
  const _WithController({required this.onController});
  final ValueChanged<TabController> onController;

  @override
  State<_WithController> createState() => _WithControllerState();
}

class _WithControllerState extends State<_WithController>
    with SingleTickerProviderStateMixin {
  late final TabController _c = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onController(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AppSegmentedTabs(labels: const ['Active', 'Done'], controller: _c);
}
