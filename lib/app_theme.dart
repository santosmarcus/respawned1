import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFFFBF9F4);


  static const Color yellowrspwn = Color(0xFFFFD95E);
  static const Color greenrspwn = Color(0xFFC2B500);
  static const Color lavenderrspwn = Color(0xFFAEB7FF);
  static const Color pinkrspwn = Color(0xFFF5D6FF);
  static const Color slaterspwn = Color(0xFFD9D9D9);
  static const Color tearspwn = Color(0xFFE3E0B9);

  static const Color textPrimary = Color(0xFF393207);
  static const Color textSecondary = Color(0xFF7E7D76);
  static const Color bgres = Color(0xFFE2E5FF);
  static const Color surface = Color(0xFFFFFFFF);

  // Meaning colours. Use these instead of a hard-coded red, amber or green.
  static const Color error = Color(0xFFE05353);
  static const Color warning = Color(0xFFE0A030);
  static const Color success = Color(0xFF4CAF6D);
}

/// The app's button looks. Pass one as `style:` instead of writing a new
/// `styleFrom(...)` on each button.
class AppButtons {
  const AppButtons._();

  static final RoundedRectangleBorder _pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(30));

  /// The main action on a screen or sheet (yellow pill).
  static final ButtonStyle primary = ElevatedButton.styleFrom(
    backgroundColor: AppColors.yellowrspwn,
    foregroundColor: AppColors.textPrimary,
    disabledBackgroundColor: AppColors.slaterspwn,
    elevation: 0,
    shape: _pill,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: GoogleFonts.tiltWarp(fontSize: 15),
  );

  /// A secondary action beside or below the main one (outlined pill).
  static final ButtonStyle outline = OutlinedButton.styleFrom(
    foregroundColor: AppColors.textPrimary,
    side: const BorderSide(color: AppColors.textPrimary),
    shape: _pill,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    textStyle: GoogleFonts.tiltWarp(fontSize: 14),
  );

  /// A destructive secondary action (outlined pill in the error colour).
  static final ButtonStyle dangerOutline = OutlinedButton.styleFrom(
    foregroundColor: AppColors.error,
    side: const BorderSide(color: AppColors.error),
    shape: _pill,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    textStyle: GoogleFonts.tiltWarp(fontSize: 14),
  );

  /// A destructive main action (reject, delete, cancel an event).
  static final ButtonStyle danger = ElevatedButton.styleFrom(
    backgroundColor: AppColors.error,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.slaterspwn,
    elevation: 0,
    shape: _pill,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: GoogleFonts.tiltWarp(fontSize: 15),
  );
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
        displayLarge: GoogleFonts.tiltWarp(fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary),
        displayMedium: GoogleFonts.tiltWarp(fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary),
        displaySmall: GoogleFonts.tiltWarp(fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary),
        headlineLarge: GoogleFonts.tiltWarp(fontSize: 24,
            fontWeight: FontWeight.normal,
            color: AppColors.textPrimary),
        //Zain
        titleLarge: GoogleFonts.zain(fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary),
        titleMedium: GoogleFonts.zain(fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary),
        titleSmall: GoogleFonts.zain(fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.tiltWarp(
          fontSize: 32,
          fontWeight: FontWeight.normal,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.yellowrspwn,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textPrimary.withValues(alpha: 0.8),
        selectedLabelStyle: GoogleFonts.zain(
            fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.zain(
            fontSize: 12, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static ThemeData get rescuerTheme {
    return lightTheme.copyWith(
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.textPrimary,
        selectedItemColor: AppColors.background,
        unselectedItemColor: AppColors.background.withValues(alpha: 0.8),
        selectedLabelStyle:
        GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle:
        GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}