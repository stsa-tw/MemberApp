# MemberApp

STSA 新加坡台灣學生會員系統 — two native apps: [`ios/`](ios/) in SwiftUI and
[`android/`](android/) in Jetpack Compose.

They sign a member in against the STSA identity provider, show their electronic
member card, and surface events, partner offers and announcements. Same
backends, same OIDC client registration, same copy in both languages — the
platforms differ only where the platform does.

Originally implemented from the Claude Design prototype
[`STSA App.dc.html`](https://claude.ai/design/p/bfab5630-cb66-4104-a360-9eaf42c3ba8d?file=STSA+App.dc.html)
(21 screens). The prototype is a design reference only; nothing from it ships,
and the apps have since diverged from it wherever the real data disagreed.

## Requirements

**iOS**

- Xcode 26 / iOS 26 SDK
- Deployment target: iOS 26.0 — `TabView` renders the floating Liquid Glass tab
  bar natively on 26, and `tabViewBottomAccessory` is 26-only
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- One SPM dependency, resolved automatically on first open:
  [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) 1.7.6

**Android**

- JDK 21, Android SDK 37 (`compileSdk`/`targetSdk`), AGP 9.3 on Gradle 9.7
- `minSdk` 30 — `BiometricPrompt` only accepts `BIOMETRIC_STRONG or
  DEVICE_CREDENTIAL` from there, and that pairing is what makes the card gate
  fall back to the PIN instead of locking someone out
- Dependencies are in [`android/gradle/libs.versions.toml`](android/gradle/libs.versions.toml);
  the ones that carry weight are AppAuth-Android, androidx.biometric and ZXing

## Running

**iOS**

```bash
open ios/MemberApp.xcodeproj
```

Pick an iPhone simulator and run. Or from the command line:

```bash
xcodebuild -project ios/MemberApp.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Sign-in works in the simulator — the OIDC flow runs in
`ASWebAuthenticationSession` and the callback scheme is registered — but Face ID
does not, so the member card lock falls back to the simulator passcode
(Features → Face ID → Enrolled, then Matching Face).

**Android**

```bash
cd android && ./gradlew installDebug
```

Point `sdk.dir` at your SDK in `android/local.properties` (git-ignored) or set
`ANDROID_HOME`. Sign-in works on an emulator — AppAuth hands off to whichever
browser is installed — but biometrics do not exist until you enrol a fingerprint
in the emulator's settings, so the card gate falls through to the PIN.

## Backends

Both apps are clients for three services neither of them contains:

| Host | What it is | Auth |
|---|---|---|
| `idms.stsa.tw` | authentik — OIDC provider, and MembershipAPI at `/membership/api/` | Bearer token |
| `event.stsa.tw` | Indico — events, read via the public category export | none |
| `app.stsa.tw` | OAuth redirect bridge (see [`tools/oauth-bridge/`](tools/oauth-bridge/)) | n/a |

## Sign-in

OIDC authorization code + PKCE against the authentik tenant, driven by AppAuth
on both platforms. The details that are easy to get wrong are documented at
[AuthConfiguration.swift](ios/MemberApp/Auth/AuthConfiguration.swift) and
[AuthConfiguration.kt](android/app/src/main/java/tw/stsa/memberapp/auth/AuthConfiguration.kt),
which hold the same four values; the short version:

- The client is the **`membership`** provider — the same one the web card uses —
  not `stsa-membership-ios`. MembershipAPI pins `iss` and `aud` to a single
  registration and 401s tokens from the other one.
- It is a **public client**. There is no secret and none should be added; proof
  of possession is PKCE (S256), which AppAuth derives on its own.
- Endpoints come from discovery at `<issuer>/.well-known/openid-configuration`,
  never hardcoded — authentik moves them between releases.
- `offline_access` is what makes authentik return a refresh token. Without it
  the session dies with the 5-minute access token.

Redirect URI is `tw.stsa.membership://callback` on both, because authentik pins
it to the shared registration. iOS declares it in
[Config/Info.plist](ios/Config/Info.plist) and resumes the flow from
`.onOpenURL` in [MemberAppApp.swift](ios/MemberApp/App/MemberAppApp.swift);
Android sets the `appAuthRedirectScheme` manifest placeholder in
[app/build.gradle.kts](android/app/build.gradle.kts) and lets AppAuth's own
receiver activity return it through an activity result.

The browser is the other half of that: `ASWebAuthenticationSession` on iOS, a
Custom Tab on Android. Both keep the sign-in page inside the browser's session,
which is what makes SSO work. Never a `WKWebView` or a `WebView`.

### Token handling

Access tokens live five minutes, so **nothing ever holds one**.
[`AuthManager.accessToken()`](ios/MemberApp/Auth/AuthManager.swift) goes through
`OIDAuthState.performAction(freshTokens:)` on every call, and
[its Android twin](android/app/src/main/java/tw/stsa/memberapp/auth/AuthManager.kt)
through `AuthState.performActionWithFreshTokens`. Both return the cached token
while it is valid and silently redeem the refresh token when it is not. Use
`authorizedRequest(for:)` / `authorizedGet(_:)` to build outbound requests
rather than stashing a token anywhere.

The serialised auth state — which carries the 30-day refresh token — is the only
credential either app stores:

| | iOS | Android |
|---|---|---|
| Where | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Preferences, sealed with an AES-256-GCM key generated in the Android Keystore ([TokenStore.kt](android/app/src/main/java/tw/stsa/memberapp/auth/TokenStore.kt)) |
| Off-device | Excluded from backup and migration by the accessibility class | Excluded by [data_extraction_rules.xml](android/app/src/main/res/xml/data_extraction_rules.xml); the key is non-extractable regardless |

Profile claims and user preferences are not credentials and live in
UserDefaults / SharedPreferences, keyed on `sub`.

## Features

| Screen | State | Source of data |
|---|---|---|
| Welcome / sign-in | Done | authentik |
| Home — greeting, card banner, shortcuts, announcements | Done | announcements are a single hardcoded real notice |
| 會員卡 Member card | Done | MembershipAPI `get_code` |
| 活動 Events + detail | Done | Indico category export |
| 優惠 Deals + detail | Done | three hardcoded real partner offers |
| 我的 Account | Done | userinfo claims |
| 設定 Settings + 關於總會 | Done | UserDefaults, stsa.tw/about transcribed |
| 頻道 Channels | Done | UserDefaults — display preference, no push backend |
| 職缺 Jobs | Stub | none yet |

Every row is done on both platforms. The one remaining stub lives in
[Features/Placeholders.swift](ios/MemberApp/Features/Placeholders.swift) and
[JobsScreen.kt](android/app/src/main/java/tw/stsa/memberapp/feature/jobs/JobsScreen.kt).
Delete both as the real screen lands.

### Member card

The QR payload is `stsa$` + a code minted per request by MembershipAPI and held
in Redis for 300s. The card re-fetches every 250s to stay inside that window,
but only while it is on screen — there is no reason to keep a live credential
alive in someone's pocket. Screen brightness is raised while the card is up and
restored on dismiss.

Showing the card requires device-owner authentication — Face ID / Touch ID /
passcode via `LAContext`, fingerprint / screen lock via `BiometricPrompt` —
**on by default**. It is not a second login; it guards the one case the lock
screen does not cover, a phone handed over while already unlocked. Devices with
no passcode fall through rather than being locked out. The toggle is in 設定.

The QR itself is `CIQRCodeGenerator` on iOS and ZXing on Android, both at
correction level H, both drawn black-on-white in either appearance because
that is what scanners expect.

### Events

The Indico category export answers anonymously, so
[EventsStore](ios/MemberApp/Features/Events/EventsStore.swift) and
[its Android twin](android/app/src/main/java/tw/stsa/memberapp/feature/events/EventsStore.kt)
deliberately send no credentials — requiring a token would only make the tab
fail for no gain. Registration happens on Indico itself. Indico splits
timestamps into date/time/tz rather than emitting ISO 8601, and descriptions
arrive as HTML; both are handled in
[IndicoEvent](ios/MemberApp/Models/IndicoEvent.swift) and
[IndicoEvent.kt](android/app/src/main/java/tw/stsa/memberapp/model/IndicoEvent.kt).

## Layout

```
ios/
├── MemberApp/
│   ├── App/            MemberAppApp (composition root), RootView (auth gate + tabs),
│   │                   Session (navigation state), AppSettings (UserDefaults)
│   ├── Auth/           AuthConfiguration, AuthManager, Profile, Keychain, BiometricGate
│   ├── DesignSystem/   Theme (tokens, BrandButtonStyle), GroupedCard
│   ├── Models/         IndicoEvent, Deal, Announcement, Channel
│   ├── Features/       One folder per flow
│   │   ├── Onboarding/ Welcome
│   │   ├── Home/       Home, Announcement Detail
│   │   ├── Card/       Member Card, MembershipCodeStore, QRCode
│   │   ├── Deals/      Deals, Deal Detail
│   │   ├── Events/     Events, Event Detail, EventsStore
│   │   ├── Channels/   Channels
│   │   ├── Auth/       Account
│   │   ├── Settings/   Settings, About
│   │   └── Placeholders.swift   Jobs
│   └── Resources/      Assets.xcassets — AppIcon, AccentColor, STSA + partner logos
├── MemberAppTests/     Pure-logic tests
└── Config/             Info.plist (only the keys build settings cannot express)

android/app/src/main/
├── java/tw/stsa/memberapp/
│   ├── MemberApplication, MainActivity   Composition root and the one Activity
│   ├── app/            AppContainer (DI), AppSettings (SharedPreferences),
│   │                   Routes (navigation graph), RootScreen (auth gate + tabs)
│   ├── auth/           AuthConfiguration, AuthManager, Profile, TokenStore, BiometricGate
│   ├── designsystem/   Theme (tokens, M3 scheme), Components, ScreenScaffold
│   ├── model/          IndicoEvent, Deal, Announcement, Channel
│   ├── net/            Http — three GETs, no client library
│   └── feature/        One package per flow, mirroring ios/MemberApp/Features/
└── res/                values (zh-Hant) + values-en, brand assets, adaptive icon

tools/oauth-bridge/     Standalone OAuth redirect bridge — not part of either app
```

Shared state is created once — in `MemberAppApp` on iOS, in `AppContainer` on
Android — and injected: `.environment(…)` there, a `CompositionLocal` here.
Nothing owns a second copy of identity: `AuthManager.isLoggedIn` is the single
gate, which is what fixed a successful login leaving the app on the welcome
screen.

iOS has a `Session` object for navigation state; Android does not, because
`NavController` already is one and a parallel copy would be exactly the second
source of truth that bug came from.

`ios/MemberApp/` is a **file-system synchronized group**: any file added to the
folder is picked up by the target automatically. Create Swift files from the
command line or Finder and Xcode includes them — no target-membership step.

## Design notes

The two apps look like their platforms rather than like each other. That is the
deliberate part: the same reasoning produced different results because the
design systems differ.

The prototype's greys are literal transcriptions of Apple's semantic colours
(`rgba(60,60,67,.6)` → `.secondaryLabel`, `#f2f2f7` → `systemGroupedBackground`,
`rgba(118,118,128,.12)` → `tertiarySystemFill`). Those are used as semantic
colours on iOS rather than hardcoded hex, so Dark Mode and Increase Contrast
work. Android does the same thing with Material 3 roles: the greys come from the
colour scheme, and only the brand red is ours. Likewise the type ramp — the
standard iOS one there, Material's type scale here — so both get the reader's
font-size setting for free.

The Material scheme is written out from the brand red rather than produced by
`dynamicColorScheme()`. The member card is an identity document and the red is
what identifies it, so it does not get repainted to match somebody's wallpaper.

Two places where the platform had no equivalent:

- iOS puts the 會員卡 button beside the tab bar with `tabViewBottomAccessory`.
  Material has no such slot, and rebuilding one by hand would be a bar that is
  not a bar, so Android uses an extended FAB — always on screen across the tabs,
  one tap, out of the way on screens with their own primary action.
- iOS presents the card as a sheet; Android makes it a navigation destination,
  which is what you want for something held up to a scanner.

> [!NOTE]
> `AccentColor.colorset` currently holds `#C68578`, a muted rose, while its own
> comment, this README, `brandDeep` and `brandInk` all describe the brand red as
> `#EC3013`. The Android scheme is built from `#EC3013`. Whichever is right,
> they disagree today.

UI strings are Traditional Chinese, with English alongside: the source language
is zh-Hant on both platforms.
[Localizable.xcstrings](ios/MemberApp/Resources/Localizable.xcstrings) holds the
iOS catalogue; [values/strings.xml](android/app/src/main/res/values/strings.xml)
and [values-en/](android/app/src/main/res/values-en/strings.xml) hold the same
copy for Android. A string added to one belongs in the other. Partner offers and
announcements are the exception — that copy is the partners' own and is Chinese
only, so it lives in the model rather than in a resource file.

## OAuth redirect bridge

[`tools/oauth-bridge/`](tools/oauth-bridge/) holds a Cloudflare Worker and a
WordPress mu-plugin — same behaviour, deploy one. Indico only accepts `http(s)`
redirect URIs, so `tw.stsa.membership://callback` cannot be registered with it
directly; the bridge is registered instead and forwards to the app.

It is standalone infrastructure. Both apps currently authenticate against
authentik, not Indico, so neither depends on it yet. See
[its README](tools/oauth-bridge/README.md) for deployment and the caching
caveats, which matter — the response carries a one-time authorization code.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
