# Live handoff test — MacBook + iPhone Pro

End to end: design in the Mac browser, scan the room with the iPhone's LiDAR,
watch the measurements land in the browser. No cloud, no Apple Developer
payment, no domain.

Budget about an hour, nearly all of it the first Xcode build.

---

## What you need

- A Mac with Xcode 15+ and Flutter on `PATH`
- **iPhone 12 Pro or later** (LiDAR — a non-Pro iPhone will not work, and the
  Simulator cannot do RoomPlan at all)
- Both devices on the **same Wi-Fi**
- A free Apple ID is enough. No paid membership: nothing here uses Universal
  Links or push, which are the entitlements that would require one.

---

## 1 — Generate the iOS project

This repo has no `ios/` directory; only the Swift sources are committed.

```bash
cd Furn-App
flutter create --platforms=ios .
```

`flutter create` writes its own `AppDelegate.swift` over ours. Restore it —
the only difference is the block that registers the channel:

```bash
git checkout ios/Runner/AppDelegate.swift
git status --short ios/          # RoomScanPlugin.swift + HandoffUploader.swift should be untouched
```

## 2 — Xcode settings

```bash
open ios/Runner.xcworkspace
```

1. **Add the two Swift files to the target.** In the Project Navigator, select
   `RoomScanPlugin.swift` and `HandoffUploader.swift` → File Inspector →
   check **Runner** under Target Membership. *If you skip this they are never
   compiled and the channel silently does nothing.*
2. **Deployment target → 16.0** (Runner target → General → Minimum Deployments).
   RoomPlan does not exist before iOS 16.
3. **Signing** → Runner → Signing & Capabilities → check *Automatically manage
   signing* → pick your personal team.
4. **Info.plist** — add both keys:

```xml
<key>NSCameraUsageDescription</key>
<string>نحتاج الكاميرا لمسح غرفتك وقياس أبعادها بدقّة.</string>

<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key><true/>
</dict>
```

The camera string is not optional: **the app is killed the moment the scan
starts without it.** `NSAllowsLocalNetworking` is what lets the phone POST to
`http://192.168.x.x` — iOS blocks cleartext HTTP otherwise. It is scoped to
private addresses; do not reach for `NSAllowsArbitraryLoads`.

5. `ios/Podfile` — first line:

```ruby
platform :ios, '16.0'
```

Then:

```bash
cd ios && pod install && cd ..
```

## 3 — Build the web app and start the rendezvous

```bash
flutter build web --no-tree-shake-icons --web-renderer canvaskit
python3 tools/handoff_server.py
```

It prints two addresses:

```
Mac browser : http://localhost:8080/
iPhone      : http://192.168.1.20:8080/   <- enter this in the app
```

The second is the one the phone needs. The server serves the Flutter build
*and* the session API from the same origin, which is why there is no CORS
configuration anywhere in this setup.

## 4 — Install on the phone

Plug the iPhone in, trust the Mac, then:

```bash
flutter devices                     # confirm the phone is listed
flutter run --release -d <device-id>
```

First run on a free Apple ID: iPhone → **Settings → General → VPN & Device
Management → Developer App → Trust**. The provisioning profile expires after
7 days; re-run to refresh it.

## 5 — Run the test

1. Mac browser → `http://localhost:8080/` → open the sandbox → tap the
   **crosshair** icon (امسح غرفتي).
2. A sheet shows a six-character code, e.g. `JGSWDU`.
3. On the phone: enter the Mac address from step 3 and that code.
4. Scan the room — walk the perimeter slowly, keep walls in frame.
5. Tap **تم**. The browser advances through
   `تم الاقتران → جارٍ المسح → معالجة القياسات → وصلت القياسات`
   and re-lays the furniture into your real room.

The server logs each stage as it arrives:

```
  [handoff] JGSWDU <- linked
  [handoff] JGSWDU <- scanning
  [handoff] JGSWDU <- completed
```

---

## When it does not work

| Symptom | Cause |
|---|---|
| Browser sits on "بانتظار الجوال" | Phone is on cellular or a different Wi-Fi. Check both on the same network. |
| Phone shows a network error | `NSAllowsLocalNetworking` missing, or the Mac's firewall is blocking 8080 (System Settings → Network → Firewall). |
| App dies when the scan starts | `NSCameraUsageDescription` missing. |
| "RoomPlan requires a LiDAR device" | Non-Pro iPhone, or the Simulator. |
| Channel never answers | The Swift files were not added to the Runner target (step 2.1). |
| Browser 404s after a reload | You are not serving through `handoff_server.py` — it is what provides the SPA fallback. |

Sessions are in memory: restarting the server invalidates open codes. TTL is 15
minutes.

---

## Scope of this rig

This is a **trusted-LAN test harness**, not a product path. There is no
authentication beyond a six-character code, traffic is cleartext HTTP, and any
device on the network that guesses a live code can read the dimensions of the
room being scanned. Fine on your own Wi-Fi for an afternoon; not something to
demo on conference or hotel networks, and not a step toward production.

The production flow is the other one: QR + Universal Link + a real backend,
which needs a domain, HTTPS, an `apple-app-site-association` file, the
Associated Domains entitlement (**paid** Apple Developer account) and a
Firebase/Supabase project. `HandoffChannel` is the seam — a
`SupabaseHandoffChannel` implementing the same interface swaps in without the
controller or the UI noticing.
