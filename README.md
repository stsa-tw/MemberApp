# MemberApp

STSA 新加坡台灣學生會員系統 — native SwiftUI iOS app.

The app signs a member in against the STSA identity provider, shows their
electronic member card, and surfaces events, partner offers and announcements.

Originally implemented from the Claude Design prototype
[`STSA App.dc.html`](https://claude.ai/design/p/bfab5630-cb66-4104-a360-9eaf42c3ba8d?file=STSA+App.dc.html)
(21 screens). The prototype is a design reference only; nothing from it ships,
and the app has since diverged from it wherever the real data disagreed.

## Requirements

- Xcode 26 / iOS 26 SDK
- Deployment target: iOS 26.0 — `TabView` renders the floating Liquid Glass tab
  bar natively on 26, and `tabViewBottomAccessory` is 26-only
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- One SPM dependency, resolved automatically on first open:
  [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) 1.7.6

## Running

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

## Backends

The app is a client for three services it does not contain:

| Host | What it is | Auth |
|---|---|---|
| `idms.stsa.tw` | authentik — OIDC provider, and MembershipAPI at `/membership/api/` | Bearer token |
| `event.stsa.tw` | Indico — events, read via the public category export | none |
| `app.stsa.tw` | OAuth redirect bridge (see [`tools/oauth-bridge/`](tools/oauth-bridge/)) | n/a |

## Sign-in

OIDC authorization code + PKCE against the authentik tenant, driven by AppAuth.
The details that are easy to get wrong are documented at
[AuthConfiguration.swift](ios/MemberApp/Auth/AuthConfiguration.swift); the short
version:

- The client is the **`membership`** provider — the same one the web card uses —
  not `stsa-membership-ios`. MembershipAPI pins `iss` and `aud` to a single
  registration and 401s tokens from the other one.
- It is a **public client**. There is no secret and none should be added; proof
  of possession is PKCE (S256), which AppAuth derives on its own.
- Endpoints come from discovery at `<issuer>/.well-known/openid-configuration`,
  never hardcoded — authentik moves them between releases.
- `offline_access` is what makes authentik return a refresh token. Without it
  the session dies with the 5-minute access token.

Redirect URI is `tw.stsa.membership://callback`, registered in
[Config/Info.plist](ios/Config/Info.plist) and resumed from `.onOpenURL` in
[MemberAppApp.swift](ios/MemberApp/App/MemberAppApp.swift).

### Token handling

Access tokens live five minutes, so **nothing ever holds one**.
[`AuthManager.accessToken()`](ios/MemberApp/Auth/AuthManager.swift) goes through
`OIDAuthState.performAction(freshTokens:)` on every call, which returns the
cached token while it is valid and silently redeems the refresh token when it is
not. Use `authorizedRequest(for:)` to build outbound requests rather than
stashing a token anywhere.

The archived `OIDAuthState` — which carries the 30-day refresh token — is the
only thing in the Keychain, written
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Profile claims and user
preferences are not credentials and live in UserDefaults, keyed on `sub`.

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

The one remaining stub lives in
[Features/Placeholders.swift](ios/MemberApp/Features/Placeholders.swift).
Delete it as its real screen lands.

### Member card

The QR payload is `stsa$` + a code minted per request by MembershipAPI and held
in Redis for 300s. The card re-fetches every 250s to stay inside that window,
but only while it is on screen — there is no reason to keep a live credential
alive in someone's pocket. Screen brightness is raised while the card is up and
restored on dismiss.

Showing the card requires device-owner authentication (Face ID / Touch ID /
passcode), **on by default**. It is not a second login — it guards the one case
the iOS lock screen does not cover, a phone handed over while already unlocked.
Devices with no passcode fall through rather than being locked out. The toggle
is in 設定.

### Events

The Indico category export answers anonymously, so
[EventsStore](ios/MemberApp/Features/Events/EventsStore.swift) deliberately sends no
credentials — requiring a token would only make the tab fail for no gain.
Registration happens on Indico itself. Indico splits timestamps into
date/time/tz rather than emitting ISO 8601, and descriptions arrive as HTML;
both are handled in [IndicoEvent](ios/MemberApp/Models/IndicoEvent.swift).

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

tools/oauth-bridge/     Standalone OAuth redirect bridge — not part of the app target
```

Observable state is created once in `MemberAppApp` and injected via
`.environment(…)`: `Session`, `AuthManager`, `MembershipCodeStore`,
`EventsStore`, `AppSettings`. Nothing owns a second copy of identity —
`AuthManager.isLoggedIn` is the single gate, which is what fixed a successful
login leaving the app on the welcome screen.

`ios/MemberApp/` is a **file-system synchronized group**: any file added to the
folder is picked up by the target automatically. Create Swift files from the
command line or Finder and Xcode includes them — no target-membership step.

## Design notes

The prototype's greys are literal transcriptions of Apple's semantic colours
(`rgba(60,60,67,.6)` → `.secondaryLabel`, `#f2f2f7` → `systemGroupedBackground`,
`rgba(118,118,128,.12)` → `tertiarySystemFill`). Those are used as semantic
colours here rather than hardcoded hex, so Dark Mode and Increase Contrast work.
Only the brand red `#EC3013` is a custom asset (`AccentColor`).

Likewise the type ramp (34/26/17/15/13/11pt) is the standard iOS ramp, so the
screens use `.largeTitle` / `.headline` / `.subheadline` / `.footnote` and get
Dynamic Type for free.

UI strings are Traditional Chinese literals in source. There is no localisation
catalogue yet.

## OAuth redirect bridge

[`tools/oauth-bridge/`](tools/oauth-bridge/) holds a Cloudflare Worker and a
WordPress mu-plugin — same behaviour, deploy one. Indico only accepts `http(s)`
redirect URIs, so `tw.stsa.membership://callback` cannot be registered with it
directly; the bridge is registered instead and forwards to the app.

It is standalone infrastructure. The app currently authenticates against
authentik, not Indico, so nothing in the iOS target depends on it yet. See
[its README](tools/oauth-bridge/README.md) for deployment and the caching
caveats, which matter — the response carries a one-time authorization code.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
