import 'package:flutter/material.dart';

/// Charte de l'application : bleu profond, accent doré, fonds blancs.
class AppCouleurs {
  const AppCouleurs._();

  static const bleu = Color(0xFF0F3D75);
  static const bleuClair = Color(0xFF1F66B0);
  static const bleuPale = Color(0xFFE8F0FA);
  static const or = Color(0xFFE9B15E);
  static const encre = Color(0xFF14263F);
  static const gris = Color(0xFF66748A);
  static const bordure = Color(0xFFE4EAF2);
  static const fond = Color(0xFFFBFCFE);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const bleu = AppCouleurs.bleu;
    const encre = AppCouleurs.encre;
    const fond = AppCouleurs.fond;
    const bordure = AppCouleurs.bordure;

    final couleurs = ColorScheme.fromSeed(seedColor: bleu).copyWith(
      primary: bleu,
      onPrimary: Colors.white,
      primaryContainer: AppCouleurs.bleuPale,
      onPrimaryContainer: bleu,
      secondary: AppCouleurs.or,
      onSecondary: encre,
      secondaryContainer: AppCouleurs.bleuPale,
      onSecondaryContainer: bleu,
      surface: Colors.white,
      onSurface: encre,
      surfaceTint: Colors.transparent,
      outlineVariant: bordure,
    );
    final formeBouton = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const texteBouton = TextStyle(fontWeight: FontWeight.w600, fontSize: 15);
    final textes = ThemeData(
      useMaterial3: true,
      colorScheme: couleurs,
    ).textTheme.apply(bodyColor: encre, displayColor: encre);

    return ThemeData(
      useMaterial3: true,
      colorScheme: couleurs,
      scaffoldBackgroundColor: fond,
      textTheme: textes.copyWith(
        headlineSmall: textes.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: textes.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: textes.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: textes.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: textes.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: fond,
        foregroundColor: encre,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: encre,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: bordure),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: bleu,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          shape: formeBouton,
          textStyle: texteBouton,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: bleu,
          minimumSize: const Size(64, 48),
          shape: formeBouton,
          side: const BorderSide(color: bordure),
          textStyle: texteBouton,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: bleu,
          shape: formeBouton,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (etats) => etats.contains(WidgetState.selected) ? bleu : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (etats) => etats.contains(WidgetState.selected) ? Colors.white : encre,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: bordure)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: bleu,
        showCheckmark: false,
        side: const BorderSide(color: bordure),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith(
            (etats) => etats.contains(WidgetState.selected) ? Colors.white : encre,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x33000000),
        elevation: 6,
        height: 66,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (etats) => IconThemeData(
            size: 24,
            color: etats.contains(WidgetState.selected) ? bleu : AppCouleurs.gris,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (etats) => TextStyle(
            // Six onglets sur 360 dp : « Réclamations » doit tenir sur une ligne.
            fontSize: 9.5,
            letterSpacing: 0,
            color: etats.contains(WidgetState.selected) ? bleu : AppCouleurs.gris,
            fontWeight: etats.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: bleu,
        labelColor: bleu,
        unselectedLabelColor: AppCouleurs.gris,
        dividerColor: bordure,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      dividerTheme: const DividerThemeData(color: bordure, thickness: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: bleu,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: encre,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: bordure),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: bleu, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
