package com.slabgames.noctua;

import static java.util.Collections.emptyList;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;
import android.view.View;

import java.util.HashMap;
import java.util.Objects;

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
     * Required constructor — called by the Godot plugin loader.
     *
     * @param godot the Godot engine instance provided by the loader
     */
    public GodotNoctua(Godot godot) {
        super(godot);
        Log.i(TAG, "GodotNoctua plugin constructor called");
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
        Log.i(TAG, "onMainCreate: Initializing Noctua SDK...");
        try {
            Noctua.INSTANCE.init(
                activity,
                emptyList(),
                new NoctuaBillingConfig()
            );
            Noctua.INSTANCE.initApp();
            _inited = true;
            Log.i(TAG, "Noctua SDK initialized successfully (Koin started). Sandbox: " + com.noctuagames.sdk.utils.NoctuaLog.INSTANCE.getSandboxEnabled());
            
            try {
                Noctua.INSTANCE.getAdjustSdkVersion(version -> {
                    if (version != null) {
                        Log.i(TAG, "Adjust SDK is initialized. Version: " + version);
                    } else {
                        Log.w(TAG, "Adjust SDK is NOT initialized (AdjustService is null or disabled)");
                    }
                    return kotlin.Unit.INSTANCE;
                });
            } catch (Exception err) {
                Log.w(TAG, "Failed to get Adjust SDK version: " + err.getMessage());
            }
        } catch (Exception e) {
            Log.e(TAG, "Noctua SDK initialization failed: " + e.getMessage(), e);
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
            if (_inited) Noctua.INSTANCE.onResume();
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
            if (_inited) Noctua.INSTANCE.onPause();
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
            if (_inited) Noctua.INSTANCE.onDestroy();
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackCustomEvent(event, toSafeMap(params));
            Log.d(TAG, "track_event: " + event);
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackPurchase(
                orderId,
                Double.parseDouble(amount),
                currency,
                toSafeMap(payload)
            );
            Log.d(TAG, "track_purchase: order=" + orderId + " " + amount + " " + currency);
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.trackAdRevenue(
                adSource,
                Double.parseDouble(revenue),
                currency,
                toSafeMap(params)
            );
            Log.d(TAG, "track_ad_revenue: " + adSource + " " + revenue + " " + currency);
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setSessionTag(sessionName);
            Log.d(TAG, "set_session_tag: " + sessionName);
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
        if (!_inited) return "";
        return Noctua.INSTANCE.getSessionTag();
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setSessionExtraParams(toSafeMap(params));
            Log.d(TAG, "set_session_extra_params: " + params.size() + " keys");
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setExperiment(experiment);
            Log.d(TAG, "set_experiment: " + experiment);
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
        if (!_inited) return "";
        return Noctua.INSTANCE.getExperiment();
    }

    /**
     * Sets a general-purpose experiment value identified by a key.
     * Unlike {@link #set_experiment}, this supports multiple concurrent
     * experiment axes (e.g. UI experiment + monetisation experiment).
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.setGeneralExperiment(experiment);
            Log.d(TAG, "set_general_experiment: " + experiment);
        });
    }

    /**
     * Retrieves a general-purpose experiment value by its key.
     *
     * <p>Maps to: {@code Noctua.getGeneralExperiment(experimentKey)}
     *
     * <p>GDScript usage:
     * <pre>
     *   var value: String = noctua.get_general_experiment("pricing")
     * </pre>
     *
     * @param experimentKey key used when the experiment was stored via
     *                      {@link #set_general_experiment}
     * @return the experiment value, or an empty string if the SDK is not
     *         initialised or the key does not exist
     */
    @UsedByGodot
    public String get_general_experiment(final String experimentKey) {
        if (!_inited) return "";
        return Noctua.INSTANCE.getGeneralExperiment(experimentKey);
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.onOnline();
            Log.d(TAG, "on_online");
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
        if (!_inited) return;
        Objects.requireNonNull(getActivity()).runOnUiThread(() -> {
            Noctua.INSTANCE.onOffline();
            Log.d(TAG, "on_offline");
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
