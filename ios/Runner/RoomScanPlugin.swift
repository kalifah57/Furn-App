import Flutter
import UIKit
import RoomPlan
import simd

/// Native half of `com.furnapp.spatial/roomplan`.
///
/// Presents Apple's RoomPlan capture UI, then reduces the resulting
/// `CapturedRoom` to the few numbers the Dart spatial engine actually needs:
/// floor width, floor length, ceiling height, openings, and a USDZ mesh path.
///
/// Requires iOS 16 and a LiDAR device (iPhone 12 Pro and later). Everything is
/// gated on `RoomCaptureSession.isSupported` — on anything else the channel
/// answers `UNSUPPORTED` rather than throwing.
@available(iOS 16.0, *)
final class RoomScanPlugin: NSObject {

  static let channelName = "com.furnapp.spatial/roomplan"

  private weak var hostViewController: UIViewController?

  /// The channel must stay alive for the handler to keep firing, so the plugin
  /// owns it. The caller owns the plugin — see `AppDelegate`.
  private var channel: FlutterMethodChannel?

  private init(host: UIViewController) {
    self.hostViewController = host
    super.init()
  }

  /// Wires the channel and returns the plugin. **Keep the returned value**: if
  /// it deallocates, the channel goes with it and `startRoomScan` silently stops
  /// being answered.
  @discardableResult
  static func register(with messenger: FlutterBinaryMessenger,
                       host: UIViewController) -> RoomScanPlugin {
    let plugin = RoomScanPlugin(host: host)
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    // Weak capture: the plugin owns the channel, so a strong capture here would
    // close the retain cycle plugin -> channel -> handler -> plugin.
    channel.setMethodCallHandler { [weak plugin] call, result in
      plugin?.handle(call, result: result)
    }
    plugin.channel = channel
    return plugin
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(RoomCaptureSession.isSupported)

    case "startRoomScan":
      guard RoomCaptureSession.isSupported else {
        result(FlutterError(code: "UNSUPPORTED",
                            message: "RoomPlan requires a LiDAR device on iOS 16+.",
                            details: nil))
        return
      }
      presentCapture(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentCapture(result: @escaping FlutterResult) {
    guard let host = hostViewController else {
      result(FlutterError(code: "SCAN_FAILED",
                          message: "No view controller to present from.",
                          details: nil))
      return
    }

    // A FlutterResult must be called exactly once — calling it twice crashes the
    // engine, never calling it hangs the Dart Future forever. This box is the
    // single place that guarantee is enforced, so every exit path below can
    // reply freely.
    let reply = SingleReply(result)

    let scanner = RoomScanViewController { outcome in
      host.dismiss(animated: true) {
        switch outcome {
        case .success(let room):
          do {
            reply.send(try RoomScanPlugin.encode(room))
          } catch {
            reply.send(FlutterError(code: "SCAN_FAILED",
                                    message: "Could not serialise the scan: \(error)",
                                    details: nil))
          }
        case .cancelled:
          reply.send(FlutterError(code: "CANCELLED",
                                  message: "The user cancelled the scan.",
                                  details: nil))
        case .failed(let error):
          reply.send(FlutterError(code: "SCAN_FAILED",
                                  message: error.localizedDescription,
                                  details: nil))
        }
      }
    }

    scanner.modalPresentationStyle = .fullScreen
    host.present(scanner, animated: true)
  }

  // MARK: - CapturedRoom -> JSON

  /// Reduces a `CapturedRoom` to the JSON contract the Dart side parses.
  ///
  /// Dimensions come from the walls, not from a floor surface: `CapturedRoom.floors`
  /// only exists on iOS 17, and walls are present on every supported version.
  static func encode(_ room: CapturedRoom) throws -> String {
    let footprint = floorExtent(of: room.walls)
    let ceilingM = room.walls.map { $0.dimensions.y }.max() ?? 0

    let openings: [[String: Any]] = (room.doors + room.windows).map {
      [
        "width_cm": Double($0.dimensions.x) * 100,
        "height_cm": Double($0.dimensions.y) * 100,
        "is_opening": true,
      ]
    }
    let walls: [[String: Any]] = room.walls.map {
      [
        "width_cm": Double($0.dimensions.x) * 100,
        "height_cm": Double($0.dimensions.y) * 100,
        "is_opening": false,
      ]
    }

    var payload: [String: Any] = [
      "width_cm": footprint.width * 100,
      "length_cm": footprint.length * 100,
      "ceiling_cm": Double(ceilingM) * 100,
      "surfaces": walls + openings,
      // RoomPlan gives no scalar confidence; wall count is a reasonable proxy
      // for whether the room closed properly. Four walls or more = a full loop.
      "confidence": room.walls.count >= 4 ? 0.95 : 0.6,
    ]

    if let meshPath = try? exportMesh(room) {
      payload["mesh_path"] = meshPath
    }

    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    return String(decoding: data, as: UTF8.self)
  }

  /// Floor width/length in metres, measured in the room's **own** frame.
  ///
  /// A world-axis bounding box would inflate every room scanned at an angle to
  /// the walls — a 3x4m room entered diagonally could measure 5x5. So the
  /// longest wall defines the room's axis, the wall endpoints are rotated into
  /// that frame, and the box is taken there.
  static func floorExtent(of walls: [CapturedRoom.Surface]) -> (width: Double, length: Double) {
    guard !walls.isEmpty else { return (0, 0) }

    let longest = walls.max(by: { $0.dimensions.x < $1.dimensions.x })!
    let axis = simd_float3(longest.transform.columns.0.x,
                           0,
                           longest.transform.columns.0.z)
    let yaw = atan2(axis.z, axis.x)
    let c = cos(-yaw), s = sin(-yaw)

    var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
    var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

    for wall in walls {
      let t = wall.transform
      let centre = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
      let along = simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z)
      let half = wall.dimensions.x / 2

      for end in [centre + along * half, centre - along * half] {
        // Rotate into the room's frame around Y.
        let x = end.x * c - end.z * s
        let z = end.x * s + end.z * c
        minX = min(minX, x); maxX = max(maxX, x)
        minZ = min(minZ, z); maxZ = max(maxZ, z)
      }
    }

    return (Double(maxX - minX), Double(maxZ - minZ))
  }

  /// Writes the room as USDZ into the caches directory and returns its path.
  private static func exportMesh(_ room: CapturedRoom) throws -> String {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let url = dir.appendingPathComponent("room_scan_\(Int(Date().timeIntervalSince1970)).usdz")
    try room.export(to: url)
    return url.path
  }
}

/// Enforces the call-the-result-exactly-once rule of platform channels.
private final class SingleReply {
  private var result: FlutterResult?
  init(_ result: @escaping FlutterResult) { self.result = result }

