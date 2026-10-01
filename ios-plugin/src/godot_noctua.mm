#include "godot_noctua.h"

#include <cmath>
#import <Foundation/Foundation.h>

#import "noctua_sdk_api.h"

GodotNoctua *GodotNoctua::instance = nullptr;

// ── Helpers ───────────────────────────────────────────────────────────────────

static NSString *const kLogPrefix = @"[GodotNoctua]";

/// Detailed trace logging, on only when noctuagg.json has "sandboxEnabled": true.
/// Errors and warnings are always logged.
static bool sandbox_enabled = false;

static void trace(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void trace(NSString *format, ...) {
	if (!sandbox_enabled) {
		return;
	}
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	NSLog(@"%@ [sandbox] %@", kLogPrefix, message);
}

/// Reads noctua.sandboxEnabled from the bundled noctuagg.json, so the init steps can be
/// traced before the SDK loads its config. Missing file or bad JSON means "not sandbox".
static bool read_sandbox_flag() {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"noctuagg" ofType:@"json"];
	NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
	id root = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	id noctua = [root isKindOfClass:[NSDictionary class]] ? root[@"noctua"] : nil;
	id flag = [noctua isKindOfClass:[NSDictionary class]] ? noctua[@"sandboxEnabled"] : nil;
	return [flag respondsToSelector:@selector(boolValue)] && [flag boolValue];
}

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
	return [scanner scanDouble:r_value] && [scanner isAtEnd] && std::isfinite(*r_value);
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
	const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
	sandbox_enabled = read_sandbox_flag();
	trace(@"init 1/4: start (noctuagg.json sandboxEnabled=true)");

	Class<NoctuaSDKAPI> sdk = noctua_sdk_class();
	if (sdk == nil) {
		init_error = "NoctuaSDK is not linked (run sdk/ios-plugin/scripts/setup_xcode.sh and open the .xcworkspace)";
		ERR_PRINT("GodotNoctua: NoctuaSDK is not linked. Run sdk/ios-plugin/scripts/setup_xcode.rb on the exported Xcode project, then build the generated .xcworkspace.");
		return;
	}
	if (!verify_sdk_selectors(sdk)) {
		init_error = "linked NoctuaSDK does not match this plugin (see the Xcode console for missing methods)";
		ERR_PRINT("GodotNoctua: linked NoctuaSDK does not match this plugin — see the Xcode console for missing methods.");
		return;
	}
	trace(@"init 2/4: NoctuaSDK linked, all selectors present");

	NSError *error = nil;
	// Same defaults as the Swift overload: no server-side verification, StoreKit 1.
	BOOL ok = [sdk initNoctuaWithVerifyPurchasesOnServer:NO useStoreKit1:YES error:&error];
	if (!ok) {
		init_error = to_godot(error.localizedDescription);
		ERR_PRINT("GodotNoctua: Noctua SDK initialization failed: " + to_godot(error.localizedDescription) +
				" (is noctuagg.json in the app bundle?)");
		trace(@"init: FAILED after %.0f ms - every tracking call will be ignored", (CFAbsoluteTimeGetCurrent() - started) * 1000);
		return;
	}
	trace(@"init 3/4: initNoctua succeeded");

	initialized = true;
	NSLog(@"%@ Noctua SDK initialized (sandbox=%d)", kLogPrefix, sandbox_enabled);
	trace(@"init 4/4: complete in %.0f ms - tracking calls are now accepted", (CFAbsoluteTimeGetCurrent() - started) * 1000);

	[sdk getAdjustSdkVersionWithCompletion:^(NSString *_Nullable version) {
		if (version != nil) {
			trace(@"adjust: initialized, SDK version %@", version);
		} else {
			NSLog(@"%@ Adjust SDK is NOT initialized (disabled or missing from noctuagg.json)", kLogPrefix);
		}
	}];
}

bool GodotNoctua::require_initialized(const char *p_method) {
	if (initialized) {
		return true;
	}
	static NSMutableSet<NSString *> *warned = [NSMutableSet set];
	NSString *method = [NSString stringWithUTF8String:p_method];
	@synchronized(warned) {
		if ([warned containsObject:method]) {
			return false;
		}
		[warned addObject:method];
	}
	String reason = init_error.length() == 0 ? String() : " (" + init_error + ")";
	WARN_PRINT(String("GodotNoctua: ") + p_method + " ignored: Noctua SDK is not initialized" + reason +
			". Check that noctuagg.json is in the app bundle (setup_xcode.sh).");
	return false;
}

bool GodotNoctua::is_initialized() const {
	return initialized;
}

String GodotNoctua::get_init_error() const {
	return init_error;
}

bool GodotNoctua::is_sandbox_enabled() const {
	return sandbox_enabled;
}

// ── Event Tracking ────────────────────────────────────────────────────────────

void GodotNoctua::track_event(String event, Dictionary params) {
	if (!require_initialized("track_event")) {
		return;
	}
	NSString *ns_event = to_ns(event);
	NSDictionary *payload = to_ns_dictionary(params);
	trace(@"track_event: event='%@' params=%@", ns_event, payload);
	run_on_main(^{
		[noctua_sdk_class() trackCustomEvent:ns_event payload:payload];
		trace(@"track_event: sent to native SDK");
	});
}

