extends Node

## Noctua SDK — GDScript bridge (autoload singleton).
##
## Auto-registered as [b]noctua[/b] in project.godot via:
## [code]noctua="*res://sdk/gd/noctua.gd"[/code]
##
## Wraps the GodotNoctua Android plugin (@UsedByGodot Java bridge) and
## mirrors the Noctua Native SDK public API in GDScript snake_case naming.
##
## [b]Initialisation:[/b] The SDK reads [code]noctuagg.json[/code] automatically
## in [code]GodotNoctua.onMainCreate()[/code]. No manual [code]init()[/code] call
## is needed from GDScript — just use any method below.
##
## [b]Desktop / editor fallback:[/b] When the plugin is absent (e.g. running in
## the Godot editor on desktop), all methods are no-ops and a warning is printed.
##
## Native SDK reference:
## https://github.com/NoctuaLabs/noctua-native-sdk

var _noctua = null

func _ready() -> void:
	if Engine.has_singleton("GodotNoctua"):
		_noctua = Engine.get_singleton("GodotNoctua")
		print("Noctua: native SDK connected")
		# The native SDK initialises before any script runs. If it failed, every
		# call below is ignored, so say so here instead of failing silently.
		# Call directly: on Android, has_method() reports false for every plugin method.
		if not bool(_noctua.is_initialized()):
			push_error("Noctua: native SDK failed to initialise (%s). Every noctua call will be ignored. Is noctuagg.json in the export preset's include filter?" % _noctua.get_init_error())
		elif is_sandbox_enabled():
			print("Noctua: native SDK initialized (sandbox: detailed [sandbox] logs in logcat / Xcode console)")
	else:
		push_warning("Noctua plugin not found! Running without native SDK.")

## Returns [code]true[/code] when the native Noctua SDK initialised successfully.
##
## When [code]false[/code], every tracking call is ignored by the native plugin.
## Always [code]false[/code] in the editor, where no native plugin is loaded.
##
## [b]Example:[/b]
## [codeblock]
## if not noctua.is_initialized():
##     push_warning("Analytics disabled: " + noctua.get_init_error())
## [/codeblock]
func is_initialized() -> bool:
	if _noctua != null:
		return bool(_noctua.is_initialized())
	return false

## Returns [code]true[/code] when [code]noctuagg.json[/code] has
## [code]"sandboxEnabled": true[/code]. The native plugin then logs every step from
## init to each tracking call, prefixed [code][sandbox][/code]. Errors are always logged.
func is_sandbox_enabled() -> bool:
	if _noctua != null:
		return bool(_noctua.is_sandbox_enabled())
	return false

## Returns why the native SDK failed to initialise, or [code]""[/code] when it
## succeeded or no native plugin is loaded.
func get_init_error() -> String:
	if _noctua != null:
		return str(_noctua.get_init_error())
	return ""

# ── Event Tracking ────────────────────────────────────────────────────────────

## Tracks a named custom event with no extra payload.
##
## Maps to: [code]Noctua.trackCustomEvent(eventName, emptyMap)[/code]
##
## [b]Example:[/b]
## [codeblock]
## noctua.track_event("level_start")
## noctua.track_event("tutorial_end")
## [/codeblock]
##
## [param event] Name of the custom event.
func track_event(event: String) -> void:
	if _noctua != null:
		_noctua.track_event(event, {})

## Tracks a named custom event with an additional key-value payload.
##
## Maps to: [code]Noctua.trackCustomEvent(eventName, payload)[/code]
##
## [b]Example:[/b]
## [codeblock]
## noctua.track_event_with_params("level_end", {"score": "1200", "stars": "3"})
## [/codeblock]
##
## [param event]  Name of the custom event.
## [param params] Flat [Dictionary] of extra data attached to the event.
func track_event_with_params(event: String, params: Dictionary) -> void:
	if _noctua != null:
		_noctua.track_event(event, params)

# ── Revenue Tracking ──────────────────────────────────────────────────────────

## Tracks an in-app purchase (IAP) transaction.
##
## Maps to: [code]Noctua.trackPurchase(orderId, amount, currency, extraPayload)[/code]
##
## [b]Example:[/b]
## [codeblock]
## noctua.track_purchase("ORDER-12345", "4.99", "USD", {})
## noctua.track_purchase("ORDER-99999", "9.99", "USD", {"sku": "starter_pack"})
## [/codeblock]
##
## [param order_id] Unique order identifier from the payment provider.
## [param amount]   Purchase amount as a decimal [String] (e.g. [code]"4.99"[/code]).
## [param currency] ISO 4217 currency code (e.g. [code]"USD"[/code], [code]"IDR"[/code]).
## [param payload]  Optional flat [Dictionary] of extra data.
func track_purchase(order_id: String, amount: String, currency: String, payload: Dictionary) -> void:
	if _noctua != null:
		_noctua.track_purchase(order_id, amount, currency, payload)

