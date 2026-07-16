// QuickLookView — the AppKit QLPreviewView wrapped for SwiftUI (ho-16).
//
// The preview pane hands local images, PDFs, and any quick-lookable type to
// QuickLook, which renders and streams large files itself. SwiftUI has no
// native QuickLook view, so this NSViewRepresentable bridges QLPreviewView.
// It is the view/AppKit part of the ho — coverage-excluded like the other
// declarative view bodies; the routing that decides when it is shown is
// PalanaCore's tested PreviewRouter.

import Quartz
import SwiftUI

/// A SwiftUI wrapper over `QLPreviewView`, pointed at a local file URL.
struct QuickLookView: NSViewRepresentable {
    /// The local file to preview.
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        // .compact drops QuickLook's own toolbar — the pane is the chrome.
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        // Re-point only when the file actually changed — reassigning the same
        // item reloads and flickers.
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}