void GodotNoctua::track_purchase(String order_id, String amount, String currency, Dictionary payload) {
	if (!require_initialized("track_purchase")) {
		return;
	}
	double value = 0.0;
	ERR_FAIL_COND_MSG(!parse_amount(amount, &value), "GodotNoctua: invalid purchase amount '" + amount + "'.");
	NSString *ns_order_id = to_ns(order_id);
	NSString *ns_currency = to_ns(currency);
	NSDictionary *ns_payload = to_ns_dictionary(payload);
	trace(@"track_purchase: order='%@' amount='%@' (parsed %g) currency='%@' payload=%@", ns_order_id, to_ns(amount), value, ns_currency, ns_payload);
	run_on_main(^{
		[noctua_sdk_class() trackPurchaseWithOrderId:ns_order_id amount:value currency:ns_currency extraPayload:ns_payload];
		trace(@"track_purchase: sent to native SDK");
	});
}

void GodotNoctua::track_ad_revenue(String ad_source, String revenue, String currency, Dictionary params) {
	if (!require_initialized("track_ad_revenue")) {
		return;
	}
	double value = 0.0;
	ERR_FAIL_COND_MSG(!parse_amount(revenue, &value), "GodotNoctua: invalid ad revenue '" + revenue + "'.");
	NSString *ns_source = to_ns(ad_source);
	NSString *ns_currency = to_ns(currency);
	NSDictionary *ns_params = to_ns_dictionary(params);
	trace(@"track_ad_revenue: source='%@' revenue='%@' (parsed %g) currency='%@' params=%@", ns_source, to_ns(revenue), value, ns_currency, ns_params);
	run_on_main(^{
		[noctua_sdk_class() trackAdRevenueWithSource:ns_source revenue:value currency:ns_currency extraPayload:ns_params];
		trace(@"track_ad_revenue: sent to native SDK");
	});
}

// ── Session ───────────────────────────────────────────────────────────────────

void GodotNoctua::set_session_tag(String session_name) {
	if (!require_initialized("set_session_tag")) {
		return;
	}
	NSString *tag = to_ns(session_name);
	trace(@"set_session_tag: tag='%@'", tag);
	run_on_main(^{
		[noctua_sdk_class() setSessionTagWithTag:tag];
		trace(@"set_session_tag: sent to native SDK");
	});
}

String GodotNoctua::get_session_tag() {
	if (!require_initialized("get_session_tag")) {
		return String();
	}
	NSString *result = read_on_main(^{
		return [noctua_sdk_class() getSessionTags];
	});
	trace(@"get_session_tag -> '%@'", result);
	return to_godot(result);
}

void GodotNoctua::set_session_extra_params(Dictionary params) {
	if (!require_initialized("set_session_extra_params")) {
		return;
	}
	NSDictionary *payload = to_ns_dictionary(params);
	trace(@"set_session_extra_params: %@", payload);
	run_on_main(^{
		[noctua_sdk_class() setSessionExtraParamsWithPayload:payload];
		trace(@"set_session_extra_params: sent to native SDK");
	});
}

// ── Experiments ───────────────────────────────────────────────────────────────

void GodotNoctua::set_experiment(String experiment) {
	if (!require_initialized("set_experiment")) {
		return;
	}
	NSString *ns_experiment = to_ns(experiment);
	trace(@"set_experiment: experiment='%@'", ns_experiment);
	run_on_main(^{
		[noctua_sdk_class() setExperimentWithExperiment:ns_experiment];
		trace(@"set_experiment: sent to native SDK");
	});
}

String GodotNoctua::get_experiment() {
	if (!require_initialized("get_experiment")) {
		return String();
	}
	NSString *result = read_on_main(^{
		return [noctua_sdk_class() getExperiment];
	});
	trace(@"get_experiment -> '%@'", result);
	return to_godot(result);
}

void GodotNoctua::set_general_experiment(String experiment) {
	if (!require_initialized("set_general_experiment")) {
		return;
	}
	NSString *ns_experiment = to_ns(experiment);
	trace(@"set_general_experiment: experiment='%@'", ns_experiment);
	run_on_main(^{
		[noctua_sdk_class() setGeneralExperimentWithExperiment:ns_experiment];
		trace(@"set_general_experiment: sent to native SDK");
	});
}

String GodotNoctua::get_general_experiment(String key) {
	if (!require_initialized("get_general_experiment")) {
		return String();
	}
	NSString *ns_key = to_ns(key);
	NSString *result = read_on_main(^{
		return [noctua_sdk_class() getGeneralExperimentWithExperimentKey:ns_key];
	});
	trace(@"get_general_experiment: key='%@' -> '%@'", ns_key, result);
	return to_godot(result);
}

// ── Network State ─────────────────────────────────────────────────────────────

void GodotNoctua::on_online() {
	if (!require_initialized("on_online")) {
		return;
	}
	run_on_main(^{
		[noctua_sdk_class() onOnline];
		trace(@"on_online: sent to native SDK");
	});
}

void GodotNoctua::on_offline() {
	if (!require_initialized("on_offline")) {
		return;
	}
	run_on_main(^{
		[noctua_sdk_class() onOffline];
		trace(@"on_offline: sent to native SDK");
	});
}

// ── Bindings ──────────────────────────────────────────────────────────────────

void GodotNoctua::_bind_methods() {
	ClassDB::bind_method(D_METHOD("track_event", "event", "params"), &GodotNoctua::track_event);
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

	ClassDB::bind_method(D_METHOD("is_initialized"), &GodotNoctua::is_initialized);
	ClassDB::bind_method(D_METHOD("get_init_error"), &GodotNoctua::get_init_error);
	ClassDB::bind_method(D_METHOD("is_sandbox_enabled"), &GodotNoctua::is_sandbox_enabled);
}
