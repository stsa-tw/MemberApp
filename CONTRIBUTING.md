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
open MemberApp.xcodeproj
```

Xcode resolves AppAuth on first open. `DEVELOPMENT_TEAM` is set in the project;
change it locally for your own signing rather than committing a different value.

Adding a file needs no Xcode step — `MemberApp/` is a file-system synchronized
group, so anything under it joins the target automatically. That means
`MemberApp.xcodeproj/project.pbxproj` should rarely change; if it shows up in a
diff, check it is a deliberate build-setting or dependency change and not
incidental churn from opening the project.

## Before you open a PR

There is no test target and no CI. That puts the burden on the build and on
running the thing:

```bash
xcodebuild -project MemberApp.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Then run it and exercise what you touched. If you changed anything in the auth
or member-card path, check all of:

- fresh sign-in (delete the app first — the Keychain survives deletion, so
  "delete and reinstall" is a real, distinct state)
- relaunch with a valid session
- backgrounding past the 5-minute access-token lifetime, then foregrounding
- the member card actually producing a scannable code
- sign out, then sign in again

## Code conventions

Match the surrounding code — it is consistent, so this is not hard.

- Swift 5 language mode, SwiftUI, `@Observable` for shared state. No third-party
  code beyond AppAuth; do not add a dependency without a reason that survives
  "could this be forty lines instead".
- Shared state is created once in `MemberAppApp` and injected with
  `.environment(…)`. Do not construct a second `AuthManager` or store — and in
  particular, do not keep a second copy of "is the user signed in".
- Views stay dumb. Networking, decoding and persistence belong in a store or
  manager, not in a `body`.
- UI strings are Traditional Chinese literals in source. Keep them that way
  until someone introduces a localisation catalogue properly.
- Use Apple's semantic colours and the standard type ramp. `Theme` only holds
  what is genuinely ours — the brand red, the radii, the CTA metrics. Reach for
  a hex value only when the design system has no equivalent.

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

Screens without a backing service stay stubs. `Features/Placeholders.swift`
exists so the shell compiles, not so the app looks complete — Jobs and Channels
are there because they have no data source yet.

The same applies to content. Announcements are a single real notice rather than
a plausible-looking feed, deal counts are computed from the actual partner list,
and the events count is the real one from Indico. Do not pad any of these with
invented entries; an empty state is a better lie than a fake one.

When a field is genuinely unknown, model it as optional and omit it. `Deal.code`
is optional because HSBC's offer has no code; `Profile.school` returns nil for
unrecognised domains rather than guessing.

## Security rules

These are not stylistic. Do not change them without discussing it first.

- **The OIDC client stays public.** No client secret, ever. PKCE is the proof of
  possession, and `OIDAuthorizationRequest`'s standard initialiser derives it —
  do not switch to the `clientSecret` overload.
- **Never hold an access token.** Call `AuthManager.accessToken()` or
  `authorizedRequest(for:)` at the point of use. Tokens live five minutes.
- **Credentials go in the Keychain, nothing else does.** The archived
  `OIDAuthState` is the only Keychain item. Profile claims and preferences go in
  UserDefaults. Never write anything token-shaped to a file, and never fall back
  to one when a Keychain write fails.
- **Key local storage on `sub`.** Email and username are user-changeable in
  authentik.
- **`Profile.groups` drives UI only.** It is a self-reported claim from a token
  this app does not verify. Anything that actually matters is re-checked
  server-side.
- **Sign-in runs in `ASWebAuthenticationSession`,** via AppAuth. Never a
  `WKWebView` — that would take the flow out of Safari's session and break SSO.
- **The redirect bridge takes no destination parameter.** Adding `next=` or
  `redirect=` to `tools/oauth-bridge/` turns it into an open redirector attached
  to a live OAuth flow.
- Keep `#if DEBUG` around anything that logs claims or token state. See
  `logLoginResult` and the diagnostics block in `AccountView`.

Changing an endpoint, scope or client ID has consequences beyond this repo —
MembershipAPI pins `iss` and `aud`, so a "cleanup" there produces 401s at
`get_code`. The reasoning is written down in
[AuthConfiguration.swift](MemberApp/Auth/AuthConfiguration.swift); read it before
editing that file.

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

Say what changed and what you ran to check it. Screenshots or a screen recording
for anything visual — most of this app is visual, and there are no snapshot
tests to catch a regression.
