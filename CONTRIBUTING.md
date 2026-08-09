# Contributing

Small codebase, few contributors, real members using it. The rules below are
mostly about not shipping something that looks finished when it is not, and not
weakening the auth path by accident.

Read the [README](README.md) first — it covers setup, the backends and how
sign-in works.

## Getting set up

```bash
git clone <this repo>
cd MemberApp
open ios/MemberApp.xcodeproj        # or: open -a "Android Studio" android
```

Xcode resolves AppAuth on first open. `DEVELOPMENT_TEAM` is set in the project;
change it locally for your own signing rather than committing a different value.

Adding a file needs no Xcode step — `ios/MemberApp/` is a file-system
synchronized group, so anything under it joins the target automatically. That
means `ios/MemberApp.xcodeproj/project.pbxproj` should rarely change; if it
shows up in a diff, check it is a deliberate build-setting or dependency change
and not incidental churn from opening the project.

Android needs an SDK path in `android/local.properties` (git-ignored, and
Android Studio writes it for you) or `ANDROID_HOME` set. Nothing else — the
Gradle wrapper fetches its own distribution.

### Changing one platform

A change that is only about how a platform draws something belongs on that
platform alone. A change to what the app *says*, what it stores, or how it talks
to a backend belongs on both, in the same PR — the two apps share one OIDC
client registration and one set of copy, and a fix that lands on one side only
is how they drift apart. Say in the PR which you did and why.

## Before you open a PR

CI builds and runs the tests on every push and PR — see
[.github/workflows/ci.yml](.github/workflows/ci.yml). The same thing locally:

```bash
xcodebuild test -project ios/MemberApp.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

cd android && ./gradlew testDebugUnitTest lintDebug assembleDebug
```

`ios/MemberAppTests/` and `android/app/src/test/` cover the same slice, and only
that slice: claim decoding, the school lookup, channel seeding, deal expiry,
Indico's date and HTML parsing, and the preference defaulting. Nothing there
touches the network, the credential store or a view, so a green run says the
logic holds, not that the app works. Expectations that pin a behaviour rather
than assert an ideal — deal expiry, suffix matching on school domains — are
commented as such on both sides and should stay in step.

That part is still on you:

Run it and exercise what you touched. If you changed anything in the auth
or member-card path, check all of:

- fresh sign-in (delete the app first — on iOS the Keychain survives deletion,
  so "delete and reinstall" is a real, distinct state; on Android the encrypted
  blob goes with the app, which is a different state worth seeing)
- relaunch with a valid session
- backgrounding past the 5-minute access-token lifetime, then foregrounding
- the member card actually producing a scannable code
- sign out, then sign in again

Android lint runs as part of CI and fails the build on errors, so run
`./gradlew lintDebug` before pushing rather than finding out there.

## Code conventions

Match the surrounding code — it is consistent, so this is not hard.

Both platforms:

- Shared state is created once — `MemberAppApp` / `AppContainer` — and injected.
  Do not construct a second `AuthManager` or store, and in particular do not
  keep a second copy of "is the user signed in".
- Views stay dumb. Networking, decoding and persistence belong in a store or
  manager, not in a `body` or a composable.
- Do not add a dependency without a reason that survives "could this be forty
  lines instead". That question is why there is no HTTP client library and no DI
  framework here; three GETs and five objects did not need one.
- Traditional Chinese is the source language and English ships alongside it. A
  string added to `Localizable.xcstrings` belongs in `values/` and `values-en/`
  too, and the other way round.
- The design system owns the greys. `Theme` holds only what is genuinely ours —
  the brand red, the radii, the CTA metrics. Reach for a hex value only when the
  platform has no equivalent.

iOS:

- Swift 5 language mode, SwiftUI, `@Observable` for shared state.
- Apple's semantic colours and the standard type ramp.

Android:

- Kotlin, Jetpack Compose, Material 3. Shared state is a plain class holding
  `mutableStateOf`, reached through `LocalAppContainer` — not a ViewModel per
  screen, because these stores outlive any one screen.
- Material 3 roles and Material's type scale. The colour scheme is written out
  in `Theme.kt` on purpose; do not swap it for `dynamicColorScheme()`.
- `NavController` owns navigation state. Do not add a `Session`-shaped object
  beside it.

### Comments explain why, not what