## Tracks ad revenue received from a mediation network.
##
## Maps to: [code]Noctua.trackAdRevenue(source, revenue, currency, extraPayload)[/code]
##
## [b]Valid [param ad_source] values:[/b]
## [codeblock]
## "applovin_max_sdk"   # AppLovin MAX mediation
## "admob_sdk"          # Google AdMob
## [/codeblock]
## Any other value is silently ignored by the native SDK.
##
## [b]Example:[/b]
## [codeblock]
## noctua.track_ad_revenue("applovin_max_sdk", "0.0025", "USD", {})
## noctua.track_ad_revenue("admob_sdk", "0.001", "USD", {"ad_unit": "banner_main"})
## [/codeblock]
##
## [param ad_source] Mediation network identifier. Must be one of the values above.
## [param revenue]   Ad revenue amount as a decimal [String] (e.g. [code]"0.0025"[/code]).
## [param currency]  ISO 4217 currency code — typically [code]"USD"[/code].
## [param params]    Optional flat [Dictionary] of extra data.
func track_ad_revenue(ad_source: String, revenue: String, currency: String, params: Dictionary) -> void:
	if _noctua != null:
		_noctua.track_ad_revenue(ad_source, revenue, currency, params)

# ── Session ───────────────────────────────────────────────────────────────────

## Tags the current analytics session for segmentation in the dashboard.
##
## Maps to: [code]Noctua.setSessionTag(tag)[/code]
##
## Call this whenever the player enters a meaningful game state so events
## can be grouped by session context (e.g. tutorial, PvP match, idle farming).
##
## [b]Example:[/b]
## [codeblock]
## noctua.set_session_tag("main_gameplay")
## noctua.set_session_tag("tutorial")
## [/codeblock]
##
## [param session_name] Arbitrary tag string (e.g. [code]"pvp_match"[/code]).
func set_session_tag(session_name: String) -> void:
	if _noctua != null:
		_noctua.set_session_tag(session_name)

## Returns the tag currently applied to the analytics session.
##
## Maps to: [code]Noctua.getSessionTag()[/code]
##
## [b]Example:[/b]
## [codeblock]
## var tag: String = noctua.get_session_tag()
## [/codeblock]
##
## [return] The current session tag, or [code]""[/code] if none has been set.
func get_session_tag() -> String:
	if _noctua != null:
		return _noctua.get_session_tag()
	return ""

## Attaches persistent key-value metadata to every subsequent session event.
##
## Maps to: [code]Noctua.setSessionExtraParams(extraParams)[/code]
##
## Useful for passing player state (level, class, server) without repeating
## it in every individual event payload.
##
## [b]Example:[/b]
## [codeblock]
## noctua.set_session_extra_params({"player_level": "42", "region": "SEA"})
## [/codeblock]
##
## [param params] Flat [Dictionary] of metadata. Values are coerced to strings.
func set_session_extra_params(params: Dictionary) -> void:
	if _noctua != null:
		_noctua.set_session_extra_params(params)

# ── Experiments ───────────────────────────────────────────────────────────────

## Assigns this session to an A/B experiment variant.
##
## Maps to: [code]Noctua.setExperiment(experiment)[/code]
##
## The value is attached to all subsequent events so results can be segmented
## by variant in the analytics dashboard.
##
## [b]Example:[/b]
## [codeblock]
## noctua.set_experiment("new_ui_v2")
## [/codeblock]
##
## [param experiment] Variant identifier (e.g. [code]"control"[/code], [code]"variant_a"[/code]).
func set_experiment(experiment: String) -> void:
	if _noctua != null:
		_noctua.set_experiment(experiment)

## Returns the A/B experiment variant assigned to the current session.
##
## Maps to: [code]Noctua.getExperiment()[/code]
##
## [b]Example:[/b]
## [codeblock]
## var bucket: String = noctua.get_experiment()
## [/codeblock]
##
## [return] The current experiment variant, or [code]""[/code] if none is set.
func get_experiment() -> String:
	if _noctua != null:
		return _noctua.get_experiment()
	return ""

## Sets a general-purpose experiment value.
##
## Maps to: [code]Noctua.setGeneralExperiment(experiment)[/code]
##
## Supports multiple concurrent experiment axes unlike [method set_experiment]
## which tracks a single experiment slot.
##
## [b]Example:[/b]
## [codeblock]
## noctua.set_general_experiment("pricing_v3")
## [/codeblock]
##
## [param experiment] Experiment value to store.
func set_general_experiment(experiment: String) -> void:
	if _noctua != null:
		_noctua.set_general_experiment(experiment)

## Retrieves a general-purpose experiment value by its key.
##
## Maps to: [code]Noctua.getGeneralExperiment(experimentKey)[/code]
##
## [b]Example:[/b]
## [codeblock]
## var value: String = noctua.get_general_experiment("pricing")
## [/codeblock]
##
## [param key]    Key used when the experiment was stored via [method set_general_experiment].
## [return]       The stored experiment value, or [code]""[/code] if not found.
func get_general_experiment(key: String) -> String:
	if _noctua != null:
		return _noctua.get_general_experiment(key)
	return ""

# ── Network state ─────────────────────────────────────────────────────────────

## Notifies the SDK that the device has regained network connectivity.
##
## Maps to: [code]Noctua.onOnline()[/code]
##
## The SDK will retry any events queued while the device was offline.
## Call this from a network-monitoring script when connectivity is restored.
##
## [b]Example:[/b]
## [codeblock]
## func _on_network_restored() -> void:
##     noctua.on_online()
## [/codeblock]
func on_online() -> void:
	if _noctua != null:
		_noctua.on_online()

## Notifies the SDK that the device has lost network connectivity.
##
## Maps to: [code]Noctua.onOffline()[/code]
##
## The SDK switches to offline-queue mode and stops attempting to send
## events until [method on_online] is called.
##
## [b]Example:[/b]
## [codeblock]
## func _on_network_lost() -> void:
##     noctua.on_offline()
## [/codeblock]
func on_offline() -> void:
	if _noctua != null:
		_noctua.on_offline()
