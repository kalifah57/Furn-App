# iOS — RoomPlan spatial scanning

This repository has **no Xcode project**. It was created as a web-first Flutter
app (`flutter create` was never run with `--platforms=ios`), and CI builds and
deploys `flutter build web` only.

The two Swift files here are the RoomPlan integration — the part that is real
work. The Xcode scaffold around them is generated, not authored, so it is not
committed: a hand-written `project.pbxproj` would be broken in ways nobody
could review.

## Generating the scaffold (requires a Mac with Xcode)

```bash
# From the repository root. This creates ios/ around the existing Swift files.
flutter create --platforms=ios .
```

`flutter create` writes its own `ios/Runner/AppDelegate.swift`. If it overwrites
the one here, restore it — the only difference is the `RoomScanPlugin.register`
block, which is what wires the channel up:

```bash
git checkout ios/Runner/AppDelegate.swift
```

Then add `RoomScanPlugin.swift` to the Runner target in Xcode
(**File → Add Files to "Runner"**), or it will not be compiled.

## Required project settings

| Setting | Value | Why |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | `16.0` | RoomPlan does not exist before iOS 16 |
| `NSCameraUsageDescription` | an Arabic sentence explaining the scan | **The app is killed on launch of the scan without it** |

In `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>نحتاج الكاميرا لمسح غرفتك وقياس أبعادها بدقّة.</string>
```

In `ios/Podfile`, raise the platform line:

```ruby
platform :ios, '16.0'
```

## Hardware

RoomPlan needs a **LiDAR** sensor: iPhone 12 Pro / Pro Max and later Pro models,
or iPad Pro 2020 and later. It does not run in the Simulator. Non-Pro iPhones
run iOS 16 but have no LiDAR, so `RoomCaptureSession.isSupported` is `false`
there and the app falls back rather than failing.

## The channel contract

`com.furnapp.spatial/roomplan`

| Method | Returns |
|---|---|
| `isSupported` | `Bool` |
| `startRoomScan` | JSON `String` (below), or a `FlutterError` |

```json
{
  "width_cm": 382.4,
  "length_cm": 421.9,
  "ceiling_cm": 271.0,
  "confidence": 0.95,
  "mesh_path": "/var/mobile/.../room_scan_1765432100.usdz",
  "surfaces": [
    { "width_cm": 382.4, "height_cm": 271.0, "is_opening": false },
    { "width_cm": 90.0,  "height_cm": 210.0, "is_opening": true }
  ]
}
```

Error codes: `UNSUPPORTED`, `CANCELLED`, `SCAN_FAILED`. Dart maps each to a
`Failure` in `PlatformRoomScannerService`.

## Verification status

The Dart side is covered by `test/features/interactive_sandbox/platform_room_scanner_test.dart`,
which drives the channel with a mock handler — including cancellation, an
unsupported device, and malformed payloads.

**The Swift is not verified.** It has never been compiled: this repository has
no Xcode project, and CI has no macOS runner. Treat it as a reviewed draft that
needs a real build and a device test before it is trusted.

Two things to check first on device:

1. **Room orientation.** `floorExtent` rotates wall endpoints into the room's
   own frame using the longest wall, because a world-axis bounding box inflates
   any room scanned at an angle. Verify against a tape measure in a room entered
   diagonally — that is where this either works or visibly does not.
2. **Non-rectangular rooms.** An L-shaped room still reduces to one width and
   one length, which will overstate its area. The engine's occupancy budget
   would then be too generous. Rooms like that need the floor polygon, not a box.
