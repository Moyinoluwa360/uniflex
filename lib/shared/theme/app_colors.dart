import 'package:flutter/material.dart';

/// Brand colour palette — matches the visual design handoff's Foundations
/// panel exactly (hex values are taken straight from it, not eyeballed).
/// Every colour used anywhere in the app should trace back to a constant
/// defined here — no hex codes scattered through screen code. Student,
/// Rider, and Admin experiences all draw from this single palette so the
/// app reads as one product across roles.
abstract final class AppColors {
  // ---- Brand ----------------------------------------------------------
  /// Primary brand colour. Success states, active tiers, selected states.
  static const Color emerald = Color(0xFF10B981);

  /// Call-to-action colour: Order, Pay, Confirm — anything that moves a
  /// flow forward and costs the user money or commits them to an action.
  /// Per the design, orange "never dims" — it stays full-chroma in dark
  /// mode too, unlike emerald.
  static const Color orange = Color(0xFFF97316);

  // ---- Light mode neutrals ----------------------------------------------
  static const Color matteBlack = Color(0xFF101312);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color softGrey = Color(0xFFF5F6F5);
  static const Color mediumGrey = Color(0xFF9CA3AF);
  static const Color borderGrey = Color(0xFFE5E7EB);

  // ---- Dark mode -------------------------------------------------------
  // "Surfaces, not a filter" — dark mode is a deliberately separate
  // system, not light-mode colours run through a dark overlay. See the
  // design handoff's "How dark mode is built" panel.
  /// Page canvas in dark mode (near-black, not true black).
  static const Color darkCanvas = Color(0xFF0C0F0E);

  /// Card/sheet surface in dark mode — lifted one step above the canvas.
  static const Color darkCard = Color(0xFF141917);

  /// General "dark surface" swatch from Foundations (dark-mode cards).
  /// Slightly lighter than [darkCard]; used where a second, more
  /// elevated dark surface is needed (e.g. the mock role/dev screens).
  static const Color darkSurface = Color(0xFF161A18);

  /// 1px hairline between dark-mode surfaces — shadows do almost no work
  /// in the dark, hairlines do the separation instead.
  static const Color darkHairline = Color.fromRGBO(255, 255, 255, 0.07);

  /// Primary / secondary text ink in dark mode.
  static const Color darkInkPrimary = Color(0xFFF2F4F3);
  static const Color darkInkSecondary = Color(0xFF8B938F);

  /// Emerald's dark-mode job: it drops from a full field to a deep
  /// gradient accent (header/hero surfaces only), reappearing as accent,
  /// glow, and the active tier state elsewhere.
  static const Color darkEmerald = Color(0xFF0A4433);

  // ---- Splash gradient stops (Design Board 01) -------------------------
  /// Top stop of the splash brand gradient (#12C48C on the board).
  static const Color splashGradientTop = Color(0xFF12C48C);

  /// Mid stop of the splash brand gradient (#0E9E74 on the board).
  static const Color splashGradientMid = Color(0xFF0E9E74);

  // ---- Membership tier accents (Design Board 24) -----------------------
  static const Color tierBronze = Color(0xFFCD7F32);
  static const Color tierSilver = Color(0xFF6B7280);
  static const Color tierGold = Color(0xFFB45309);
  static const Color tierPlatinum = Color(0xFF6D28D9);

  /// Violet accent used for Around-type and completed-state chips/badges.
  static const Color accentViolet = Color(0xFF7C3AED);

  // ---- Semantic -----------------------------------------------------
  static const Color success = emerald;
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
}
