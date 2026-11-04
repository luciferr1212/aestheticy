# Third-Party Fonts & Licensing

This document lists the font families supported by Aestheticy and their open-source licenses.

## Bundled Font Families

| Font Family | Designer / Upstream | License |
|---|---|---|
| **Inter** | Rasmus Andersson | SIL Open Font License 1.1 |
| **IBM Plex Sans Arabic** | Mike Abbink / Bold Monday | SIL Open Font License 1.1 |
| **Noto Sans Arabic** | Google | SIL Open Font License 1.1 |
| **Cairo** | Mohamed Gaber, Accademia di Belle Arti di Catania | SIL Open Font License 1.1 |

## License Preservation

The complete license text for each font family is preserved in the respective `OFL.txt` file stored directly alongside the font TTF binaries in `assets/fonts/<Family>/OFL.txt`:

- `assets/fonts/Inter/OFL.txt`
- `assets/fonts/IBMPlexSansArabic/OFL.txt`
- `assets/fonts/NotoSansArabic/OFL.txt`
- `assets/fonts/Cairo/OFL.txt`

## Fallback Font Stack

When using custom or system fonts, missing glyphs (e.g. Arabic script in Latin-only fonts) automatically fall back through the following desktop font stack to guarantee seamless rendering without boxes or missing glyphs:
- `'Segoe UI Variable'`
- `'Segoe UI'`
- `'Tahoma'`
- `'Arial'`
