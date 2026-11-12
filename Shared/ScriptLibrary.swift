import Foundation

/// Bundled JavaScript engines (MathJax, Mermaid), inlined into a rendered
/// document only when it uses them. Quick Look can't run scripts, so its
/// extension runs them once offscreen and keeps the result (ScriptBaker).
enum ScriptLibrary {

    static func scripts(for features: DocumentFeatures, scheme: ThemeColorScheme?) -> [String] {
        var out: [String] = []
        if features.math, let mathjax = load("mathjax-tex-svg") {
            out.append(mathJaxConfig)
            out.append(mathjax)
        }
        if features.mermaid, let mermaid = load("mermaid.min") {
            out.append(mermaid)
            out.append(mermaidInit(scheme: scheme))
        }
        if !out.isEmpty { out.append(readyScript) }
        return out
    }

    private static let mathJaxConfig = """
    window.MathJax = {
      tex: { inlineMath: [['\\\\(', '\\\\)']], displayMath: [['\\\\[', '\\\\]']], processEscapes: true },
      svg: { fontCache: 'global' },
      options: { ignoreHtmlClass: 'mermaid|tok-.*', skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'] },
      startup: { typeset: true }
    };
    """

    private static func mermaidInit(scheme: ThemeColorScheme?) -> String {
        let dark: String = switch scheme {
        case .dark: "true"
        case .light: "false"
        case nil: "window.matchMedia('(prefers-color-scheme: dark)').matches"
        }
        return """
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: (\(dark)) ? 'dark' : 'default', fontFamily: 'inherit' });
        """
    }

    /// Sets `window.__mpReady` once engines finished, so exporters can wait.
    private static let readyScript = """
    (function () {
      window.__mpReady = false;
      // Remember each block's source before the engines replace it, so the
      // live preview can reuse renderings whose source didn't change.
      document.querySelectorAll('.mermaid, .math-inline, .math-display').forEach(function (el) {
        el.setAttribute('data-mp-src', el.textContent);
      });
      var tasks = [];
      if (window.mermaid) { tasks.push(mermaid.run()); }
      if (window.MathJax && MathJax.startup) { tasks.push(MathJax.startup.promise); }
      Promise.allSettled(tasks).then(function () { window.__mpReady = true; });
    })();
    """

    /// The app bundle holds the engines; an extension finds it two levels up
    /// (MarkPeek.app/Contents/PlugIns/X.appex).
    private static var resourceBundle: Bundle {
        let main = Bundle.main
        guard main.bundleURL.pathExtension == "appex" else { return main }
        let app = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app) ?? main
    }

    private static let cache = Cache()

    private static func load(_ name: String) -> String? {
        if let cached = cache.get(name) { return cached }
        let url = resourceBundle.url(forResource: name, withExtension: "js", subdirectory: "vendor")
            ?? resourceBundle.url(forResource: name, withExtension: "js")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        cache.set(name, text)
        return text
    }

    private final class Cache: @unchecked Sendable {
        private var store: [String: String] = [:]
        private let lock = NSLock()
        func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return store[key] }
        func set(_ key: String, _ value: String) { lock.lock(); store[key] = value; lock.unlock() }
    }
}