  func send(_ value: Any?) {
    guard let result = result else { return }
    self.result = nil
    result(value)
  }
}

// MARK: - Capture UI

@available(iOS 16.0, *)
enum RoomScanOutcome {
  case success(CapturedRoom)
  case cancelled
  case failed(Error)
}

/// Hosts `RoomCaptureView` with Done / Cancel, and reports exactly one outcome.
@available(iOS 16.0, *)
final class RoomScanViewController: UIViewController, RoomCaptureViewDelegate {

  private lazy var captureView = RoomCaptureView(frame: view.bounds)
  private let onFinish: (RoomScanOutcome) -> Void
  private var finished = false

  init(onFinish: @escaping (RoomScanOutcome) -> Void) {
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    captureView.delegate = self
    view.addSubview(captureView)
    addControls()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    captureView.captureSession.run(configuration: RoomCaptureSessionConfig())
  }

  private func addControls() {
    let done = UIButton(type: .system)
    done.setTitle("تم", for: .normal)
    done.addTarget(self, action: #selector(finishScan), for: .touchUpInside)

    let cancel = UIButton(type: .system)
    cancel.setTitle("إلغاء", for: .normal)
    cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [cancel, done])
    stack.axis = .horizontal
    stack.distribution = .equalSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                    constant: -24),
    ])
  }

  @objc private func finishScan() {
    // Stopping the session triggers processing; the result arrives in the
    // delegate callback below, not here.
    captureView.captureSession.stop()
  }

  @objc private func cancelScan() {
    captureView.captureSession.stop()
    report(.cancelled)
  }

  // MARK: RoomCaptureViewDelegate

  func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                   error: Error?) -> Bool {
    // Let RoomPlan post-process into a CapturedRoom.
    return error == nil
  }

  func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
    if let error = error {
      report(.failed(error))
    } else {
      report(.success(processedResult))
    }
  }

  /// Cancel and completion can race (the user taps Cancel while processing is
  /// already in flight); only the first one is reported.
  private func report(_ outcome: RoomScanOutcome) {
    guard !finished else { return }
    finished = true
    onFinish(outcome)
  }
}
