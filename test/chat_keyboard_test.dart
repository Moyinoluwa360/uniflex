// Chat keyboard fix: with the keyboard open the newest message must sit above
// the input bar and the input bar directly above the keyboard (no gap), the
// list must not be yanked when the user is reading history, sending scrolls
// to the newest message, and a growing input keeps the newest visible.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/admin/support/admin_support_chat_screen.dart';
import 'package:uniflex/shared/models/support_conversation.dart';
import 'package:uniflex/shared/models/support_message.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/support/support_chat_service.dart';
import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/widgets/chat/chat_scroll.dart';
import 'package:uniflex/student/support/support_chat_screen.dart';

const _kb = 300.0; // logical keyboard height
const _safe = 34.0; // logical home-indicator inset
const _screenH = 844.0;

final _conv = SupportConversation(
  id: 'conv-1',
  studentId: 'student-1',
  status: 'open',
  studentUnreadCount: 0,
  adminUnreadCount: 0,
  createdAt: DateTime(2026, 1, 1),
);

SupportMessage _msg(int n) => SupportMessage(
      id: '$n',
      conversationId: 'conv-1',
      senderId: n.isEven ? 'student-1' : 'admin-1',
      senderRole: n.isEven ? 'student' : 'admin',
      senderName: n.isEven ? 'Alice' : 'Bob',
      body: 'message $n',
      createdAt: DateTime(2026, 1, 1, 10, 0, n),
    );

class _Svc implements SupportChatService {
  _Svc(this.onSend);
  final void Function(String body) onSend;

  @override
  Future<Map<String, dynamic>> sendMessage(String body,
      {String? orderId, String? groupId, String? conversationId}) async {
    onSend(body.trim());
    return {'message_id': 'm', 'conversation_id': 'conv-1'};
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  Future<Map<String, dynamic>?> fetchStudentProfile(String studentId) async =>
      {'full_name': 'Alice A', 'nickname': 'alice', 'phone': '0800'};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Rig {
  _Rig(this.tester, {required this.admin, required this.dark, this.scale = 1});
  final WidgetTester tester;
  final bool admin;
  final bool dark;
  final double scale;
  final stream = StreamController<List<SupportMessage>>();
  final messages = <SupportMessage>[];
  late final _Svc svc;

  Future<void> pump({int count = 40}) async {
    tester.view.physicalSize = const Size(390, _screenH) * 2;
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(bottom: _safe * 2, top: 94);
    tester.view.viewPadding = const FakeViewPadding(bottom: _safe * 2, top: 94);
    addTearDown(tester.view.reset);
    addTearDown(stream.close);
    for (var i = 1; i <= count; i++) {
      messages.add(_msg(i));
    }
    svc = _Svc((body) {
      messages.add(_msg(messages.length + 1).copyBody(body));
      stream.add(List.of(messages));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        supportChatServiceProvider.overrideWithValue(svc),
        myConversationProvider.overrideWith((ref) => Stream.value(_conv)),
        conversationMessagesProvider.overrideWith((ref, id) => stream.stream),
        currentProfileProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: admin
            ? AdminSupportChatScreen(conversation: _conv)
            : const SupportChatScreen(),
      ),
    ));
    await tester.pump();
    stream.add(List.of(messages));
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> keyboard(bool open) async {
    tester.view.viewInsets = FakeViewPadding(bottom: open ? _kb * 2 : 0);
    await tester.pump();
    await settle();
  }

  ScrollController get list =>
      tester.widget<ListView>(find.byType(ListView).first).controller!;

  Rect rectOf(Finder f) => tester.getRect(f);
  Rect get inputBar => rectOf(find.byType(ChatBottomInset));

  /// The text field itself (what the user sees), without the bar's padding.
  Rect get field => rectOf(find.byType(TextField));
  double get keyboardTop => _screenH - _kb;
  Finder newest(int n) => find.text('message $n');
}

extension on SupportMessage {
  SupportMessage copyBody(String body) => SupportMessage(
        id: id,
        conversationId: conversationId,
        senderId: 'student-1',
        senderRole: 'student',
        senderName: 'Alice',
        body: body,
        createdAt: createdAt,
      );
}

void main() {
  for (final admin in [false, true]) {
    final who = admin ? 'admin chat' : 'student chat';
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        final v = '${dark ? 'dark' : 'light'}, x$scale';

        testWidgets(
            '$who: keyboard open keeps the newest message above the '
            'input bar ($v)', (tester) async {
          final r = _Rig(tester, admin: admin, dark: dark, scale: scale);
          await r.pump();
          expect(r.newest(40), findsOneWidget);

          await r.keyboard(true);

          expect(r.newest(40), findsOneWidget);
          final msgBottom = r.rectOf(r.newest(40)).bottom;
          expect(msgBottom, lessThanOrEqualTo(r.inputBar.top + 0.5),
              reason: 'newest message must be above the input bar');
          // The field sits on the keyboard with only the bar's own 8px
          // padding below it — no extra home-indicator gap.
          expect(r.keyboardTop - r.field.bottom, lessThanOrEqualTo(12));
          expect(tester.takeException(), isNull);

          await r.keyboard(false);
          expect(r.newest(40), findsOneWidget);
          // Keyboard closed: the home-indicator inset is back (8 + 34).
          expect(_screenH - r.field.bottom, closeTo(8 + _safe, 2));
        });
      }
    }

    testWidgets(
        '$who: scrolled-up history is not yanked when the keyboard '
        'opens', (tester) async {
      final r = _Rig(tester, admin: admin, dark: false);
      await r.pump();
      r.list.jumpTo(0);
      await r.settle();
      expect(r.list.offset, 0);

      await r.keyboard(true);
      expect(r.list.offset, 0);
      expect(r.newest(40), findsNothing);
    });

    testWidgets('$who: sending scrolls to the new message', (tester) async {
      final r = _Rig(tester, admin: admin, dark: false);
      await r.pump();
      await r.keyboard(true);

      await tester.enterText(find.byType(TextField), 'brand new reply');
      await tester.tap(find.byIcon(admin ? Icons.send_rounded : AppIcons.send));
      await r.settle();

      expect(find.text('brand new reply'), findsOneWidget);
      expect(r.rectOf(find.text('brand new reply')).bottom,
          lessThanOrEqualTo(r.inputBar.top + 0.5));
    });

    testWidgets('$who: sending while scrolled up jumps to the new message',
        (tester) async {
      final r = _Rig(tester, admin: admin, dark: false);
      await r.pump();
      r.list.jumpTo(0);
      await r.settle();

      await tester.enterText(find.byType(TextField), 'from the top');
      await tester.tap(find.byIcon(admin ? Icons.send_rounded : AppIcons.send));
      await r.settle();
      expect(find.text('from the top'), findsOneWidget);
    });

    testWidgets('$who: a long input grows without hiding the newest message',
        (tester) async {
      final r = _Rig(tester, admin: admin, dark: true, scale: 1.3);
      await r.pump();
      await r.keyboard(true);

      await tester.enterText(find.byType(TextField), 'a\nb\nc\nd\ne');
      await r.settle();

      expect(r.newest(40), findsOneWidget);
      expect(r.rectOf(r.newest(40)).bottom,
          lessThanOrEqualTo(r.inputBar.top + 0.5));
      expect(r.keyboardTop - r.field.bottom, lessThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    });
  }
}
