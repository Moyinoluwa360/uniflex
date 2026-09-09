import 'package:flutter/material.dart';

/// Brand colour palette. Every colour used anywhere in the app should
/// trace back to a constant defined here — no hex codes scattered through
/// screen code. Student, Rider, and Admin experiences all draw from this
/// single palette so the app reads as one product across roles.
abstract final class AppColors {
  // ---- Brand ----------------------------------------------------------
  /// Primary brand colour. Success states, active tiers, selected states.
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDark = Color(0xFF0B8F65);
  static const Color emeraldLight = Color(0xFFD1FAE5);

  /// Call-to-action colour: Order, Pay, Confirm — anything that moves a
  /// flow forward and costs the user money or commits them to an action.
  static const Color orange = Color(0xFFF97316);
  static const Color orangeDark = Color(0xFFC2540A);
  static const Color orangeLight = Color(0xFFFFEDD5);

  // ---- Neutrals ---------------------------------------------------------
  static const Color matteBlack = Color(0xFF121212);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color softGrey = Color(0xFFF3F4F6);
  static const Color mediumGrey = Color(0xFF9CA3AF);
  static const Color borderGrey = Color(0xFFE5E7EB);

  // ---- Dark mode surfaces ----------------------------------------------
  // Layered slightly above pure black so cards/sheets read as elevated,
  // matching the Uber/Notion convention of near-black rather than true black.
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceElevated = Color(0xFF242426);
  static const Color darkBorder = Color(0xFF2E2E30);

  // ---- Semantic -----------------------------------------------------
  static const Color success = emerald;
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
}
