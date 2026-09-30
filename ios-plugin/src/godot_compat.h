// Godot 3.x / 4.x source compatibility for the GodotNoctua iOS plugin.
//
// build.sh compiles this plugin once per engine major version and passes
// -DGODOT_NOCTUA_GODOT4 for 4.x, so the rest of the plugin can be written once.

#ifndef GODOT_NOCTUA_COMPAT_H
#define GODOT_NOCTUA_COMPAT_H

#ifdef GODOT_NOCTUA_GODOT4

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/string/ustring.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

#define GODOT_NOCTUA_VARIANT_FLOAT Variant::FLOAT

#else

#include "core/array.h"
#include "core/class_db.h"
#include "core/dictionary.h"
#include "core/engine.h"
#include "core/object.h"
#include "core/ustring.h"
#include "core/variant.h"

#define GODOT_NOCTUA_VARIANT_FLOAT Variant::REAL

#endif

#endif // GODOT_NOCTUA_COMPAT_H
