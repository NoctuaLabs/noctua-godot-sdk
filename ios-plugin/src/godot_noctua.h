// GodotNoctua — iOS engine singleton bridging GDScript to the Noctua iOS SDK.
//
// Registered as Engine singleton "GodotNoctua", the same name the Android plugin
// uses, so sdk/gd/noctua.gd works unchanged on both platforms:
//
//   GDScript (noctua.gd autoload)
//       → GodotNoctua (this class, Objective-C++)
//           → Noctua (NoctuaSDK Swift class, linked via CocoaPods)
//
// Method names and argument types mirror GodotNoctua.java exactly. Numeric
// amounts arrive as Strings (as on Android) and are parsed to double here.

#ifndef GODOT_NOCTUA_H
#define GODOT_NOCTUA_H

#include "godot_compat.h"

class GodotNoctua : public Object {
	GDCLASS(GodotNoctua, Object);

	static GodotNoctua *instance;

	/// true once Noctua.initNoctua() succeeded; every call is a no-op before that.
	bool initialized = false;

protected:
	static void _bind_methods();

public:
	static GodotNoctua *get_singleton();

	/// Resolves the NoctuaSDK class and initialises it from the bundled noctuagg.json.
	void initialize_sdk();

	// Event tracking
	void track_event(String event, Dictionary params);
	void track_purchase(String order_id, String amount, String currency, Dictionary payload);
	void track_ad_revenue(String ad_source, String revenue, String currency, Dictionary params);

	// Session
	void set_session_tag(String session_name);
	String get_session_tag();
	void set_session_extra_params(Dictionary params);

	// Experiments
	void set_experiment(String experiment);
	String get_experiment();
	void set_general_experiment(String experiment);
	String get_general_experiment(String key);

	// Network state
	void on_online();
	void on_offline();

	GodotNoctua();
	~GodotNoctua();
};

#endif // GODOT_NOCTUA_H
