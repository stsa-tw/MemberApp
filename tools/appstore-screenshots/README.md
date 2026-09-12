# App Store screenshots

The four 繁體中文 screenshots in [`zh-Hant/`](zh-Hant/), sized 1284 × 2778 for
App Store Connect's 6.5" slot. Upload them in filename order.

| | Screen | Caption |
|---|---|---|
| 01 | 會員卡 | 電子會員卡，隨時出示 |
| 02 | 首頁 | 重要的事，一開就看見 |
| 03 | 活動 | 活動報名與電子票券 |
| 04 | 優惠 | 合作商家專屬優惠 |

## Regenerating

```bash
xcodebuild -project ios/MemberApp.xcodeproj -scheme MemberApp \
  -destination 'platform=iOS Simulator,name=ASC 6.5' build   # Debug, not Release
xcrun simctl install "ASC 6.5" <path to MemberApp.app>
python3 tools/appstore-screenshots/capture.py   # raw_zh/ — one relaunch per screen
python3 tools/appstore-screenshots/frame.py     # zh-Hant/ — brand wash + captions
```

`capture.py` creates the `ASC 6.5` simulator itself if it is missing. It has to
be an **iPhone 14 Plus**: it is the only device left in the Xcode 26 simulator
set whose native framebuffer is 1284 × 2778, so nothing is ever resampled. The
6.9" slot (1320 × 2868) is an iPhone 17 Pro Max, if that one is wanted too.

## Why the member is fictional

`ScreenshotFixtures` (in `ios/MemberApp/App/`) stands up 王小明 / `demo@u.nus.edu`
and a `stsa$`-prefixed code that is not valid server-side. It is `#if DEBUG` and
inert unless `STSA_SCREENSHOT=1` is in the launch environment, so it cannot
reach a release build.

Signing a real member in instead would put their name, school email and a live
QR payload on a public store listing — and the card's biometric gate would
photograph as a passcode keyboard, because the simulator answers
`canEvaluatePolicy` with a prompt no capture script can type into.
