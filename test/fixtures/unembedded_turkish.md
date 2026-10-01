# Unembedded Turkish PDF regression fixture

`unembedded_turkish.pdf` is self-authored test data. It contains two A4 pages,
Turkish characters, a TimesNewRomanPSMT TrueType font descriptor without embedded
font data, and Windows-1254 Differences entries (Gbreve, Idotaccent, Scedilla,
gbreve, dotlessi, scedilla). Character widths come from the bundled OFL-licensed
Liberation Serif font. It contains no real case, identity or customer data.

Manual native-viewer checks: all Turkish glyphs appear; scroll to both page
bottoms; first/last navigation updates the counter; rotate both ways without
rotating the toolbar/scrollbar; fit page/width and expand the preview. Source
bytes must remain unchanged. `pdf_fonts_test.dart` checks the bundled fallback
font glyph coverage in all twelve font/style combinations.
