# Pixel Framework build log

## Attempt 1 — m SettingsGoogle
- Error category: Soong global error (whole-tree analysis, not module-specific)
- Error: `module "smartspace-proto-java" already defined` and
  `module "smartspace-proto-lite-java" already defined`
  (frameworks/base/packages/SystemUI/proto/Android.bp vs
  vendor/pixel-framework/SystemUIGoogle/proto/Android.bp)
- Root cause: vendor/pixel-framework carries its own copy of the smartspace
  proto Java libraries, but this Android 17 tree's frameworks/base already
  defines the same two modules with byte-identical .proto sources (confirmed
  with `diff`, both files diff clean).
- Fix (inside vendor/pixel-framework): emptied
  vendor/pixel-framework/SystemUIGoogle/proto/Android.bp (removed both
  java_library module defs, left explanatory comment). SystemUIGoogle's own
  Android.bp already references "smartspace-proto-java" /
  "smartspace-proto-lite-java" as static_libs by name only, so it now binds
  to the frameworks/base-provided modules automatically.
- Status: fixed, rebuilt.

## Attempt 2 — m SettingsGoogle
- Error category: Soong error, "depends on undefined module"
- Error: `vendor/pixel-framework/SettingsGoogle/Android.bp:34:1:
  "SettingsGoogle-core" depends on undefined module "Settings_manifest"`
  (also used at line 109 by the "SettingsGoogle" android_app module).
- Investigated: packages/apps/Settings/Android.bp in this tree has no
  "Settings_manifest" filegroup (only "Settings_proguard_flags" at
  line 260-263 and no top-level `manifest:` property on the "Settings"
  android_app module — it just uses default manifest discovery). RisingOS's
  own Settings fork apparently adds this filegroup; this Mist-OS tree's
  Settings hasn't been hooked yet.
- Tried working around this purely inside vendor/pixel-framework: a
  filegroup here cannot point at
  packages/apps/Settings/AndroidManifest.xml via a "../" relative path —
  Soong's path validation explicitly rejects any source path that escapes
  the owning Android.bp's directory (build/soong/android/paths.go:2235,
  "Path is outside directory"). So there is no legal fix confined to
  vendor/pixel-framework; duplicating Settings' full AndroidManifest.xml
  into vendor/pixel-framework would just recreate the same
  divergence/maintenance risk as the smartspace-proto duplicate from
  Attempt 1, and is exactly the kind of dangerous stub the task rules say
  to avoid.
- OUT OF SCOPE change needed (report only, not applied):
  packages/apps/Settings/Android.bp — add
  `filegroup { name: "Settings_manifest", srcs: ["AndroidManifest.xml"] }`
  (same pattern as existing "Settings_proguard_flags" filegroup).
- Status: SettingsGoogle now blocked solely on this out-of-scope change.
  Moving on to SystemUIGoogle per procedure step 2.

## Attempt 3 — m SystemUIGoogle (confirms it also hits the whole-tree Soong
   block from Attempt 2, since Soong resolves the ENTIRE module graph in one
   pass regardless of the requested ninja target — a broken module anywhere
   in the tree blocks every `m` invocation)
- Error: identical `"SettingsGoogle-core" depends on undefined module
  "Settings_manifest"` Soong error as Attempt 2, even though SettingsGoogle
  was not requested.
- To get past this and actually reach SystemUIGoogle's own compile errors,
  temporarily set `enabled: false` on the "SettingsGoogle-core" and
  "SettingsGoogle" modules in
  vendor/pixel-framework/SettingsGoogle/Android.bp (backup kept at
  /tmp/claude-4392/pf/build/SettingsGoogle.Android.bp.orig). This is
  DIAGNOSTIC ONLY, clearly commented in the .bp file itself, and was
  reverted before returning to SettingsGoogle work (see Attempt 4).

## Attempt 4 — m SystemUIGoogle (with SettingsGoogle disabled, diagnostic)
- Soong analysis now succeeds; reached real javac/kotlinc compile errors in
  SystemUIGoogle-core. Per coordinator's updated priority, this module is
  NOT worth pursuing further: Mist's SystemUI-core already natively
  contains the entire com.google.android.systemui.smartspace package/API
  surface, and RisingOS's `sixteen`-branch SystemUIGoogle here is
  essentially only that smartspace integration — so the whole class tree
  is fighting a different, incompatible version of the same feature
  already built into this tree's SystemUI-core.
- Representative real errors (full log: /tmp/claude-4392/pf/build/SystemUIGoogle.log):
  - `SystemUIGoogleModule.java:206: error: method create in interface
    LogBufferFactory cannot be applied to given types; required:
    String,int,boolean,boolean,String found: String,int` — LogBufferFactory
    (frameworks/base SystemUI-core, package com.android.systemui.log)
    changed its `create()` signature (added enableThreshold/systemProperty
    params) since the RisingOS 16 QPR0 base this vendor tree was written
    against.
  - `DateSmartspaceDataProvider`, `WeatherSmartspaceDataProvider`,
    `BcSmartspaceDataProvider` (all in
    vendor/pixel-framework/SystemUIGoogle/src/com/google/android/systemui/smartspace/)
    are "not abstract and does not override abstract method
    getEventNotifier() in BcSmartspaceDataPlugin" — the
    BcSmartspaceDataPlugin interface (frameworks/base SystemUI-core
    smartspace plugin API) gained a new abstract member
    `getEventNotifier()` that this vendor code's implementations don't
    provide.
  - Dozens of further "method does not override or implement a method
    from a supertype", "cannot find symbol", and "incompatible types: bad
    type in conditional expression" errors across BcSmartspaceView.java,
    CardPagerAdapter.java, CardRecyclerViewAdapter.java,
    DateSmartspaceView.java, WeatherSmartspaceView.java,
    DefaultBcSmartspaceConfigProvider.java — all in the same
    smartspace/ package, all against SystemUI-core smartspace plugin
    classes that have diverged from what this RisingOS 16 QPR0 fork
    expects (42 distinct `error:` lines total).