This is the codebase's strongest convention, and the most useful thing in it.
Comments record the constraint or the bug that produced the code, so the next
person does not "simplify" it back:

```swift
// `bool(forKey:)` cannot tell "never set" from "explicitly off", and the
// default is on — so check for the key before falling back.
```

If you fix something subtle, leave the reason behind. If you find such a comment
and it is now wrong, deleting it is part of the change.

## Data honesty

Screens without a backing service stay stubs. `Features/Placeholders.swift` and
`JobsScreen.kt` exist so the shells compile, not so the apps look complete —
Jobs is there because it has no data source yet.

The same applies to content. Announcements are a single real notice rather than
a plausible-looking feed, deal counts are computed from the actual partner list,
and the events count is the real one from Indico. Do not pad any of these with
invented entries; an empty state is a better lie than a fake one.

When a field is genuinely unknown, model it as optional and omit it. `Deal.code`
is optional because HSBC's offer has no code; `Profile.school` returns nil for
unrecognised domains rather than guessing.

## Security rules

These are not stylistic. Do not change them without discussing it first.

They apply to both apps. Where the mechanism differs the rule does not.

- **The OIDC client stays public.** No client secret, ever. PKCE is the proof of
  possession, and both `OIDAuthorizationRequest`'s standard initialiser and
  `AuthorizationRequest.Builder` derive it — do not switch to the `clientSecret`
  overload, and do not call `setCodeVerifier(null)`.
- **Never hold an access token.** Call `AuthManager.accessToken()`,
  `authorizedRequest(for:)` or `authorizedGet(_:)` at the point of use. Tokens
  live five minutes.
- **Credentials go in the credential store, nothing else does.** The serialised
  auth state is the only thing in the iOS Keychain and the only thing
  `TokenStore` encrypts. Profile claims and preferences go in UserDefaults /
  SharedPreferences. Never write anything token-shaped in the clear, and never
  fall back to plaintext when the write fails.
- **Key local storage on `sub`.** Email and username are user-changeable in
  authentik.
- **`Profile.groups` drives UI only.** It is a self-reported claim from a token
  neither app verifies. Anything that actually matters is re-checked
  server-side.
- **Sign-in runs in the browser** — `ASWebAuthenticationSession` on iOS, a
  Custom Tab on Android, both via AppAuth. Never a `WKWebView` or a `WebView`:
  that takes the flow out of the browser's session and breaks SSO.
- **The redirect bridge takes no destination parameter.** Adding `next=` or
  `redirect=` to `tools/oauth-bridge/` turns it into an open redirector attached
  to a live OAuth flow.
- Keep anything that logs claims or token state behind `#if DEBUG` /
  `BuildConfig.DEBUG`. Both are compile-time, so the code does not ship. See
  `logLoginResult` and the diagnostics section in `AccountView` / `AccountScreen`.
- **Nothing leaves the device.** `allowBackup="false"` plus the exclusions in
  `data_extraction_rules.xml` are the Android half of the iOS Keychain's
  `ThisDeviceOnly` accessibility. Do not relax either to make a migration work.

Changing an endpoint, scope or client ID has consequences beyond this repo —
MembershipAPI pins `iss` and `aud`, so a "cleanup" there produces 401s at
`get_code`, and the two apps share one registration, so changing it on one
platform only breaks that one. The reasoning is written down in
[AuthConfiguration.swift](ios/MemberApp/Auth/AuthConfiguration.swift) and
[AuthConfiguration.kt](android/app/src/main/java/tw/stsa/memberapp/auth/AuthConfiguration.kt);
read it before editing either.

## Commits

Look at `git log` — the style is consistent and worth matching.

- Subject: imperative mood, sentence case, no type prefix, no trailing period,
  ~65 characters. "Stop the pinned CTA rendering under the tab bar", not
  "fix: tab bar bug".
- Body: hard-wrapped at ~76 columns, explaining the problem and why this is the
  fix. Symptom first, mechanism second. Skip the body only when the subject is
  genuinely the whole story.
- One logical change per commit. If the body needs "also", consider two commits
  — though a small related follow-on in the same area is fine, called out in its
  own paragraph.
- No trailers or attribution footers.

## Pull requests

Say what changed and what you ran to check it, and on which platforms.
Screenshots or a screen recording for anything visual — most of these apps are
visual, and there are no snapshot tests to catch a regression. For a change that
touches both, one screenshot each.
