#include "godot_noctua.h"

#import <Foundation/Foundation.h>

#import "noctua_sdk_api.h"

GodotNoctua *GodotNoctua::instance = nullptr;

// ── Helpers ───────────────────────────────────────────────────────────────────

static NSString *const kLogPrefix = @"[GodotNoctua]";

/// Swift runtime names tried, in order, when resolving the SDK class.
static NSString *const kNoctuaSDKClassNames[] = { @"NoctuaSDK.Noctua", @"Noctua" };

static NSString *to_ns(const String &p_string) {
	return [NSString stringWithUTF8String:p_string.utf8().get_data()];
}

static String to_godot(NSString *p_string) {
	return p_string == nil ? String() : String::utf8([p_string UTF8String]);
}

/// Resolves the NoctuaSDK Swift class, or nil when the pod is not linked.
static Class<NoctuaSDKAPI> noctua_sdk_class() {
	for (NSString *name : kNoctuaSDKClassNames) {
		Class cls = NSClassFromString(name);
		if (cls != nil) {
			return (Class<NoctuaSDKAPI>)cls;
		}
	}
	return nil;
}

/// Logs every protocol selector the linked SDK does not implement.
/// Returns false when any is missing (an SDK/plugin API mismatch).
static bool verify_sdk_selectors(Class<NoctuaSDKAPI> p_cls) {
	const SEL selectors[] = {
		@selector(initNoctuaWithVerifyPurchasesOnServer:useStoreKit1:error:),
		@selector(trackCustomEvent:payload:),
		@selector(trackCustomEventWithRevenue:revenue:currency:payload:),
		@selector(trackPurchaseWithOrderId:amount:currency:extraPayload:),
		@selector(trackAdRevenueWithSource:revenue:currency:extraPayload:),
		@selector(setSessionTagWithTag:),
		@selector(getSessionTags),
		@selector(setSessionExtraParamsWithPayload:),
		@selector(setExperimentWithExperiment:),
		@selector(getExperiment),
		@selector(setGeneralExperimentWithExperiment:),
		@selector(getGeneralExperimentWithExperimentKey:),
		@selector(onOnline),
		@selector(onOffline),
		@selector(getAdjustSdkVersionWithCompletion:),
	};
	bool all_present = true;
	for (SEL selector : selectors) {
		if (![p_cls respondsToSelector:selector]) {
			NSLog(@"%@ NoctuaSDK is missing +%@ — plugin and SDK versions do not match",
					kLogPrefix, NSStringFromSelector(selector));
			all_present = false;
		}
	}
	return all_present;
}

/// Converts a GDScript Dictionary to an NSDictionary for the SDK's [String: Any]
/// parameters. Mirrors GodotNoctua.java#toSafeMap: int → 64-bit integer,
/// float → double, bool/String pass through, null is dropped, anything else
/// becomes its string form.
static NSDictionary<NSString *, id> *to_ns_dictionary(const Dictionary &p_dict) {
	NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
	Array keys = p_dict.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const Variant value = p_dict.get(key, Variant());
		NSString *ns_key = to_ns(String(key));
		switch (value.get_type()) {
			case Variant::NIL:
				break;
			case Variant::BOOL:
				result[ns_key] = @((bool)value);
				break;
			case Variant::INT:
				result[ns_key] = @((int64_t)value);
				break;
			case GODOT_NOCTUA_VARIANT_FLOAT:
				result[ns_key] = @((double)value);
				break;
			default:
				result[ns_key] = to_ns(String(value));
				break;
		}
	}
	return [result copy];
}

/// Parses a decimal amount sent from GDScript as a String ("0.99").
/// Locale-independent ('.' decimal separator), like Java's Double.parseDouble.
static bool parse_amount(const String &p_amount, double *r_value) {
	NSScanner *scanner = [NSScanner scannerWithString:to_ns(p_amount.strip_edges())];
	return [scanner scanDouble:r_value] && [scanner isAtEnd];
}

/// Runs SDK calls on the main thread — the SDK drives UIKit/StoreKit internally.
static void run_on_main(dispatch_block_t p_block) {
	if ([NSThread isMainThread]) {
		p_block();
	} else {
		dispatch_async(dispatch_get_main_queue(), p_block);
	}
}

