import 'package:flutter/material.dart';

/// The single source of icons (UI Polish 1).
///
/// One family only: Material **outlined** glyphs (`Icons.*_outlined`), which is
/// the outline set already in the project — no new dependency. Never mix a
/// filled glyph in: the active state is shown by colour/capsule, not by
/// swapping to a filled icon.
///
/// Sizes: 22 (list rows, nav, icon buttons), 20 (inside buttons), 18
/// (chevrons, inline). Colour: `context.colors.textSecondary` unless the icon
/// is active/primary.
abstract final class AppIconSize {
  static const double regular = 22;
  static const double inButton = 20;
  static const double small = 18;
}

abstract final class AppIcons {
  // ── Navigation / areas ──────────────────────────────────────────────
  static const IconData home = Icons.home_outlined;
  static const IconData orders = Icons.receipt_long_outlined;
  static const IconData wallet = Icons.account_balance_wallet_outlined;
  static const IconData profile = Icons.person_outline;
  static const IconData jobs = Icons.inbox_outlined;
  static const IconData rider = Icons.two_wheeler_outlined;
  static const IconData history = Icons.history_outlined;
  static const IconData dashboard = Icons.dashboard_outlined;
  static const IconData manage = Icons.tune_outlined;
  static const IconData analytics = Icons.bar_chart_outlined;
  static const IconData kitchen = Icons.restaurant_menu_outlined;
  static const IconData vendor = Icons.storefront_outlined;
  static const IconData food = Icons.restaurant_outlined;
  static const IconData pack = Icons.inventory_2_outlined;

  // ── Actions ─────────────────────────────────────────────────────────
  static const IconData search = Icons.search;
  static const IconData close = Icons.close;
  static const IconData add = Icons.add;
  static const IconData remove = Icons.remove;
  static const IconData check = Icons.check;
  static const IconData back = Icons.arrow_back;
  static const IconData forward = Icons.arrow_forward;
  static const IconData arrowDown = Icons.arrow_downward;
  static const IconData arrowUp = Icons.arrow_upward;
  static const IconData chevronRight = Icons.chevron_right;
  static const IconData chevronLeft = Icons.chevron_left;
  static const IconData chevronDown = Icons.expand_more;
  static const IconData chevronUp = Icons.expand_less;
  static const IconData refresh = Icons.refresh;
  static const IconData delete = Icons.delete_outline;
  static const IconData edit = Icons.edit_outlined;
  static const IconData share = Icons.ios_share_outlined;
  static const IconData copy = Icons.content_copy_outlined;
  static const IconData logout = Icons.logout;
  static const IconData openExternal = Icons.open_in_new;

  // ── Things ──────────────────────────────────────────────────────────
  static const IconData cart = Icons.shopping_cart_outlined;
  static const IconData bell = Icons.notifications_none_outlined;
  static const IconData gift = Icons.card_giftcard_outlined;
  static const IconData image = Icons.image_outlined;
  static const IconData send = Icons.send_outlined;
  static const IconData award = Icons.workspace_premium_outlined;
  static const IconData trophy = Icons.emoji_events_outlined;
  static const IconData star = Icons.star_outline;
  static const IconData location = Icons.location_on_outlined;
  static const IconData phone = Icons.phone_outlined;
  static const IconData mail = Icons.mail_outline;
  // Form-field leading icons (UI Polish 3). Same glyphs the fields used before.
  static const IconData idCard = Icons.badge_outlined;
  static const IconData atSign = Icons.alternate_email;
  static const IconData calendar = Icons.calendar_today_outlined;
  static const IconData sms = Icons.sms_outlined;
  static const IconData pin = Icons.pin_outlined;
  static const IconData lock = Icons.lock_outline;
  static const IconData chat = Icons.chat_bubble_outline;
  static const IconData clock = Icons.schedule_outlined;
  static const IconData group = Icons.people_outline;
  static const IconData receipt = Icons.receipt_outlined;
  static const IconData savings = Icons.savings_outlined;
  static const IconData bank = Icons.account_balance_outlined;
  static const IconData eye = Icons.visibility_outlined;
  static const IconData eyeOff = Icons.visibility_off_outlined;
  static const IconData errand = Icons.directions_run_outlined;
  static const IconData delivery = Icons.delivery_dining_outlined;
  static const IconData moon = Icons.dark_mode_outlined;
  static const IconData sun = Icons.light_mode_outlined;
  static const IconData auto = Icons.brightness_auto_outlined;

  // ── Feedback ────────────────────────────────────────────────────────
  static const IconData info = Icons.info_outline;
  static const IconData error = Icons.error_outline;
  static const IconData success = Icons.check_circle_outline;
  static const IconData offline = Icons.wifi_off_outlined;
}
