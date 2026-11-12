import Foundation

/// Bundled JavaScript engines (MathJax, Mermaid), inlined into a rendered
/// document only when it uses them. Quick Look never runs scripts.
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
      var tasks = [];
      if (window.mermaid) { tasks.push(mermaid.run()); }
      if (window.MathJax && MathJax.startup) { tasks.push(MathJax.startup.promise); }
      Promise.allSettled(tasks).then(function () { window.__mpReady = true; });
    })();
    """

    private static let cache = Cache()

    private static func load(_ name: String) -> String? {
        if let cached = cache.get(name) { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "vendor")
            ?? Bundle.main.url(forResource: name, withExtension: "js")
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
