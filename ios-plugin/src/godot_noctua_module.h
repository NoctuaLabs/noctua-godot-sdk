// Entry points referenced by GodotNoctua.gdip ([config] initialization /
// deinitialization). Godot's iOS export generates calls to these during
// application start-up and shutdown.

#ifndef GODOT_NOCTUA_MODULE_H
#define GODOT_NOCTUA_MODULE_H

void godot_noctua_init();
void godot_noctua_deinit();

#endif // GODOT_NOCTUA_MODULE_H
