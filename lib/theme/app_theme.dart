import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.light,
    seedColor: AppColors.primary,
    surface: AppColors.surfaceLight,
  ),
  textTheme: GoogleFonts.notoSansTcTextTheme(),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: AppColors.accentDark,
    surface: AppColors.surfaceDark,
  ),
  textTheme: GoogleFonts.notoSansTcTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  ),
);