- Decision (per coordinator): STOP iterating on SystemUIGoogle. Not worth
  chasing since the target functionality (smartspace) is natively covered
  by Mist's own SystemUI-core already. No further changes made to
  SystemUIGoogle or its submodules.
- Reverted the diagnostic `enabled: false` changes in
  vendor/pixel-framework/SettingsGoogle/Android.bp back to the real
  (blocked) state from Attempt 2, restoring from the .orig backup, so the
  tree reflects SettingsGoogle's genuine status going forward. All further
  effort redirected to SettingsGoogle per updated priority.

## Attempt 5 — m SettingsGoogle (diagnostic: temporary Settings_manifest
   stand-in, purely to see how far SettingsGoogle-core/SettingsGoogle get
   past the Attempt-2 blocker)
- Confirmed by reading packages/apps/Settings/Android.bp directly:
  "Settings-core" and the "Settings" android_app both have NO `manifest:`
  property at all (they rely on default AndroidManifest.xml discovery in
  their own directory, the real 6501-line packages/apps/Settings/
  AndroidManifest.xml). So `:Settings_manifest` in
  vendor/pixel-framework/SettingsGoogle/Android.bp is meant to be a
  filegroup, provided by a Settings-side hook commit, that exposes that
  same file under a stable name for forks like SettingsGoogle to consume
  as their base manifest. Confirms Attempt 2's diagnosis exactly; this is
  not a naming typo in vendor/pixel-framework (note there is already an
  unrelated, unused "SettingsGoogle_manifest" filegroup in this same file
  wrapping the small 376-line local delta AndroidManifest.xml — that one
  is NOT a substitute; using it instead of the real Settings manifest
  would silently drop hundreds of permission/activity/provider
  declarations, which is exactly the "dangerous stub" the task rules warn
  against).
- To surface further real errors, TEMPORARILY (diagnostic only, fully
  reverted afterward): copied packages/apps/Settings/AndroidManifest.xml
  verbatim to
  vendor/pixel-framework/SettingsGoogle/DIAG_TEMP_Settings_AndroidManifest.xml
  and added a temporary `filegroup { name: "Settings_manifest", srcs:
  ["DIAG_TEMP_Settings_AndroidManifest.xml"] }` to
  vendor/pixel-framework/SettingsGoogle/Android.bp. Rebuilt.
- Result: Soong analysis passed, and — importantly — **all Java/Kotlin
  compilation of SettingsGoogle-core and SettingsGoogle succeeded with no
  javac/kotlinc errors** (aapt2 resource compile also succeeded, only
  benign "removing resource ... without required default value" warnings
  for a handful of accessibility-gesture strings). The build only failed
  at the manifest-merger step:
  ```
  out/soong/.intermediates/vendor/pixel-framework/SettingsGoogle/SettingsGoogle/android_common/manifest_fixer/AndroidManifest.xml:154:18-53 Error:
      Attribute application@name value=(com.android.settings.SettingsApplication) from AndroidManifest.xml:154:18-53
      is also present at AndroidManifest.xml:171:461-556 value=(com.google.android.settings.generalaccess.SettingsGoogleGeneralAccessApplication).
      Suggestion: add 'tools:replace="android:name"' to <application> element at AndroidManifest.xml:154:5-4133:19 to override.
  ```
  i.e. the base Settings manifest declares
  `<application android:name="com.android.settings.SettingsApplication">`
  and vendor/pixel-framework/SettingsGoogle/AndroidManifest.xml (line 171,
  merged in via `additional_manifests`) declares
  `android:name="com.google.android.settings.generalaccess.SettingsGoogleGeneralAccessApplication"`
  on its own `<application>` tag without a `tools:replace="android:name"`
  attribute, so the manifest merger correctly refuses to pick a winner.
- **This IS a legitimate, in-scope, cheap fix** (not applied — see note
  below): add `tools:replace="android:name"` to the `<application>` tag at
  vendor/pixel-framework/SettingsGoogle/AndroidManifest.xml:171. The
  `xmlns:tools` namespace is already declared on the manifest root, and
  the rest of the file already uses `tools:replace="android:protectionLevel"`
  on several `<permission>` elements (same pattern), so this is
  idiomatic/consistent with the rest of the file, not a new pattern.
  **NOT applied and NOT rebuilt** because the coordinator instructed
  wrapping up before starting a new fix/build cycle; this is recorded here
  as the next concrete step for whoever picks this back up, rather than
  left undiscovered.
- Cleanup: removed
  vendor/pixel-framework/SettingsGoogle/DIAG_TEMP_Settings_AndroidManifest.xml
  and reverted vendor/pixel-framework/SettingsGoogle/Android.bp to the
  exact real (Attempt-2-blocked) content — diff against the Attempt-1
  backup confirms a clean revert. **Final on-disk state of
  vendor/pixel-framework: only the Attempt-1 smartspace-proto fix remains
  applied.** SettingsGoogle is genuinely blocked on the missing
  Settings_manifest filegroup in packages/apps/Settings/Android.bp until
  that lands (whereupon the tools:replace fix above will very likely be
  the *only* remaining blocker — no other errors were seen in this
  diagnostic pass, though aapt2/dexing/proguard stages beyond the manifest
  merge step were never reached and so are unverified).
- No build process left running; `fuser ~/mistos/out/.lock` empty,
  soong_ui/ninja process count 0.
