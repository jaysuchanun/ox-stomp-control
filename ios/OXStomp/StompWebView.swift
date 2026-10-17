import SwiftUI
import UIKit
import WebKit

/// Hosts ox-stomp-control.html and gives it a Web MIDI–compatible
/// `navigator.requestMIDIAccess()` backed by CoreMIDI, so the page runs unchanged.
struct StompWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = config.userContentController
        controller.addUserScript(WKUserScript(source: Coordinator.webMIDIShim,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.add(context.coordinator, name: "midi")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "ox-stomp-control", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        private let midi = MIDIBridge()

        override init() {
            super.init()
            midi.onSetupChanged = { [weak self] in self?.pushDevices(resolveAccess: false) }
        }

        // Messages from the page: {cmd:"list"} | {cmd:"send", id, data:[bytes]} | {cmd:"export", name, json}
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
            switch cmd {
            case "list":
                pushDevices(resolveAccess: true)
            case "send":
                guard let idString = body["id"] as? String, let uid = Int32(idString),
                      let data = body["data"] as? [NSNumber] else { return }
                midi.send(toUniqueID: uid, bytes: data.map { $0.uint8Value })
            case "export":
                guard let json = body["json"] as? String else { return }
                share(json: json, fileName: body["name"] as? String ?? "ox-stomp-snapshots.json")
            default:
                break
            }
        }

        private func pushDevices(resolveAccess: Bool) {
            guard let data = try? JSONSerialization.data(withJSONObject: midi.destinations()),
                  let json = String(data: data, encoding: .utf8) else { return }
            var js = "window.__oxMidiUpdate(\(json));"
            if resolveAccess { js += "window.__oxMidiResolve && window.__oxMidiResolve();" }
            webView?.evaluateJavaScript(js)
        }

        private func share(json: String, fileName: String) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do { try json.write(to: url, atomically: true, encoding: .utf8) } catch { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = webView
            present(sheet)
        }

        // MARK: alert / confirm / prompt — WKWebView ignores them unless the app shows them

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, orElse: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, orElse: { completionHandler(false) })
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            present(alert, orElse: { completionHandler(nil) })
        }

        private func present(_ vc: UIViewController, orElse fallback: (() -> Void)? = nil) {
            guard var top = webView?.window?.rootViewController else { fallback?(); return }
            while let presented = top.presentedViewController { top = presented }
            top.present(vc, animated: true)
        }

        // MARK: Web MIDI shim injected before the page's own script runs

        static let webMIDIShim = """
        (function () {
          var outputs = new Map(), inputs = new Map(), access = null;
          function makeOutput(d) {
            return {
              id: d.id, name: d.name || "MIDI device", manufacturer: d.manufacturer || "",
              type: "output", state: "connected", connection: "open",
              send: function (data) {
                window.webkit.messageHandlers.midi.postMessage({ cmd: "send", id: d.id, data: Array.from(data) });
              },
              open: function () { return Promise.resolve(this); },
              close: function () { return Promise.resolve(this); }
            };
          }
          window.__oxMidiUpdate = function (list) {
            outputs.clear();
            list.forEach(function (d) { outputs.set(d.id, makeOutput(d)); });
            if (access && typeof access.onstatechange === "function") access.onstatechange({ port: null });
          };
          navigator.requestMIDIAccess = function () {
            return new Promise(function (resolve) {
              access = access || { inputs: inputs, outputs: outputs, sysexEnabled: false, onstatechange: null };
              window.__oxMidiResolve = function () { window.__oxMidiResolve = null; resolve(access); };
              window.webkit.messageHandlers.midi.postMessage({ cmd: "list" });
            });
          };
        })();
        """
    }
}
