#pragma once

#include <flutter_linux/flutter_linux.h>

// Exposes the rich clipboard targets both ways. Flutter's stock Clipboard API
// only knows text/plain, which discards Word/LibreOffice formatting on paste
// and gives other programs nothing but text when Folio copies.
void register_rich_clipboard(FlView* view);
