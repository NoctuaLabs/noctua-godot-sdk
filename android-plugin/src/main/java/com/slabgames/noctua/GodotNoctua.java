package com.slabgames.noctua;

import static java.util.Collections.emptyList;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;
import android.view.View;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import org.godotengine.godot.Dictionary;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import com.noctuagames.sdk.Noctua;
import com.noctuagames.sdk.models.NoctuaBillingConfig;

/**
 * Godot 3.x Android plugin that bridges GDScript to the Noctua Native SDK.
 *
 * <p>Architecture:
 * <pre>
 *   GDScript (noctua.gd autoload)
 *       → GodotNoctua (@UsedByGodot methods, runs on UI thread)
 *           → Noctua.INSTANCE (Kotlin object singleton)
 * </pre>
 *
 * <p>Initialisation:
 * The SDK reads {@code noctuagg.json} from the APK's {@code assets/} folder
 * automatically in {@link #onMainCreate}. No token or config is required from
 * GDScript — place {@code noctuagg.json} in the project root before exporting.
 *
 * <p>Threading:
 * All Noctua SDK calls are dispatched to the UI thread via
 * {@code Activity.runOnUiThread()} because the SDK internally uses Android UI
 * components (dialogs, billing flows, etc.).
 *
 * <p>Native SDK reference:
 * <a href="https://github.com/NoctuaLabs/noctua-native-sdk">noctua-native-sdk</a>
 */
public class GodotNoctua extends GodotPlugin {

    private static final String TAG = GodotNoctua.class.getName();

    /** {@code true} after {@link Noctua#init} completes successfully. */
    private boolean _inited = false;

    /**
     * Detailed trace logging, on only when {@code noctuagg.json} has
     * {@code "sandboxEnabled": true}. Errors and warnings are always logged.
     */
    private boolean _sandbox = false;

    /** Why the SDK is not initialised; empty once initialisation succeeded. */
    private String _initError = "not initialized yet: onMainCreate has not run";

    /** A plain decimal: optional sign, digits with an optional fraction, optional exponent. */
    private static final java.util.regex.Pattern DECIMAL =
            java.util.regex.Pattern.compile("[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?");

    /**
     * Values a setter has queued to the UI thread but the native SDK has not applied yet.
     * Getters return these first, so a read right after a write sees the new value
     * (setters are asynchronous, getters are not). Keys: see {@link #PENDING_SESSION_TAG}.
     */
    private final Map<String, String> _pending = new ConcurrentHashMap<>();
    private static final String PENDING_SESSION_TAG = "session_tag";
    private static final String PENDING_EXPERIMENT = "experiment";
    /** Prefix + key; the native one-argument setGeneralExperiment stores the value as its own key. */
    private static final String PENDING_GENERAL_EXPERIMENT = "general_experiment:";

    /** Methods already warned about being called before a successful init (warn once each). */
    private final Set<String> _warnedNotInitialized = Collections.synchronizedSet(new HashSet<>());

    /**
     * Required constructor — called by the Godot plugin loader.
     *
     * @param godot the Godot engine instance provided by the loader
     */
    public GodotNoctua(Godot godot) {
        super(godot);
    }

