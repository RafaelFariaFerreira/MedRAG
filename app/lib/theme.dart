import 'package:material_ui/material_ui.dart';

/// Paleta do app. Uma instância para o tema claro e outra para o escuro.
class Pal {
  final bool dark;
  final Color bg, surface, surfaceAlt, ink, inkSoft, inkFaint, line;
  final Color primary, onPrimary, ok, bad, warn, marca, nota;

  const Pal({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.primary,
    required this.onPrimary,
    required this.ok,
    required this.bad,
    required this.warn,
    required this.marca,
    required this.nota,
  });

  static const light = Pal(
    dark: false,
    bg: Color(0xFFF6F4EF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFECE5),
    ink: Color(0xFF1C1B1A),
    inkSoft: Color(0xFF5F5B55),
    inkFaint: Color(0xFF9A958C),
    line: Color(0xFFE4E0D6),
    primary: Color(0xFF1F4E46),
    onPrimary: Color(0xFFFFFFFF),
    ok: Color(0xFF2E7D5B),
    bad: Color(0xFFC0392B),
    warn: Color(0xFFB7791F),
    marca: Color(0xFFFFF0A3),
    nota: Color(0xFFFFF7D6),
  );

  static const darkPal = Pal(
    dark: true,
    bg: Color(0xFF111312),
    surface: Color(0xFF1A1D1C),
    surfaceAlt: Color(0xFF232726),
    ink: Color(0xFFECEAE4),
    inkSoft: Color(0xFFA9A59C),
    inkFaint: Color(0xFF726F68),
    line: Color(0xFF2D3130),
    primary: Color(0xFF7FD1BE),
    onPrimary: Color(0xFF0C2420),
    ok: Color(0xFF6FCF9F),
    bad: Color(0xFFF08A7B),
    warn: Color(0xFFE5B567),
    marca: Color(0xFF5A4E12),
    nota: Color(0xFF3A3520),
  );

  /// Cor de identidade de cada módulo (ajuda a "compartimentalizar").
  Color modulo(String id) {
    switch (id) {
      case 'tireoide':
        return dark ? const Color(0xFFF0A070) : const Color(0xFFC2571A);
      case 'linfadenopatias':
        return dark ? const Color(0xFF6CCFC7) : const Color(0xFF1B7F79);
      case 'linfomas':
        return dark ? const Color(0xFFA99CF5) : const Color(0xFF5B4BC4);
      default:
        return inkSoft;
    }
  }

  Color soft(Color c, [double a = .11]) => c.withValues(alpha: dark ? a + .05 : a);
}

extension PalX on BuildContext {
  Pal get pal => Theme.of(this).brightness == Brightness.dark ? Pal.darkPal : Pal.light;
}

const kSerif = 'DMSerif';

String moduloNome(String id) => switch (id) {
      'tireoide' => 'Tireoide',
      'linfadenopatias' => 'Linfadenopatias',
      'linfomas' => 'Linfomas',
      _ => 'Outros',
    };

IconData moduloIcone(String id) => switch (id) {
      'tireoide' => Icons.spa_outlined,
      'linfadenopatias' => Icons.bubble_chart_outlined,
      'linfomas' => Icons.hub_outlined,
      _ => Icons.more_horiz,
    };

ThemeData buildTheme(Pal p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: p.dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surface,
      onSurface: p.ink,
      outline: p.line,
      error: p.bad,
    ),
  );
  return base.copyWith(
    splashFactory: InkSparkle.splashFactory,
    dividerColor: p.line,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.soft(p.primary, .14),
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.primary : p.inkSoft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 23,
          color: s.contains(WidgetState.selected) ? p.primary : p.inkSoft,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.inkFaint, fontSize: 14.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary, width: 1.6),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? p.surfaceAlt : p.ink,
      contentTextStyle: TextStyle(color: p.dark ? p.ink : p.bg, fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
