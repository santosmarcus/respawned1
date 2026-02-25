import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFFF0EADC);


  static const Color yellowrspwn = Color(0xFFFFD95E);
  static const Color greenrspwn = Color(0xFFC2B500);
  static const Color lavenderrspwn = Color(0xFFAEB7FF);
  static const Color pinkrspwn = Color(0xFFF5D6FF);
  static const Color slaterspwn = Color(0xFFD9D9D9);
  static const Color tearspwn = Color(0xFFE3E0B9);

  static const Color textPrimary = Color(0xFF393207);
  static const Color textSecondary = Color(0xFF7E7D76);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.yellowrspwn,
          primary: AppColors.yellowrspwn,
          secondary: AppColors.greenrspwn,
          //background: AppColors.background,
          surface: AppColors.background,
        ),

        textTheme: TextTheme(
          //Tilt Warp
          displayLarge:  GoogleFonts.tiltWarp(fontSize: 32, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
          displayMedium:  GoogleFonts.tiltWarp(fontSize: 20, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
          displaySmall:  GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
          headlineLarge:  GoogleFonts.tiltWarp(fontSize: 24, fontWeight: FontWeight.bold,   color: AppColors.textPrimary),
          //Zain
          titleMedium:   GoogleFonts.zain(fontSize: 24, fontWeight: FontWeight.w500,   color: AppColors.textPrimary),
          titleSmall:   GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w500,   color: AppColors.textPrimary),
        ),

        // AppBar
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.tiltWarp(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),

        // Bottom Navigation
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.yellowrspwn,
          selectedItemColor: AppColors.textPrimary,
          unselectedItemColor: AppColors.textPrimary.withOpacity(0.8),
          selectedLabelStyle: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        )
    );
  }
}