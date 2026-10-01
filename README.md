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
├── android-plugin/               # Gradle project — builds the Android bridge AAR
│   ├── src/main/java/…/GodotNoctua.java   # @UsedByGodot Java bridge (shared)
│   ├── src/godot3/AndroidManifest.xml     # Godot 3.x: plugin v1 meta-data
│   ├── src/godot4/AndroidManifest.xml     # Godot 4.x: plugin v2 meta-data
│   ├── libs/godot3/, libs/godot4/         # Godot engine AARs (not committed)
│   ├── GodotNoctua.godot3.gdap            # Godot 3.x plugin descriptor
│   └── build.gradle                       # godot3 / godot4 product flavors
├── ios-plugin/                   # Objective-C++ bridge for iOS (Godot 3.6 + 4.x)
│   ├── src/                      # GodotNoctua singleton + NoctuaSDK Obj-C view
│   ├── GodotNoctua.gdip          # iOS plugin descriptor
│   └── scripts/
│       ├── build.sh              # builds GodotNoctua.{debug,release}.xcframework
│       ├── setup_xcode.sh        # post-export: Podfile + pod install
│       └── noctua_xcode_project.rb
├── gd/
│   └── noctua.gd                 # GDScript autoload singleton (Android + iOS)
├── addon/godot3/, addon/godot4/  # Editor plugin scripts (packaged into the zips)
├── scripts/package_addon.sh      # Builds dist/GodotNoctua-godot<3|4>-<build>.zip
└── README.md
```

Sample projects using this SDK as a git submodule:
[noctua-godot-sample](https://github.com/NoctuaLabs/noctua-godot-sample) (Godot 4.6).

---

## Install as an editor plugin (recommended)

Godot plugin zips are built per engine line, because Godot 3 and 4 editor scripts
use different syntax:

| Engine | Zip |
|---|---|
| Godot 3.6.x | `GodotNoctua-godot3-<build>.zip` |
| Godot 4.2+ | `GodotNoctua-godot4-<build>.zip` |

1. Extract the zip into the project root, so you get `res://addons/GodotNoctua/`
   ([Installing plugins](https://docs.godotengine.org/en/3.6/tutorials/plugins/editor/installing_plugins.html)).
2. **Project > Project Settings > Plugins** → enable **GodotNoctua**.
3. Put `noctuagg.json` (and `google-services.json` / `GoogleService-Info.plist`) in the project root.
4. Check the editor **Output** panel and fix every `Noctua:` warning.

What the plugin does while enabled:

| Task | Godot 3.6 | Godot 4.2+ |
|---|---|---|
| Registers the `noctua` autoload (removed when disabled) | Yes | Yes |
| Android plugin | Copies `GodotNoctua.gdap` + AAR into `res://android/plugins/` | Injects the AAR and Maven dependency at export |
| iOS plugin | Copies it into `res://ios/plugins/GodotNoctua/` | Same |
| Adds `noctuagg.json` to every Android export (no include filter needed) | Yes | Yes |
| Warns about missing config and wrong export preset settings | Yes | Yes |

Native files are refreshed whenever the addon's `BUILD` stamp changes, so updating
is: delete `addons/GodotNoctua/`, extract the new zip, reopen the project.

You still set these in **Project > Export** yourself:

| Preset | Godot 3.6 | Godot 4.2+ |
|---|---|---|
| Android | Use Custom Build, Plugins > GodotNoctua, Min Sdk 23 | Use Gradle Build |
| iOS | Plugins > GodotNoctua | Plugins > GodotNoctua |

iOS still needs `ios-plugin/scripts/setup_xcode.sh` after every export (see [iOS Installation](#ios-installation)).

**Migrating from the submodule setup:** remove the `noctua` autoload that points to
`res://sdk/gd/noctua.gd` (the plugin warns while it exists), and delete any older
`.gdap` / `addons/GodotNoctua` copy you made by hand.

### Building the zips

```bash
(cd android-plugin && ./gradlew assembleGodot3Release assembleGodot4Release)
ios-plugin/scripts/build.sh 3.x && ios-plugin/scripts/build.sh 4.x
scripts/package_addon.sh 3.x      # -> dist/GodotNoctua-godot3-<build>.zip
scripts/package_addon.sh 4.x      # -> dist/GodotNoctua-godot4-<build>.zip
```

`<build>` is the SDK commit; `-dirty` is appended when the sources have uncommitted changes.

---

## Common Setup (manual / submodule)

Add this repository to the game as a submodule and register the autoload:

```bash
git submodule add https://github.com/NoctuaLabs/noctua-godot-sdk.git sdk
```

```ini
; project.godot
[autoload]
noctua="*res://sdk/gd/noctua.gd"
```

Place `noctuagg.json` in the project root (obtain it from the Noctua team; never
commit it). In **every** export preset, add it to **Resources → Filters to export
non-resource files** (`include_filter="noctuagg.json"`) — Godot only exports
`.json` files listed there, and the SDK cannot start without it. Also exclude the
SDK's build folders: `exclude_filter="sdk/android-plugin/*, sdk/ios-plugin/*"`.

---

## Android Installation

### 1. Build the AAR

Download the Godot engine AAR for your version from the
[Godot releases](https://github.com/godotengine/godot/releases) into
`android-plugin/libs/godot3/` or `libs/godot4/`, then (JDK 17):

```bash
cd sdk/android-plugin
./gradlew assembleGodot4Release     # Godot 4.2+
./gradlew assembleGodot3Release     # Godot 3.6
```

Copy `build/outputs/aar/GodotNoctua.godot4Release.aar` (or `godot3Release`) into the
game's `android/plugins/` folder, and place `google-services.json` in the project root.

### 2a. Godot 4.2+ — EditorExportPlugin

Godot 4 uses a v2 plugin: an editor addon that injects the AAR and Maven dependency
at export time. Create `res://addons/GodotNoctua/` with a `plugin.cfg`, an
`EditorPlugin` that calls `add_export_plugin()`, and this export plugin:

```gdscript
@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "GodotNoctua"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	# Use a res:// path — relative paths are resolved under res://addons/.
	return PackedStringArray(["res://android/plugins/GodotNoctua.godot4Release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(["com.noctuagames.sdk:noctua-android-sdk:0.35.1"])

func _get_android_dependencies_maven_repos(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(["https://dl.google.com/dl/android/maven2", "https://repo1.maven.org/maven2"])
```

The sample app contains a complete copy in
[`addons/GodotNoctua/`](https://github.com/NoctuaLabs/noctua-godot-sample/tree/main/addons/GodotNoctua).
Enable it in **Project → Project Settings → Plugins**, install the Android build
template, and tick **Use Gradle Build** in the Android preset.

### 2b. Godot 3.6 — .gdap descriptor

Copy `android-plugin/GodotNoctua.godot3.gdap` to `android/plugins/GodotNoctua.gdap`:

```ini
[config]
name="GodotNoctua"
binary_type="local"
binary="GodotNoctua.godot3Release.aar"

[dependencies]
remote=["com.noctuagames.sdk:noctua-android-sdk:0.35.1"]
custom_maven_repos=["https://dl.google.com/dl/android/maven2", "https://repo1.maven.org/maven2"]
```

Then in **Project → Export → Android**: enable **Use Custom Build**, tick
**Plugins → GodotNoctua**, set **Min SDK** to `23`. Godot 3.6.3's Gradle build
requires JDK 17 exactly (**Editor Settings → Export → Android → Java SDK Path**).

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

> Amounts are dot-decimal **Strings** (`"4.99"`). Both platforms accept plain decimals
> only; anything else (`"4,99"`, `""`, `"Rp 15.000"`, `"NaN"`) is rejected and logged, and
> the call is not tracked. Build the String from a number: `"%.2f" % price` or `str(value)`.

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

### Initialisation status

#### `is_initialized() -> bool`

`true` once the native SDK initialised. When `false`, every tracking call is ignored
(the native plugin logs that once per function). Always `false` in the editor.

#### `get_init_error() -> String`

Why initialisation failed, e.g. `IllegalArgumentException: Failed to load noctuagg.json`,
or `""` once it succeeded. `noctua.gd` also reports it with `push_error()` at start-up.

```gdscript
if not noctua.is_initialized():
    push_warning("Analytics disabled: " + noctua.get_init_error())
```

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

## Logging

| Level | Production (`sandboxEnabled: false`) | Sandbox (`sandboxEnabled: true`) |
|---|---|---|
| Errors and warnings (init failure, invalid amount, call ignored before init) | Logged | Logged |
| `Noctua SDK initialized (sandbox=...)` | Logged once | Logged once |
| Detailed trace, prefixed `[sandbox]` | Off | Every step from init to each tracking call |

The sandbox trace covers init (`init 1/4` … `4/4` with timing), lifecycle
forwarding, Adjust's version, and every call with its parameters, the parsed amount,
and `sent to native SDK`:

```
[sandbox] init 1/4: start (noctuagg.json sandboxEnabled=true, Godot plugin GodotNoctua)
[sandbox] init 2/4: Noctua.init() done - config loaded, services created
[sandbox] init 3/4: Koin already started by the native SDK at process start; initApp() skipped
Noctua SDK initialized (sandbox=true)
[sandbox] init 4/4: complete in 257 ms - tracking calls are now accepted
[sandbox] track_purchase: order='ORDER-1' amount='4.99' (parsed 4.99) currency='USD' payload={sku=test}
[sandbox] track_purchase: sent to native SDK
```

Android: `adb logcat -s com.slabgames.noctua.GodotNoctua` (stream it: some vendor
builds prune app logs, so `logcat -d` afterwards can miss them). iOS: Xcode console,
prefix `[GodotNoctua] [sandbox]`. `noctua.is_sandbox_enabled()` reports the mode.

---

## Credential Files

Both files are gitignored. Place them in the project root before exporting:

| File | Purpose |
|------|---------|
| `noctuagg.json` | Noctua SDK config — `clientId`, `gameId`, Firebase, Adjust keys |
| `google-services.json` | Firebase project config (Android) — required by Crashlytics and Analytics |
| `GoogleService-Info.plist` | Firebase project config (iOS) — added to the app bundle by `setup_xcode.sh` |

`noctuagg.json` reaches the app only through the export preset's include filter
(Android: packed into APK `assets/`) or, on iOS, through `setup_xcode.sh` (added to
the app bundle).

`google-services.json` must also be placed in the Android build template folder
(`android/build/`) for the `com.google.gms.google-services` Gradle plugin to process it.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Failed to load noctuagg.json` | File missing from APK assets | Add `noctuagg.json` to the export preset's include filter (see Common Setup) |
| Every call ignored; `noctua.get_init_error()` is `KoinApplicationAlreadyStartedException` | Plugin built before this fix, with native SDK 0.35+ (Koin is auto-started at process start) | Rebuild the AAR from current source |
| `push_error`: `Noctua: native SDK failed to initialise (...)` | See the reason in the message; usually `Failed to load noctuagg.json` | Add `noctuagg.json` to the export preset's include filter |
| `<method>: invalid purchase amount` / `invalid ad revenue` | Amount String is not a plain decimal | Pass `"%.2f" % price` or `str(value)`, never a display label |
| `Crashlytics build ID is missing` | `firebase-crashlytics-gradle` plugin not applied | Ensure `build.gradle` has the Crashlytics classpath + `apply plugin` |
| `Invalid plugin config file` | AAR missing from `android/plugins/` | Run `./gradlew assembleGodot3Release` and copy the AAR |
| Godot 4: `Transform's input file does not exist: …/addons/android/plugins/…aar` | Relative path in `_get_android_libraries()` | Return a `res://android/plugins/…` path |
| `Invalid Java version` | Godot 3.6.2 requires Java 17 exactly | Set `JAVA_HOME` to JDK 17; `gradlew` auto-sets it if installed via Homebrew |
| `ClassCastException: InternalNoctuaApp cannot be cast to Activity` | `getApplicationContext()` passed to `Noctua.init()` | Pass `activity` directly (already fixed in current source) |
| iOS: `GodotNoctua: NoctuaSDK is not linked` | Pods not installed / `.xcodeproj` opened instead of `.xcworkspace` | Run `setup_xcode.sh`, open the `.xcworkspace` |
| iOS: `NoctuaSDK is missing +<selector>` | NoctuaSDK version changed its Obj-C API | Pin `NOCTUA_IOS_SDK_VERSION` to a supported version or update `noctua_sdk_api.h` |
| iOS: `building for 'iOS-simulator', but linking in dylib … built for 'iOS'` | Godot's recursive `$(PROJECT_DIR)/**` search path reached `Pods/` | Re-run `setup_xcode.sh` (it scopes the search paths) |
| iOS (Godot 3.6): black screen after `setup 0` | App launched while the device was locked/inactive — Godot 3 starts the engine only once the view is active | Unlock the device and relaunch |

---

## License

See [LICENSE](LICENSE).
