import Foundation

/// Sends scan progress and results to the Mac's local rendezvous
/// (`tools/handoff_server.py`) over the LAN.
///
/// Deliberately plain `URLSession` against `http://` on a private network:
/// there is no cloud in this path, so there is nothing to authenticate against
/// beyond the pairing code the user typed. That is acceptable for a trusted
/// LAN test rig and nowhere near sufficient for production — see the note on
/// ATS below.
///
/// **Info.plist**: iOS blocks cleartext HTTP by default (App Transport
/// Security). Talking to `http://192.168.x.x:8080` therefore requires an ATS
/// exception. Scope it to local networking only:
///
/// ```xml
/// <key>NSAppTransportSecurity</key>
/// <dict>
///   <key>NSAllowsLocalNetworking</key><true/>
/// </dict>
/// ```
///
/// `NSAllowsLocalNetworking` covers RFC-1918 addresses and `.local` without
/// opening the app to arbitrary cleartext — do **not** use
/// `NSAllowsArbitraryLoads` for this.
@available(iOS 16.0, *)
struct HandoffUploader {

  enum Stage: String {
    case linked, scanning, processing, completed, failed, cancelled
  }

  let baseURL: URL      // e.g. http://192.168.1.20:8080
  let pairingCode: String

  private var endpoint: URL {
    baseURL.appendingPathComponent("handoff").appendingPathComponent(
      pairingCode.uppercased())
  }

  /// Publishes a stage with no payload — the browser uses these to show
  /// progress while the user is still walking around the room.
  func send(stage: Stage, failure: String? = nil) async {
    var body: [String: Any] = ["status": stage.rawValue]
    if let failure = failure { body["failure"] = failure }
    await post(body)
  }

  /// Publishes the finished measurements.
  ///
  /// Dimensions only — the USDZ mesh is megabytes and the browser does not need
  /// it to render the scene. Uploading it here would turn a one-second handoff
  /// into a minute of waiting for data nothing is blocked on.
  func sendCompleted(widthCm: Double, lengthCm: Double,
                     ceilingCm: Double, confidence: Double) async {
    await post([
      "status": Stage.completed.rawValue,
      "room": [
        "width_cm": widthCm,
        "length_cm": lengthCm,
        "ceiling_cm": ceilingCm,
        "confidence": confidence,
      ],
    ])
  }

  private func post(_ body: [String: Any]) async {
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    request.timeoutInterval = 10

    // A failed progress ping must not abort the scan: the browser simply keeps
    // showing the previous stage and the final POST is what matters.
    _ = try? await URLSession.shared.data(for: request)
  }
}