/// Reads an SDK value on the main thread, after any setter queued by run_on_main.
static NSString *read_on_main(NSString * (^p_block)(void)) {
	if ([NSThread isMainThread]) {
		return p_block();
	}
	__block NSString *result = nil;
	dispatch_sync(dispatch_get_main_queue(), ^{
		result = p_block();
	});
	return result;
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

GodotNoctua *GodotNoctua::get_singleton() {
	return instance;
}

GodotNoctua::GodotNoctua() {
	ERR_FAIL_COND(instance != nullptr);
	instance = this;
}

GodotNoctua::~GodotNoctua() {
	if (instance == this) {
		instance = nullptr;
	}
}

void GodotNoctua::initialize_sdk() {
	if (initialized) {
		return;
	}
	NSLog(@"%@ Initializing Noctua SDK...", kLogPrefix);

	Class<NoctuaSDKAPI> sdk = noctua_sdk_class();
	if (sdk == nil) {
		ERR_PRINT("GodotNoctua: NoctuaSDK is not linked. Run sdk/ios-plugin/scripts/setup_xcode.rb on the exported Xcode project, then build the generated .xcworkspace.");
		return;
	}
	if (!verify_sdk_selectors(sdk)) {
		ERR_PRINT("GodotNoctua: linked NoctuaSDK does not match this plugin — see the Xcode console for missing methods.");
		return;
	}

	NSError *error = nil;
	// Same defaults as the Swift overload: no server-side verification, StoreKit 1.
	BOOL ok = [sdk initNoctuaWithVerifyPurchasesOnServer:NO useStoreKit1:YES error:&error];
	if (!ok) {
		ERR_PRINT("GodotNoctua: Noctua SDK initialization failed: " + to_godot(error.localizedDescription) +
				" (is noctuagg.json in the app bundle?)");
		return;
	}

	initialized = true;
	NSLog(@"%@ Noctua SDK initialized", kLogPrefix);

	[sdk getAdjustSdkVersionWithCompletion:^(NSString *_Nullable version) {
		if (version != nil) {
			NSLog(@"%@ Adjust SDK is initialized. Version: %@", kLogPrefix, version);
		} else {
			NSLog(@"%@ Adjust SDK is NOT initialized (disabled or missing from noctuagg.json)", kLogPrefix);
		}
	}];
}

// ── Event Tracking ────────────────────────────────────────────────────────────

void GodotNoctua::track_event(String event, Dictionary params) {
	if (!initialized) {
		return;
	}
	NSString *ns_event = to_ns(event);
	NSDictionary *payload = to_ns_dictionary(params);
	run_on_main(^{
		[noctua_sdk_class() trackCustomEvent:ns_event payload:payload];
	});
}

void GodotNoctua::track_custom_event_with_revenue(String event_name, String revenue, String currency, Dictionary payload) {
	if (!initialized) {
		return;
	}
	double value = 0.0;
	ERR_FAIL_COND_MSG(!parse_amount(revenue, &value), "GodotNoctua: invalid revenue '" + revenue + "'.");
	NSString *ns_event = to_ns(event_name);
	NSString *ns_currency = to_ns(currency);
	NSDictionary *ns_payload = to_ns_dictionary(payload);
	run_on_main(^{
		[noctua_sdk_class() trackCustomEventWithRevenue:ns_event revenue:value currency:ns_currency payload:ns_payload];
	});
}

void GodotNoctua::track_purchase(String order_id, String amount, String currency, Dictionary payload) {
	if (!initialized) {
		return;
	}
	double value = 0.0;
	ERR_FAIL_COND_MSG(!parse_amount(amount, &value), "GodotNoctua: invalid purchase amount '" + amount + "'.");
	NSString *ns_order_id = to_ns(order_id);
	NSString *ns_currency = to_ns(currency);
	NSDictionary *ns_payload = to_ns_dictionary(payload);
	run_on_main(^{
		[noctua_sdk_class() trackPurchaseWithOrderId:ns_order_id amount:value currency:ns_currency extraPayload:ns_payload];
	});
}

void GodotNoctua::track_ad_revenue(String ad_source, String revenue, String currency, Dictionary params) {
	if (!initialized) {
		return;
	}
	double value = 0.0;
	ERR_FAIL_COND_MSG(!parse_amount(revenue, &value), "GodotNoctua: invalid ad revenue '" + revenue + "'.");
	NSString *ns_source = to_ns(ad_source);
	NSString *ns_currency = to_ns(currency);
	NSDictionary *ns_params = to_ns_dictionary(params);
	run_on_main(^{
		[noctua_sdk_class() trackAdRevenueWithSource:ns_source revenue:value currency:ns_currency extraPayload:ns_params];
	});
}

// ── Session ───────────────────────────────────────────────────────────────────

void GodotNoctua::set_session_tag(String session_name) {
	if (!initialized) {
		return;
	}
	NSString *tag = to_ns(session_name);
	run_on_main(^{
		[noctua_sdk_class() setSessionTagWithTag:tag];
	});
}

String GodotNoctua::get_session_tag() {
	if (!initialized) {
		return String();
	}
	return to_godot(read_on_main(^{
		return [noctua_sdk_class() getSessionTags];
	}));
}

void GodotNoctua::set_session_extra_params(Dictionary params) {
	if (!initialized) {
		return;
	}
	NSDictionary *payload = to_ns_dictionary(params);
	run_on_main(^{
		[noctua_sdk_class() setSessionExtraParamsWithPayload:payload];
	});
}

// ── Experiments ───────────────────────────────────────────────────────────────

void GodotNoctua::set_experiment(String experiment) {
	if (!initialized) {
		return;
	}
	NSString *ns_experiment = to_ns(experiment);
	run_on_main(^{
		[noctua_sdk_class() setExperimentWithExperiment:ns_experiment];
	});
}

String GodotNoctua::get_experiment() {
	if (!initialized) {
		return String();
	}
	return to_godot(read_on_main(^{
		return [noctua_sdk_class() getExperiment];
	}));
}

void GodotNoctua::set_general_experiment(String experiment) {
	if (!initialized) {
		return;
	}
	NSString *ns_experiment = to_ns(experiment);
	run_on_main(^{
		[noctua_sdk_class() setGeneralExperimentWithExperiment:ns_experiment];
	});
}

String GodotNoctua::get_general_experiment(String key) {
	if (!initialized) {
		return String();
	}
	NSString *ns_key = to_ns(key);
	return to_godot(read_on_main(^{
		return [noctua_sdk_class() getGeneralExperimentWithExperimentKey:ns_key];
	}));
}

// ── Network State ─────────────────────────────────────────────────────────────

void GodotNoctua::on_online() {
	if (!initialized) {
		return;
	}
	run_on_main(^{
		[noctua_sdk_class() onOnline];
	});
}

void GodotNoctua::on_offline() {
	if (!initialized) {
		return;
	}
	run_on_main(^{
		[noctua_sdk_class() onOffline];
	});
}

// ── Bindings ──────────────────────────────────────────────────────────────────

void GodotNoctua::_bind_methods() {
	ClassDB::bind_method(D_METHOD("track_event", "event", "params"), &GodotNoctua::track_event);
	ClassDB::bind_method(D_METHOD("track_custom_event_with_revenue", "event_name", "revenue", "currency", "payload"), &GodotNoctua::track_custom_event_with_revenue);
	ClassDB::bind_method(D_METHOD("track_purchase", "order_id", "amount", "currency", "payload"), &GodotNoctua::track_purchase);
	ClassDB::bind_method(D_METHOD("track_ad_revenue", "ad_source", "revenue", "currency", "params"), &GodotNoctua::track_ad_revenue);

	ClassDB::bind_method(D_METHOD("set_session_tag", "session_name"), &GodotNoctua::set_session_tag);
	ClassDB::bind_method(D_METHOD("get_session_tag"), &GodotNoctua::get_session_tag);
	ClassDB::bind_method(D_METHOD("set_session_extra_params", "params"), &GodotNoctua::set_session_extra_params);

	ClassDB::bind_method(D_METHOD("set_experiment", "experiment"), &GodotNoctua::set_experiment);
	ClassDB::bind_method(D_METHOD("get_experiment"), &GodotNoctua::get_experiment);
	ClassDB::bind_method(D_METHOD("set_general_experiment", "experiment"), &GodotNoctua::set_general_experiment);
	ClassDB::bind_method(D_METHOD("get_general_experiment", "key"), &GodotNoctua::get_general_experiment);

	ClassDB::bind_method(D_METHOD("on_online"), &GodotNoctua::on_online);
	ClassDB::bind_method(D_METHOD("on_offline"), &GodotNoctua::on_offline);
}
