# MemberApp

STSA 新加坡台灣學生會員系統 — native SwiftUI iOS app.

Implemented from the Claude Design prototype [`STSA App.dc.html`](https://claude.ai/design/p/bfab5630-cb66-4104-a360-9eaf42c3ba8d?file=STSA+App.dc.html)
(21 screens). The prototype is the design reference only; nothing from it ships.

## Requirements

- Xcode 26 / iOS 26 SDK
- Deployment target: iOS 26.0 (the design specifies a floating Liquid Glass tab
  bar, which `TabView` renders natively on 26)

## Running

```bash
open MemberApp.xcodeproj
```

Pick an iPhone simulator and run. Or from the command line:

```bash
xcodebuild -project MemberApp.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Layout

```
MemberApp/
├── App/            MemberAppApp, RootView (tab shell), Session
├── DesignSystem/   Theme — brand colour, radii, BrandButtonStyle
├── Models/         Member, and the rest of the domain types
├── Features/       One folder per prototype flow
│   ├── Onboarding/ Welcome, Sign Up, Issued
│   ├── Home/       Home, Announcement Detail, Channels
│   ├── Card/       Member Card
│   ├── Deals/      Deals, Deal Detail, Redeem
│   ├── Jobs/       Jobs, Job Detail
│   ├── Events/     Events, Event Detail, Ticket
│   ├── Buddy/      Intro, Quiz, Results, Buddy Profile
│   └── Profile/    Profile
└── Resources/      Assets.xcassets
```

`MemberApp/` is a **file-system synchronized group**: any file added to the
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

## Status

Built: onboarding Welcome screen, tab shell, design tokens.
Remaining: the other 20 screens — see `Features/Placeholders.swift`.
