#include "godot_noctua_module.h"

#include "godot_noctua.h"

static GodotNoctua *godot_noctua = nullptr;

void godot_noctua_init() {
	godot_noctua = memnew(GodotNoctua);
	Engine::get_singleton()->add_singleton(Engine::Singleton("GodotNoctua", godot_noctua));
	// Like the Android plugin's onMainCreate(): the SDK reads noctuagg.json on its own.
	godot_noctua->initialize_sdk();
}

void godot_noctua_deinit() {
	if (godot_noctua != nullptr) {
		memdelete(godot_noctua);
		godot_noctua = nullptr;
	}
}