    /**
     * Returns the plugin name as registered in {@code GodotNoctua.gdap}.
     * GDScript accesses this plugin via {@code Engine.get_singleton("GodotNoctua")}.
     *
     * @return {@code "GodotNoctua"}
     */
    @Override
    public String getPluginName() {
        return "GodotNoctua";
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /**
     * Called when the Godot activity is first created.
     * Initialises the Noctua SDK by reading {@code noctuagg.json} from APK assets.
     *
     * <p>Must run on the UI thread because {@link Noctua#init} internally starts
     * Firebase, Adjust, and other Android SDK components.
     *
     * @param activity the host {@link Activity}; passed directly to
     *                 {@link Noctua#init} (the SDK casts it to {@code Activity})
     * @return {@code null} — this plugin adds no overlay view
     */
    @Override
    public View onMainCreate(Activity activity) {
        final long started = System.currentTimeMillis();
        _sandbox = readSandboxFlag(activity);
        trace("init 1/4: start (noctuagg.json sandboxEnabled=true, Godot plugin GodotNoctua)");
        try {
            Noctua.INSTANCE.init(
                activity,
                emptyList(),
                new NoctuaBillingConfig()
            );
            trace("init 2/4: Noctua.init() done - config loaded, services created");
            startKoinIfNeeded();
            _inited = true;
            _initError = "";
            // The native SDK's own flag is authoritative (it can be overridden at runtime).
            _sandbox = com.noctuagames.sdk.utils.NoctuaLog.INSTANCE.getSandboxEnabled();
            Log.i(TAG, "Noctua SDK initialized (sandbox=" + _sandbox + ")");
            trace("init 4/4: complete in " + (System.currentTimeMillis() - started) + " ms - tracking calls are now accepted");

            try {
                Noctua.INSTANCE.getAdjustSdkVersion(version -> {
                    if (version != null) {
                        trace("adjust: initialized, SDK version " + version);
                    } else {
                        Log.w(TAG, "Adjust SDK is NOT initialized (AdjustService is null or disabled)");
                    }
                    return kotlin.Unit.INSTANCE;
                });
            } catch (Exception err) {
                Log.w(TAG, "Failed to get Adjust SDK version: " + err.getMessage());
            }
        } catch (Throwable e) {
            // Throwable, not Exception: a missing dependency surfaces as an Error
            // (e.g. NoClassDefFoundError) and must not leave the SDK silently uninitialised.
            _initError = e.getClass().getSimpleName() + ": " + e.getMessage();
            Log.e(TAG, "Noctua SDK initialization failed: " + e.getMessage()
                    + " (is noctuagg.json in the export preset's include filter?)", e);
            trace("init: FAILED after " + (System.currentTimeMillis() - started) + " ms - every tracking call will be ignored");
        }
        return null;
    }

    /**
     * Called when the Godot activity resumes from background.
     * Forwards to {@link Noctua#onResume()} so the SDK can restart
     * session timers and refresh attribution state.
     */
    @Override
    public void onMainResume() {
        super.onMainResume();
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            if (_inited) {
                Noctua.INSTANCE.onResume();
                trace("lifecycle: onResume forwarded to native SDK");
            }
        });
    }

    /**
     * Called when the Godot activity moves to the background.
     * Forwards to {@link Noctua#onPause()} so the SDK can flush pending
     * events and pause session timers.
     */
    @Override
    public void onMainPause() {
        super.onMainPause();
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            if (_inited) {
                Noctua.INSTANCE.onPause();
                trace("lifecycle: onPause forwarded to native SDK");
            }
        });
    }

    /**
     * Called when the Godot activity is destroyed.
     * Forwards to {@link Noctua#onDestroy()} so the SDK can release
     * resources (billing connections, Firebase listeners, etc.).
     */
    @Override
    public void onMainDestroy() {
        super.onMainDestroy();
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            if (_inited) {
                Noctua.INSTANCE.onDestroy();
                trace("lifecycle: onDestroy forwarded to native SDK");
            }
        });
    }

    // ── Event Tracking ────────────────────────────────────────────────────────

    /**
     * Tracks a named custom event with an optional key-value payload.
     *
     * <p>Maps to: {@code Noctua.trackCustomEvent(eventName, payload)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.track_event("level_start")
     *   noctua.track_event_with_params("level_end", {"score": 1200})
     * </pre>
     *
     * @param event  name of the custom event (e.g. {@code "level_start"})
     * @param params optional flat key-value payload; pass {@code {}} if unused
     */
    @UsedByGodot
    public void track_event(final String event, final Dictionary params) {
        if (!requireInitialized("track_event")) return;
        trace("track_event: event='" + event + "' params=" + toSafeMap(params));
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackCustomEvent(event, toSafeMap(params));
            trace("track_event: sent to native SDK");
        });
    }

    /**
     * Tracks an in-app purchase (IAP) transaction.
     *
     * <p>Maps to: {@code Noctua.trackPurchase(orderId, amount, currency, extraPayload)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.track_purchase("ORDER-12345", "4.99", "USD", {})
     * </pre>
     *
     * @param orderId  unique order identifier from the payment provider
     * @param amount   purchase amount as a decimal string (e.g. {@code "4.99"});
     *                 converted to {@code Double} before calling the native SDK
     * @param currency ISO 4217 currency code (e.g. {@code "USD"})
     * @param payload  optional flat key-value payload; pass {@code {}} if unused
     */
    @UsedByGodot
    public void track_purchase(final String orderId, final String amount,
                               final String currency, final Dictionary payload) {
        if (!requireInitialized("track_purchase")) return;
        // Parse here, on the caller's thread: an invalid value used to throw
        // NumberFormatException inside the UI-thread Runnable and crash the app.
        final Double value = parseAmount(amount);
        if (value == null) {
            Log.e(TAG, "track_purchase: invalid purchase amount '" + amount + "' - expected a dot-decimal number such as \"4.99\". Not tracked.");
            return;
        }
        trace("track_purchase: order='" + orderId + "' amount='" + amount + "' (parsed " + value + ") currency='" + currency + "' payload=" + toSafeMap(payload));
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackPurchase(
                orderId,
                value,
                currency,
                toSafeMap(payload)
            );
            trace("track_purchase: sent to native SDK");
        });
    }

    /**
     * Tracks ad revenue received from a mediation network.
     *
     * <p>Maps to: {@code Noctua.trackAdRevenue(source, revenue, currency, extraPayload)}
     *
     * <p><b>Valid {@code adSource} values:</b>
     * <ul>
     *   <li>{@code "applovin_max_sdk"} — AppLovin MAX mediation</li>
     *   <li>{@code "admob_sdk"}        — Google AdMob</li>
     * </ul>
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.track_ad_revenue("applovin_max_sdk", "0.0025", "USD", {})
     *   noctua.track_ad_revenue("admob_sdk", "0.001", "USD", {})
     * </pre>
     *
     * @param adSource mediation network identifier; must be one of the values
     *                 listed above — other values are silently ignored by the SDK
     * @param revenue  ad revenue amount as a decimal string (e.g. {@code "0.0025"});
     *                 converted to {@code Double} before calling the native SDK
     * @param currency ISO 4217 currency code — typically {@code "USD"}
     * @param params   optional flat key-value payload; pass {@code {}} if unused
     */
    @UsedByGodot
    public void track_ad_revenue(final String adSource, final String revenue,
                                 final String currency, final Dictionary params) {
        if (!requireInitialized("track_ad_revenue")) return;
        // Parse here, on the caller's thread: an invalid value used to throw
        // NumberFormatException inside the UI-thread Runnable and crash the app.
        final Double value = parseAmount(revenue);
        if (value == null) {
            Log.e(TAG, "track_ad_revenue: invalid ad revenue '" + revenue + "' - expected a dot-decimal number such as \"4.99\". Not tracked.");
            return;
        }
        trace("track_ad_revenue: source='" + adSource + "' revenue='" + revenue + "' (parsed " + value + ") currency='" + currency + "' params=" + toSafeMap(params));
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackAdRevenue(
                adSource,
                value,
                currency,
                toSafeMap(params)
            );
            trace("track_ad_revenue: sent to native SDK");
        });
    }

    // ── Session ───────────────────────────────────────────────────────────────

    /**
     * Tags the current analytics session for segmentation.
     *
     * <p>Maps to: {@code Noctua.setSessionTag(tag)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.set_session_tag("main_gameplay")
     * </pre>
     *
     * @param sessionName arbitrary tag string used to segment sessions in the
     *                    analytics dashboard (e.g. {@code "tutorial"},
     *                    {@code "pvp_match"}, {@code "main_gameplay"})
     */
    @UsedByGodot
    public void set_session_tag(final String sessionName) {
        if (!requireInitialized("set_session_tag")) return;
        trace("set_session_tag: tag='" + sessionName + "'");
        _pending.put(PENDING_SESSION_TAG, sessionName);
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setSessionTag(sessionName);
            _pending.remove(PENDING_SESSION_TAG, sessionName);
            trace("set_session_tag: sent to native SDK");
        });
    }

    /**
     * Returns the tag applied to the current analytics session.
     *
     * <p>Maps to: {@code Noctua.getSessionTag()}
     *
     * <p>GDScript usage:
     * <pre>
     *   var tag: String = noctua.get_session_tag()
     * </pre>
     *
     * @return the current session tag, or an empty string if the SDK is not
     *         yet initialised or no tag has been set
     */
    @UsedByGodot
    public String get_session_tag() {
        if (!requireInitialized("get_session_tag")) return "";
        String pending = _pending.get(PENDING_SESSION_TAG);
        String result = pending != null ? pending : Noctua.INSTANCE.getSessionTag();
        trace("get_session_tag -> '" + result + "'" + (pending != null ? " (queued, not yet applied)" : ""));
        return result;
    }

    /**
     * Attaches extra key-value metadata to every subsequent session event.
     * Useful for passing player state (level, character class, server region)
     * without repeating it in every individual event payload.
     *
     * <p>Maps to: {@code Noctua.setSessionExtraParams(extraParams)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.set_session_extra_params({"player_level": "42", "region": "SEA"})
     * </pre>
     *
     * @param params flat {@code String → String} dictionary of metadata;
     *               values are coerced to strings by {@link #toSafeMap}
     */
    @UsedByGodot
    public void set_session_extra_params(final Dictionary params) {
        if (!requireInitialized("set_session_extra_params")) return;
        trace("set_session_extra_params: " + toSafeMap(params));
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setSessionExtraParams(toSafeMap(params));
            trace("set_session_extra_params: sent to native SDK");
        });
    }

    // ── Experiments ───────────────────────────────────────────────────────────

    /**
     * Assigns this session to an A/B experiment bucket.
     * The value is attached to all subsequent events so results can be
     * segmented by experiment variant in the analytics dashboard.
     *
     * <p>Maps to: {@code Noctua.setExperiment(experiment)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.set_experiment("new_ui_v2")
     * </pre>
     *
     * @param experiment experiment variant identifier
     *                   (e.g. {@code "control"}, {@code "variant_a"})
     */
    @UsedByGodot
    public void set_experiment(final String experiment) {
        if (!requireInitialized("set_experiment")) return;
        trace("set_experiment: experiment='" + experiment + "'");
        _pending.put(PENDING_EXPERIMENT, experiment);
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setExperiment(experiment);
            _pending.remove(PENDING_EXPERIMENT, experiment);
            trace("set_experiment: sent to native SDK");
        });
    }

    /**
     * Returns the A/B experiment bucket assigned to the current session.
     *
     * <p>Maps to: {@code Noctua.getExperiment()}
     *
     * <p>GDScript usage:
     * <pre>
     *   var bucket: String = noctua.get_experiment()
     * </pre>
     *
     * @return the current experiment variant string, or an empty string if
     *         the SDK is not initialised or no experiment has been set
     */
    @UsedByGodot
    public String get_experiment() {
        if (!requireInitialized("get_experiment")) return "";
        String pending = _pending.get(PENDING_EXPERIMENT);
        String result = pending != null ? pending : Noctua.INSTANCE.getExperiment();
        trace("get_experiment -> '" + result + "'" + (pending != null ? " (queued, not yet applied)" : ""));
        return result;
    }

    /**
     * Sets a general-purpose experiment value. The native SDK stores the value
     * as both key and value, so read it back with
     * {@code get_general_experiment(experiment)}. Unlike {@link #set_experiment},
     * this supports multiple concurrent experiment axes.
     *
     * <p>Maps to: {@code Noctua.setGeneralExperiment(experiment)}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.set_general_experiment("pricing_v3")
     * </pre>
     *
     * @param experiment experiment value to store
     */
    @UsedByGodot
    public void set_general_experiment(final String experiment) {
        if (!requireInitialized("set_general_experiment")) return;
        trace("set_general_experiment: experiment='" + experiment + "'");
        final String pendingKey = PENDING_GENERAL_EXPERIMENT + experiment;
        _pending.put(pendingKey, experiment);
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setGeneralExperiment(experiment);
            _pending.remove(pendingKey, experiment);
            trace("set_general_experiment: sent to native SDK");
        });
    }

    /**
     * Retrieves a general-purpose experiment value by its key.
     *
     * <p>Maps to: {@code Noctua.getGeneralExperiment(experimentKey)}
     *
     * <p>GDScript usage:
     * <pre>
     *   var value: String = noctua.get_general_experiment("pricing_v3")
     * </pre>
     *
     * @param experimentKey the value passed to {@link #set_general_experiment}
     *                      (the native SDK uses it as the key)
     * @return the experiment value, or an empty string if the SDK is not
     *         initialised or the key does not exist
     */
    @UsedByGodot
    public String get_general_experiment(final String experimentKey) {
        if (!requireInitialized("get_general_experiment")) return "";
        String pending = _pending.get(PENDING_GENERAL_EXPERIMENT + experimentKey);
        String result = pending != null ? pending : Noctua.INSTANCE.getGeneralExperiment(experimentKey);
        trace("get_general_experiment: key='" + experimentKey + "' -> '" + result + "'"
                + (pending != null ? " (queued, not yet applied)" : ""));
        return result;
    }

    // ── Network state ─────────────────────────────────────────────────────────

    /**
     * Notifies the SDK that the device has regained network connectivity.
     * The SDK will retry any queued events that failed to send while offline.
     *
     * <p>Maps to: {@code Noctua.onOnline()}
     *
     * <p>GDScript usage:
     * <pre>
     *   # Typically called from a network-monitor script:
     *   noctua.on_online()
     * </pre>
     */
    @UsedByGodot
    public void on_online() {
        if (!requireInitialized("on_online")) return;
        trace("on_online: device back online, flushing queued events");
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.onOnline();
            trace("on_online: sent to native SDK");
        });
    }

    /**
     * Notifies the SDK that the device has lost network connectivity.
     * The SDK will switch to offline-queue mode and stop attempting
     * to send events until {@link #on_online()} is called.
     *
     * <p>Maps to: {@code Noctua.onOffline()}
     *
     * <p>GDScript usage:
     * <pre>
     *   noctua.on_offline()
     * </pre>
     */
    @UsedByGodot
    public void on_offline() {
        if (!requireInitialized("on_offline")) return;
        trace("on_offline: device offline, queueing events");
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.onOffline();
            trace("on_offline: sent to native SDK");
        });
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /**
     * No-op implementation of the activity result callback.
     * Override if this plugin needs to handle {@code startActivityForResult} responses.
     *
     * @param requestCode request code passed to {@code startActivityForResult}
     * @param resultCode  result code returned by the launched activity
     * @param data        intent carrying result data, may be {@code null}
     */
    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
    }

    /**
     * Converts a Godot {@link Dictionary} to a {@code HashMap<String, Object>}
     * safe for passing to the Noctua SDK's {@code MutableMap<String, Any>} parameters.
     *
     * <p>Type mapping:
     * <table border="1">
     *   <tr><th>GDScript / Godot type</th><th>Java input</th><th>Mapped to</th></tr>
     *   <tr><td>int</td><td>{@link Integer}</td><td>{@link Long} (GDScript int is 64-bit)</td></tr>
     *   <tr><td>float</td><td>{@link Double}</td><td>{@link Double} (kept as-is for SDK compatibility)</td></tr>
     *   <tr><td>float (single)</td><td>{@link Float}</td><td>{@link Float} (passed through)</td></tr>
     *   <tr><td>int (64-bit)</td><td>{@link Long}</td><td>{@link Long} (passed through)</td></tr>
     *   <tr><td>bool</td><td>{@link Boolean}</td><td>{@link Boolean} (passed through)</td></tr>
     *   <tr><td>String</td><td>{@link String}</td><td>{@link String} (passed through)</td></tr>
     *   <tr><td>other</td><td>any</td><td>{@link String} via {@code toString()}</td></tr>
     *   <tr><td>null</td><td>{@code null}</td><td>key omitted from result</td></tr>
     * </table>
     *
     * <p><b>Note:</b> {@link Double} is intentionally kept as {@link Double} (not
     * downcast to {@link Float}) because the Noctua SDK may perform
     * {@code value as Double} casts internally, which would throw
     * {@link ClassCastException} on a {@link Float}.
     *
     * @param dict Godot Dictionary from GDScript; {@code null}-safe
     * @return a new {@link HashMap} with coerced values; never {@code null}
     */
    /**
     * Native SDK 0.35+ starts its Koin container at process start (InternalNoctuaApp),
     * so {@link Noctua#initApp()} then throws KoinApplicationAlreadyStartedException.
     * That used to abort initialisation after {@link Noctua#init} had already succeeded,
     * leaving every call ignored. Older native SDKs still need initApp(), so call it and
     * treat "already started" as success.
     */
    private void startKoinIfNeeded() {
        try {
            Noctua.INSTANCE.initApp();
            trace("init 3/4: Koin started by initApp() (older native SDK)");
        } catch (Throwable t) {
            if (!"KoinApplicationAlreadyStartedException".equals(t.getClass().getSimpleName())) {
                throw t;
            }
            trace("init 3/4: Koin already started by the native SDK at process start; initApp() skipped");
        }
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────

    /**
     * Whether the Noctua SDK initialised successfully. When {@code false}, every
     * tracking call is ignored (and warned about once per method).
     *
     * @return {@code true} after a successful {@link Noctua#init}
     */
    @UsedByGodot
    public boolean is_initialized() {
        return _inited;
    }

    /**
     * The reason initialisation failed, so GDScript can surface it.
     *
     * @return the failure reason, or an empty string once init succeeded
     */
    @UsedByGodot
    public String get_init_error() {
        return _initError;
    }

    /**
     * Whether detailed sandbox logging is on ({@code noctuagg.json} {@code sandboxEnabled}).
     *
     * @return {@code true} in sandbox builds
     */
    @UsedByGodot
    public boolean is_sandbox_enabled() {
        return _sandbox;
    }

    /** Detailed log line, emitted only when sandbox is enabled. */
    private void trace(String message) {
        if (_sandbox) Log.i(TAG, "[sandbox] " + message);
    }

    /**
     * Reads {@code noctua.sandboxEnabled} from the bundled {@code noctuagg.json}, so the
     * init steps can be traced before the native SDK has loaded its config. Any problem
     * (missing file, bad JSON) means "not sandbox"; init then reports the real error.
     */
    private static boolean readSandboxFlag(Activity activity) {
        try (java.io.InputStream in = activity.getAssets().open("noctuagg.json")) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            org.json.JSONObject root = new org.json.JSONObject(out.toString("UTF-8"));
            org.json.JSONObject noctua = root.optJSONObject("noctua");
            return noctua != null && noctua.optBoolean("sandboxEnabled", false);
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Returns {@code true} when the SDK is ready. Otherwise logs, once per method,
     * that the call was ignored, instead of dropping it silently.
     */
    private boolean requireInitialized(String method) {
        if (_inited) return true;
        if (_warnedNotInitialized.add(method)) {
            Log.w(TAG, method + " ignored: Noctua SDK is not initialized"
                    + " (" + _initError + ")"
                    + ". Check that noctuagg.json is in the export preset's include filter.");
        }
        return false;
    }

    /**
     * Parses a dot-decimal amount sent from GDScript as a String.
     *
     * @return the value, or {@code null} when it is empty, malformed, NaN or infinite
     */
    static Double parseAmount(String value) {
        if (value == null) return null;
        String trimmed = value.trim();
        // Plain decimals only, matching the iOS bridge: rejects "4,99", "4.99f", hex, "NaN".
        if (!DECIMAL.matcher(trimmed).matches()) return null;
        try {
            double parsed = Double.parseDouble(trimmed);
            return Double.isNaN(parsed) || Double.isInfinite(parsed) ? null : parsed;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private HashMap<String, Object> toSafeMap(Dictionary dict) {
        HashMap<String, Object> map = new HashMap<>();
        if (dict == null) return map;
        for (Object key : dict.keySet()) {
            Object value = dict.get(key);
            String k = String.valueOf(key);
            if (value instanceof Integer) {
                map.put(k, ((Integer) value).longValue());
            } else if (value instanceof Double
                    || value instanceof Float
                    || value instanceof Long
                    || value instanceof Boolean
                    || value instanceof String) {
                map.put(k, value);
            } else if (value != null) {
                map.put(k, value.toString());
            }
        }
        return map;
    }
}
