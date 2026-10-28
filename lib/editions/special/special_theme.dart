import 'package:flutter/material.dart';

ThemeData specialTheme(ThemeData base) => base.copyWith(
  scaffoldBackgroundColor: const Color(0xFFF4F7FF),
  colorScheme: base.colorScheme.copyWith(
    primary: const Color(0xFF4A72FF),
    secondary: const Color(0xFFFF8E35),
  ),
  appBarTheme: base.appBarTheme.copyWith(
    backgroundColor: const Color(0xFFF4F7FF),
    surfaceTintColor: Colors.transparent,
  ),
  cardTheme: const CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      side: BorderSide(color: Color(0xFFE5ECFA)),
    ),
  ),
  inputDecorationTheme: base.inputDecorationTheme.copyWith(
    filled: true,
    fillColor: const Color(0xFFF2F5FC),
  ),
  chipTheme: base.chipTheme.copyWith(
    labelStyle: base.chipTheme.labelStyle?.copyWith(fontFamily: 'sans-serif'),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: (base.filledButtonTheme.style ?? const ButtonStyle()).merge(
      FilledButton.styleFrom(
        backgroundColor: const Color(0xFF4A72FF),
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  ),
);
