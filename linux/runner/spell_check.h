#pragma once
#include <flutter_linux/flutter_linux.h>

// Turkish spelling, from whatever on this machine already knows Turkish.
//
// A word list of our own is no good for a language that builds words by
// adding to them: mahkemesine, dilekçesiyle and davalılardan are all
// ordinary words and no list holds every form. Enchant is the usual way to
// reach a real checker on Linux, and it is opened at run time rather than
// linked, so a machine without it builds and runs the same and simply
// underlines nothing.
void register_spell_check(FlView* view);
