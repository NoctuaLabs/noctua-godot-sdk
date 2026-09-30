# Noctua SDK — Godot Plugin (Android + iOS)

GDScript bridge to the [Noctua Native SDK](https://github.com/NoctuaLabs/noctua-native-sdk) for Godot 3.6.x and 4.2+ projects on Android and iOS.

Provides analytics event tracking, IAP purchase tracking, ad revenue tracking, session management, and A/B experiment support — all callable from GDScript via a single `noctua` autoload singleton.

---

## Requirements

| Dependency | Version |
|------------|---------|
| Godot Engine | 3.6.x or 4.2+ |
| Android min SDK | 23 |
| iOS deployment target | 15.0 |
| Java (Android build only) | 17 |
| Xcode + CocoaPods (iOS only) | Xcode 16+, CocoaPods 1.16+ |
| Noctua Native SDK | `0.35.1+` (Android) · `0.40.1+` (iOS) |

---

## Project Structure

```
sdk/
├── android-plugin/               # Gradle project — builds the AAR bridge
│   ├── src/main/java/
│   │   └── com/slabgames/noctua/
│   │       └── GodotNoctua.java  # @UsedByGodot Java bridge
│   ├── libs/godot3/
│   │   └── godot-lib.3.6.2.stable.release.aar  # Godot engine AAR (not committed)
│   └── build.gradle
├── ios-plugin/                   # Objective-C++ bridge for iOS (Godot 3.6 + 4.x)
│   ├── src/                      # GodotNoctua singleton + NoctuaSDK Obj-C view
│   ├── GodotNoctua.gdip          # iOS plugin descriptor
│   └── scripts/
│       ├── build.sh              # builds GodotNoctua.{debug,release}.xcframework
│       ├── setup_xcode.sh        # post-export: Podfile + pod install
│       └── noctua_xcode_project.rb
├── gd/
│   └── noctua.gd                 # GDScript autoload singleton (Android + iOS)
└── README.md
```

---

## Android Installation

### 1. Copy credential files

These files contain secrets and are **not committed** to the repository. Copy them from your secure storage after cloning:

```bash
cp /path/to/secure/noctuagg.json     <godot-project-root>/noctuagg.json
cp /path/to/secure/google-services.json  <godot-project-root>/google-services.json
```

> The Noctua SDK reads `noctuagg.json` from the APK's `assets/` folder at runtime.  
> A Gradle task (`copyCredentialAssets`) copies it automatically during every build.

### 2. Build the AAR

```bash
cd sdk/android-plugin
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew assembleGodot3Release
```

Copy the output to the Godot project's plugin folder:

```bash
cp build/outputs/aar/GodotNoctua.godot3Release.aar \
   ../../android/plugins/GodotNoctua.godot3Release.aar
```

### 3. Configure the Godot project

The autoload is already registered in `project.godot`:

```ini
[autoload]
noctua="*res://sdk/gd/noctua.gd"
```

The plugin descriptor `android/plugins/GodotNoctua.gdap` must point to the AAR:

```ini
[config]
name="GodotNoctua"
binary_type="local"
binary="GodotNoctua.godot3Release.aar"

[dependencies]
remote=["com.noctuagames.sdk:noctua-android-sdk:0.35.1"]
custom_maven_repos=["https://dl.google.com/dl/android/maven2", "https://repo1.maven.org/maven2"]
```

### 4. Enable the plugin in Godot

> **Project → Export → Android → Plugins → GodotNoctua** ✓

Enable **Use Custom Build** and set **Min SDK** to `23`.

---

## iOS Installation

The iOS plugin registers the same `GodotNoctua` singleton as the Android plugin,
so `noctua.gd` and your game scripts work unchanged. NoctuaSDK (Swift) and its
dependencies (Adjust, Firebase, Facebook) are installed with CocoaPods **after**
each Godot export.

### 1. Build the plugin

```bash
python3 -m pip install --user scons      # once
sdk/ios-plugin/scripts/build.sh 4.x      # Godot 4.2+ (default headers: 4.6.1-stable)
sdk/ios-plugin/scripts/build.sh 3.x      # Godot 3.6 (default headers: 3.6.3-stable)
```

The first run clones the matching Godot source into `ios-plugin/.godot/` and
generates its headers (a few minutes). Output: `ios-plugin/bin/<3.x|4.x>/GodotNoctua/`.

### 2. Add it to the game

Copy `ios-plugin/bin/<3.x|4.x>/GodotNoctua/` to `res://ios/plugins/GodotNoctua/`, then in
**Project → Export → iOS**:

- tick **Plugins → GodotNoctua**
- set **Min iOS Version** to `15.0`, your **App Store Team ID** and **Bundle Identifier**
- Godot 4: tick **Export Project Only**
- Godot 3.6: the App Store icon (1024×1024) must be opaque or the export stops

Place `noctuagg.json` and `GoogleService-Info.plist` in the project root.

### 3. Export, then link NoctuaSDK

```bash
sdk/ios-plugin/scripts/setup_xcode.sh <exported-xcode-dir> <godot-project-dir>
```

Run it after every export, then open `<name>.xcworkspace` (not the `.xcodeproj`).
It copies the config files into the app bundle, writes a Podfile pinning
NoctuaSDK `0.40.1` (override with `NOCTUA_IOS_SDK_VERSION`), runs `pod install`
and fixes the Godot project's build settings for CocoaPods. It also adds a
`.gdignore` to the export folder so Godot never imports `Pods/`.

> Simulator: Godot's official iOS templates ship an x86_64-only simulator
> library, which iOS 26 simulators cannot run. Test on a device.

---

## API Reference

All methods are accessed via the `noctua` autoload singleton.  
When running in the Godot editor (no plugin loaded), all methods are **no-ops**.

---

### Event Tracking

#### `track_event(event: String) -> void`

Tracks a named custom event with no extra payload.

```gdscript
noctua.track_event("level_start")
noctua.track_event("tutorial_end")
noctua.track_event("achievement_unlocked")
```

Maps to: `Noctua.trackCustomEvent(eventName, emptyMap)`

---

#### `track_event_with_params(event: String, params: Dictionary) -> void`

Tracks a named custom event with an additional key-value payload.

```gdscript
noctua.track_event_with_params("level_end", {"score": "1200", "stars": "3"})
```

Maps to: `Noctua.trackCustomEvent(eventName, payload)`

---

### Revenue Tracking

#### `track_custom_event_with_revenue(event_name: String, revenue: float, currency: String = "USD", payload: Dictionary = {}) -> void`

Tracks a custom event that carries a monetary revenue value.

```gdscript
noctua.track_custom_event_with_revenue("purchase", 0.99, "USD")
noctua.track_custom_event_with_revenue("bundle_sale", 4.99, "USD", {"sku": "gems_500"})
```

Maps to: `Noctua.trackCustomEventWithRevenue(eventName, revenue, currency, payload)`

---

#### `track_purchase(order_id: String, amount: String, currency: String, payload: Dictionary) -> void`

Tracks an in-app purchase (IAP) transaction.

```gdscript
noctua.track_purchase("ORDER-12345", "4.99", "USD", {})
noctua.track_purchase("ORDER-99999", "9.99", "USD", {"sku": "starter_pack"})
```

Maps to: `Noctua.trackPurchase(orderId, amount, currency, extraPayload)`

---

#### `track_ad_revenue(ad_source: String, revenue: String, currency: String, params: Dictionary) -> void`

Tracks ad revenue received from a mediation network.

| `ad_source` value | Network |
|-------------------|---------|
| `"applovin_max_sdk"` | AppLovin MAX |
| `"admob_sdk"` | Google AdMob |

> Any other `ad_source` value is silently ignored by the native SDK.

```gdscript
noctua.track_ad_revenue("applovin_max_sdk", "0.0025", "USD", {})
noctua.track_ad_revenue("admob_sdk", "0.001", "USD", {"ad_unit": "banner_main"})
```

Maps to: `Noctua.trackAdRevenue(source, revenue, currency, extraPayload)`

---

### Session Management

#### `set_session_tag(session_name: String) -> void`

Tags the current analytics session for segmentation in the dashboard.  
Call this whenever the player enters a meaningful game state.

```gdscript
noctua.set_session_tag("main_gameplay")
noctua.set_session_tag("tutorial")
noctua.set_session_tag("pvp_match")
```

Maps to: `Noctua.setSessionTag(tag)`

---

#### `get_session_tag() -> String`

Returns the tag applied to the current session, or `""` if none is set.

```gdscript
var tag: String = noctua.get_session_tag()
```

Maps to: `Noctua.getSessionTag()`

---

#### `set_session_extra_params(params: Dictionary) -> void`

Attaches persistent key-value metadata to every subsequent session event.  
Useful for player state that applies to many events (level, region, character class).

```gdscript
noctua.set_session_extra_params({"player_level": "42", "region": "SEA"})
```

Maps to: `Noctua.setSessionExtraParams(extraParams)`

---

### A/B Experiments

#### `set_experiment(experiment: String) -> void`

Assigns this session to an A/B experiment variant.

```gdscript
noctua.set_experiment("new_ui_v2")
```

Maps to: `Noctua.setExperiment(experiment)`

---

#### `get_experiment() -> String`

Returns the current experiment variant, or `""` if none is set.

```gdscript
var bucket: String = noctua.get_experiment()
```

Maps to: `Noctua.getExperiment()`

---

#### `set_general_experiment(experiment: String) -> void`

Sets a general-purpose experiment value (supports multiple concurrent experiment axes).

```gdscript
noctua.set_general_experiment("pricing_v3")
```

Maps to: `Noctua.setGeneralExperiment(experiment)`

---

#### `get_general_experiment(key: String) -> String`

Retrieves a general-purpose experiment value by key, or `""` if not found.

```gdscript
var value: String = noctua.get_general_experiment("pricing")
```

Maps to: `Noctua.getGeneralExperiment(experimentKey)`

---

### Network State

#### `on_online() -> void`

Notifies the SDK that the device has regained network connectivity.  
The SDK retries any events queued while offline.

```gdscript
func _on_network_restored() -> void:
    noctua.on_online()
```

Maps to: `Noctua.onOnline()`

---

#### `on_offline() -> void`

Notifies the SDK that the device has lost network connectivity.  
The SDK switches to offline-queue mode until `on_online()` is called.

```gdscript
func _on_network_lost() -> void:
    noctua.on_offline()
```

Maps to: `Noctua.onOffline()`

---

## Architecture

```
GDScript (noctua.gd autoload)
    │  snake_case wrappers, null-safe, editor-friendly
    ▼
GodotNoctua.java  (@UsedByGodot, UI-thread dispatch)
    │  converts GDScript Dictionary → MutableMap<String, Any>
    │  converts String amounts → Double for SDK
    ▼
Noctua.INSTANCE  (Kotlin object singleton)
    │  reads noctuagg.json from APK assets
    │  manages Firebase, Adjust, session, billing
    ▼
Noctua Native SDK  (com.noctuagames.sdk:noctua-android-sdk)
```

On iOS the same `GodotNoctua` singleton is implemented in Objective-C++:

```
GDScript (noctua.gd autoload)
    ▼
GodotNoctua (ios-plugin/src/godot_noctua.mm, main-thread dispatch)
    │  converts Dictionary → NSDictionary, String amounts → double
    ▼
Noctua (NoctuaSDK Swift class, CocoaPods)
    │  resolved at runtime via NSClassFromString("NoctuaSDK.Noctua")
    │  reads noctuagg.json from the app bundle
    ▼
Adjust · Firebase · Facebook · Noctua tracker
```

The plugin binary does not link NoctuaSDK directly — it looks the class up at
start-up and checks every selector it uses, logging any mismatch. Upgrading the
iOS SDK is therefore a Podfile version bump, not a plugin rebuild.

### Type conversion — `GDScript → Java → Kotlin`

| GDScript type | Java (Dictionary value) | Passed to SDK |
|---------------|------------------------|---------------|
| `int` | `Integer` | `Long` (safe 64-bit upcast) |
| `float` | `Double` | `Double` (kept as-is) |
| `bool` | `Boolean` | `Boolean` |
| `String` | `String` | `String` |
| other | any | `toString()` |
| revenue/amount | `String` from GDScript | `Double.parseDouble()` in Java · `NSScanner` (locale-independent) on iOS |

---

## Credential Files

Both files are gitignored. Place them in the project root before exporting:

| File | Purpose |
|------|---------|
| `noctuagg.json` | Noctua SDK config — `clientId`, `gameId`, Firebase, Adjust keys |
| `google-services.json` | Firebase project config (Android) — required by Crashlytics and Analytics |
| `GoogleService-Info.plist` | Firebase project config (iOS) — added to the app bundle by `setup_xcode.sh` |

`noctuagg.json` is automatically copied to `android/build/assets/` by the
`copyCredentialAssets` Gradle task on every build.

`google-services.json` must be placed in `android/build/` for the
`com.google.gms.google-services` Gradle plugin to process it.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Failed to load noctuagg.json` | File missing from APK assets | Place `noctuagg.json` in project root; Gradle copies it automatically |
| `Crashlytics build ID is missing` | `firebase-crashlytics-gradle` plugin not applied | Ensure `build.gradle` has the Crashlytics classpath + `apply plugin` |
| `Invalid plugin config file` | AAR missing from `android/plugins/` | Run `./gradlew assembleGodot3Release` and copy the AAR |
| `Invalid Java version` | Godot 3.6.2 requires Java 17 exactly | Set `JAVA_HOME` to JDK 17; `gradlew` auto-sets it if installed via Homebrew |
| `ClassCastException: InternalNoctuaApp cannot be cast to Activity` | `getApplicationContext()` passed to `Noctua.init()` | Pass `activity` directly (already fixed in current source) |
| iOS: `GodotNoctua: NoctuaSDK is not linked` | Pods not installed / `.xcodeproj` opened instead of `.xcworkspace` | Run `setup_xcode.sh`, open the `.xcworkspace` |
| iOS: `NoctuaSDK is missing +<selector>` | NoctuaSDK version changed its Obj-C API | Pin `NOCTUA_IOS_SDK_VERSION` to a supported version or update `noctua_sdk_api.h` |
| iOS: `building for 'iOS-simulator', but linking in dylib … built for 'iOS'` | Godot's recursive `$(PROJECT_DIR)/**` search path reached `Pods/` | Re-run `setup_xcode.sh` (it scopes the search paths) |
| iOS (Godot 3.6): black screen after `setup 0` | App launched while the device was locked/inactive — Godot 3 starts the engine only once the view is active | Unlock the device and relaunch |

---

## License

See [LICENSE](LICENSE).
