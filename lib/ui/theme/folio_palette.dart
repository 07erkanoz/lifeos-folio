import 'package:flutter/material.dart';

/// The pages' own colours, light or dark as the app's theme is.
///
/// The agenda, the notices, the cases and the home page were drawn with
/// fixed colours made for a white page: pale fills under dark words. On the
/// dark theme their fills stayed pale and their words turned light, and
/// what was written on them could not be read. [tone] gives each such
/// colour its dark counterpart: a pale fill the same hue made deep, a dark
/// word the same hue made light, a strong colour a little lighter; on the
/// light theme it gives the colour back as it is.
abstract final class FolioPalette {
  /// Whether the dark theme is showing; set by the app's builder from the
  /// theme it is given, before the pages below it are built.
  static bool dark = false;

  static Color tone(Color c) {
    if (!dark) return c;
    final a = c.a;
    // A shadow or a veil: dark on the dark theme too.
    if (a < 1) return c;
    final hsl = HSLColor.fromColor(c);
    final l = hsl.lightness;
    final s = hsl.saturation;
    if (l >= .7) {
      // A fill, a hairline, a page: the same hue, deep and quieter.
      return hsl
          .withLightness(.10 + (1 - l) * .5)
          .withSaturation(s * .5)
          .toColor();
    }
    if (l < .36) {
      // A word written on a fill: the same hue, light.
      return hsl
          .withLightness(.92 - l * .4)
          .withSaturation(s > .7 ? .7 : s)
          .toColor();
    }
    // A strong colour, or a grey for the quieter words: a little lighter,
    // to stand on a dark page as it did on a light one.
    return hsl
        .withLightness((l + (s > .25 ? .12 : .08)).clamp(0, .78))
        .toColor();
  }
}

/// [FolioPalette.tone]: [c], or its counterpart on the dark theme.
Color tone(Color c) => FolioPalette.tone(c);
