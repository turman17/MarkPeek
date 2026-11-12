import Foundation

/// Lightweight, dependency-free syntax highlighting for fenced code blocks.
/// Produces escaped HTML with `<span class="tok-…">` wrappers, line by line,
/// so it works wherever the rest of the HTML works: the app, Quick Look, PDF.
public enum SyntaxHighlighter {

    public enum Kind: String, CaseIterable, Sendable {
        case keyword = "kw", string = "str", comment = "cm", number = "num"
        case type = "type", function = "fn", attribute = "attr"
    }

    /// True when a language name (or alias) has a highlighting spec.
    public static func supports(_ language: String) -> Bool {
        spec(for: language) != nil
    }

    /// Escaped HTML, one entry per source line. Spans never cross lines.
    public static func htmlLines(_ code: String, language: String) -> [String]? {
        guard let spec = spec(for: language) else { return nil }
        var scanner = Scanner(code: code, spec: spec)
        let tokens = scanner.scan()
        var lines: [String] = [""]
        for token in tokens {
            let parts = token.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append("") }
                guard !part.isEmpty else { continue }
                let escaped = escape(String(part))
                if let kind = token.kind {
                    lines[lines.count - 1] += "<span class=\"tok-\(kind.rawValue)\">\(escaped)</span>"
                } else {
                    lines[lines.count - 1] += escaped
                }
            }
        }
        return lines
    }

    // MARK: - Language specs

    struct Spec {
        var keywords: Set<String> = []
        var types: Set<String> = []
        var lineComments: [String] = []
        var blockComments: [(String, String)] = []
        var quotes: [Character] = ["\"", "'"]
        var tripleQuotes = false
        var attributePrefix: Character? = nil   // @decorator, @objc, #[rust]
        var capitalizedIsType = true
        var caseInsensitive = false
        var keyBeforeColon = false            // json / yaml / css property names
        var preprocessor = false              // #include
        var shellVariables = false            // $NAME
        var bangMacros = false                // println!
        var markup = false                    // <tag attr="…">
        var identifierExtras: Set<Character> = ["_"]
    }

    private static let cFamilyKeywords: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return",
        "goto", "sizeof", "typedef", "struct", "union", "enum", "const", "static", "extern", "inline",
        "volatile", "register", "auto", "class", "public", "private", "protected", "virtual", "template",
        "typename", "namespace", "using", "new", "delete", "this", "nullptr", "true", "false", "try",
        "catch", "throw", "operator", "friend", "explicit", "constexpr", "override", "final", "NULL",
        "@interface", "@implementation", "@end", "@property", "@synthesize", "@protocol", "@selector",
        "self", "super", "nil", "YES", "NO", "import", "include", "define", "pragma", "ifdef", "ifndef", "endif",
    ]

    static func spec(for language: String) -> Spec? {
        switch language.lowercased() {
        case "swift":
            var s = Spec()
            s.keywords = ["func", "let", "var", "if", "else", "for", "while", "repeat", "return", "import", "struct",
                          "class", "enum", "protocol", "extension", "guard", "switch", "case", "default", "break",
                          "continue", "in", "where", "init", "deinit", "self", "Self", "super", "throws", "throw",
                          "try", "catch", "async", "await", "actor", "static", "final", "private", "public",
                          "internal", "fileprivate", "open", "override", "mutating", "nonmutating", "some", "any",
                          "is", "as", "nil", "true", "false", "defer", "do", "inout", "typealias", "associatedtype",
                          "subscript", "lazy", "weak", "unowned", "convenience", "required", "optional", "dynamic",
                          "indirect", "rethrows", "operator", "infix", "prefix", "postfix", "willSet", "didSet",
                          "get", "set", "fallthrough", "nonisolated", "isolated", "consuming", "borrowing", "macro"]
            s.types = ["Int", "Double", "Float", "String", "Bool", "Character", "Array", "Dictionary", "Set",
                       "Optional", "Void", "Any", "AnyObject", "Error", "Result", "Data", "Date", "URL", "UUID"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.quotes = ["\""]; s.tripleQuotes = true; s.attributePrefix = "@"
            return s
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs", "cjs":
            var s = Spec()
            s.keywords = ["function", "const", "let", "var", "if", "else", "for", "while", "do", "return", "import",
                          "export", "from", "default", "class", "extends", "new", "this", "super", "switch", "case",
                          "break", "continue", "try", "catch", "finally", "throw", "typeof", "instanceof", "in",
                          "of", "delete", "void", "yield", "async", "await", "static", "get", "set", "null",
                          "undefined", "true", "false", "interface", "type", "enum", "implements", "declare",
                          "namespace", "abstract", "readonly", "public", "private", "protected", "as", "any",
                          "never", "unknown", "keyof", "satisfies", "with", "debugger"]
            s.types = ["string", "number", "boolean", "object", "symbol", "bigint", "Promise", "Array", "Map",
                       "Set", "Date", "Object", "String", "Number", "Boolean", "Error", "RegExp", "JSON", "Math"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.quotes = ["\"", "'", "`"]; s.attributePrefix = "@"; s.identifierExtras = ["_", "$"]
            return s
        case "py", "python", "python3":
            var s = Spec()
            s.keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as",
                          "with", "try", "except", "finally", "raise", "pass", "break", "continue", "lambda",
                          "yield", "global", "nonlocal", "assert", "del", "in", "is", "not", "and", "or", "None",
                          "True", "False", "async", "await", "self", "cls", "match", "case", "print"]
            s.types = ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type", "range"]
            s.lineComments = ["#"]; s.tripleQuotes = true; s.attributePrefix = "@"
            return s
        case "go", "golang":
            var s = Spec()
            s.keywords = ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan",
                          "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "return",
                          "go", "defer", "select", "fallthrough", "goto", "nil", "true", "false", "iota", "make",
                          "new", "len", "cap", "append", "panic", "recover"]
            s.types = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64",
                       "float32", "float64", "string", "bool", "byte", "rune", "error", "any", "uintptr", "complex128"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.quotes = ["\"", "'", "`"]; s.capitalizedIsType = false
            return s
        case "rs", "rust":
            var s = Spec()
            s.keywords = ["fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "for", "in", "if", "else",
                          "match", "while", "loop", "return", "use", "mod", "crate", "self", "Self", "super", "as",
                          "where", "unsafe", "async", "await", "move", "ref", "static", "const", "type", "dyn",
                          "break", "continue", "true", "false", "extern", "macro_rules"]
            s.types = ["i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128", "usize", "isize",
                       "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.quotes = ["\""]; s.attributePrefix = "#"; s.bangMacros = true
            return s
        case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "m", "mm", "cs", "csharp", "cu":
            var s = Spec()
            s.keywords = cFamilyKeywords.union(["int", "char", "float", "double", "void", "long", "short",
                                                 "unsigned", "signed", "bool", "string", "var", "foreach", "is",
                                                 "as", "null", "readonly", "sealed", "abstract", "interface",
                                                 "internal", "async", "await", "out", "ref", "params", "base"])
            s.types = ["size_t", "uint8_t", "int32_t", "int64_t", "uint32_t", "uint64_t", "NSString", "NSArray",
                       "NSDictionary", "NSObject", "id", "BOOL", "CGFloat", "NSInteger", "std"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.preprocessor = true; s.attributePrefix = "@"
            return s
        case "java", "kt", "kotlin", "kts", "scala", "groovy", "dart":
            var s = Spec()
            s.keywords = ["class", "interface", "enum", "object", "fun", "val", "var", "when", "data", "sealed",
                          "companion", "override", "open", "abstract", "lateinit", "init", "is", "in", "as", "null",
                          "true", "false", "return", "if", "else", "for", "while", "do", "try", "catch", "finally",
                          "throw", "throws", "import", "package", "this", "super", "suspend", "inline", "reified",
                          "by", "get", "set", "public", "private", "protected", "internal", "static", "final",
                          "new", "extends", "implements", "instanceof", "switch", "case", "break", "continue",
                          "default", "void", "int", "long", "double", "float", "boolean", "char", "byte", "short",
                          "const", "late", "async", "await", "yield", "extension", "mixin", "typedef", "with",
                          "synchronized", "volatile", "transient", "native", "assert", "where", "typealias", "out"]
            s.types = ["String", "Int", "Long", "Double", "Float", "Boolean", "Char", "List", "Map", "Set", "Unit",
                       "Any", "Nothing", "Array", "Object", "Integer", "Future", "Stream"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.tripleQuotes = true; s.attributePrefix = "@"
            return s
        case "rb", "ruby":
            var s = Spec()
            s.keywords = ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for",
                          "do", "begin", "rescue", "ensure", "return", "yield", "self", "nil", "true", "false",
                          "and", "or", "not", "require", "require_relative", "include", "extend", "attr_accessor",
                          "attr_reader", "attr_writer", "puts", "print", "lambda", "proc", "then", "case", "when",
                          "in", "raise", "super", "new", "private", "public", "protected", "alias", "defined?"]
            s.lineComments = ["#"]; s.attributePrefix = "@"; s.shellVariables = false
            return s
        case "sh", "bash", "zsh", "shell", "console", "fish":
            var s = Spec()
            s.keywords = ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
                          "function", "in", "return", "exit", "export", "local", "echo", "cd", "source", "set",
                          "unset", "readonly", "shift", "break", "continue", "true", "false", "sudo", "cat", "grep",
                          "sed", "awk", "mkdir", "rm", "cp", "mv", "ls", "chmod", "git", "brew", "npm", "swift",
                          "xcodebuild", "open", "pkill", "printf", "test", "eval", "exec", "trap", "select"]
            s.lineComments = ["#"]; s.shellVariables = true; s.capitalizedIsType = false
            s.identifierExtras = ["_", "-"]
            return s
        case "php":
            var s = Spec()
            s.keywords = ["function", "class", "interface", "trait", "extends", "implements", "public", "private",
                          "protected", "static", "abstract", "final", "const", "var", "new", "return", "if", "else",
                          "elseif", "for", "foreach", "while", "do", "switch", "case", "break", "continue",
                          "default", "try", "catch", "finally", "throw", "use", "namespace", "echo", "print",
                          "null", "true", "false", "as", "instanceof", "array", "fn", "match", "yield", "require",
                          "include", "require_once", "include_once", "isset", "empty", "unset", "self", "parent"]
            s.lineComments = ["//", "#"]; s.blockComments = [("/*", "*/")]
            s.shellVariables = true; s.attributePrefix = "#"
            return s
        case "sql", "mysql", "postgres", "postgresql", "sqlite", "psql":
            var s = Spec()
            s.keywords = ["select", "from", "where", "insert", "into", "update", "delete", "set", "values", "create",
                          "table", "drop", "alter", "add", "column", "join", "left", "right", "inner", "outer",
                          "full", "cross", "on", "group", "by", "order", "having", "limit", "offset", "as", "and",
                          "or", "not", "null", "is", "in", "like", "between", "distinct", "union", "all", "primary",
                          "key", "foreign", "references", "index", "view", "default", "exists", "case", "when",
                          "then", "else", "end", "begin", "commit", "rollback", "transaction", "asc", "desc",
                          "true", "false", "with", "returning", "constraint", "unique", "cascade", "if", "replace"]
            s.types = ["int", "integer", "bigint", "smallint", "text", "varchar", "char", "boolean", "bool",
                       "date", "timestamp", "datetime", "float", "real", "double", "decimal", "numeric", "blob",
                       "json", "jsonb", "uuid", "serial"]
            s.lineComments = ["--"]; s.blockComments = [("/*", "*/")]
            s.quotes = ["'", "\""]; s.caseInsensitive = true; s.capitalizedIsType = false
            return s
        case "json", "jsonc", "json5":
            var s = Spec()
            s.keywords = ["true", "false", "null"]
            s.lineComments = ["//"]; s.blockComments = [("/*", "*/")]
            s.keyBeforeColon = true; s.capitalizedIsType = false
            return s
        case "yaml", "yml":
            var s = Spec()
            s.keywords = ["true", "false", "null", "yes", "no", "on", "off", "~"]
            s.lineComments = ["#"]; s.keyBeforeColon = true; s.capitalizedIsType = false
            s.identifierExtras = ["_", "-", "."]
            return s
        case "toml", "ini", "cfg", "conf", "properties", "env", "dotenv":
            var s = Spec()
            s.keywords = ["true", "false"]
            s.lineComments = ["#", ";"]; s.keyBeforeColon = true; s.capitalizedIsType = false
            s.tripleQuotes = true; s.identifierExtras = ["_", "-", "."]
            return s
        case "html", "xml", "svg", "xhtml", "vue", "plist", "xaml":
            var s = Spec()
            s.blockComments = [("<!--", "-->")]; s.markup = true; s.capitalizedIsType = false
            s.identifierExtras = ["_", "-", ":"]
            return s
        case "css", "scss", "less":
            var s = Spec()
            s.keywords = ["important", "inherit", "initial", "unset", "none", "auto", "flex", "grid", "block",
                          "inline", "absolute", "relative", "fixed", "sticky", "solid", "bold", "italic", "center"]
            s.blockComments = [("/*", "*/")]; s.lineComments = ["//"]
            s.keyBeforeColon = true; s.capitalizedIsType = false; s.attributePrefix = "@"
            s.identifierExtras = ["_", "-"]
            return s
        case "md", "markdown", "diff", "text", "txt", "plain", "":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Scanner

    struct Token {
        var kind: Kind?
        var text: String
    }

    private struct Scanner {
        let chars: [Character]
        let spec: Spec
        var i = 0
        var tokens: [Token] = []
        var plain = ""

        init(code: String, spec: Spec) {
            chars = Array(code)
            self.spec = spec
        }

        mutating func scan() -> [Token] {
            while i < chars.count {
                if scanComment() || scanString() || scanNumber() || scanAttribute() || scanMarkupTag() || scanIdentifier() {
                    continue
                }
                plain.append(chars[i])
                i += 1
            }
            flushPlain()
            return tokens
        }

        // MARK: helpers

        private func matches(_ s: String, at index: Int) -> Bool {
            let pattern = Array(s)
            guard index + pattern.count <= chars.count else { return false }
            for (offset, ch) in pattern.enumerated() where chars[index + offset] != ch { return false }
            return true
        }

        private mutating func flushPlain() {
            if !plain.isEmpty { tokens.append(Token(kind: nil, text: plain)); plain = "" }
        }

        private mutating func emit(_ kind: Kind?, from start: Int, to end: Int) {
            flushPlain()
            tokens.append(Token(kind: kind, text: String(chars[start..<end])))
            i = end
        }

        private func atLineStart(_ index: Int) -> Bool {
            var j = index - 1
            while j >= 0, chars[j] == " " || chars[j] == "\t" { j -= 1 }
            return j < 0 || chars[j] == "\n"
        }

        private func isIdentStart(_ c: Character) -> Bool {
            c.isLetter || spec.identifierExtras.contains(c) && c != "-" && c != "." && c != ":"
        }

        private func isIdentChar(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || spec.identifierExtras.contains(c)
        }

        private func nextNonSpace(after index: Int) -> Character? {
            var j = index
            while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
            return j < chars.count ? chars[j] : nil
        }

        // MARK: scanners

        private mutating func scanComment() -> Bool {
            for (open, close) in spec.blockComments where matches(open, at: i) {
                var j = i + open.count
                while j < chars.count, !matches(close, at: j) { j += 1 }
                emit(.comment, from: i, to: min(chars.count, j + close.count))
                return true
            }
            for marker in spec.lineComments where matches(marker, at: i) {
                // "#" is only a comment when it isn't a preprocessor line or shell variable.
                if marker == "#", spec.preprocessor { continue }
                var j = i
                while j < chars.count, chars[j] != "\n" { j += 1 }
                emit(.comment, from: i, to: j)
                return true
            }
            return false
        }

        private mutating func scanString() -> Bool {
            let c = chars[i]
            if spec.tripleQuotes, matches("\"\"\"", at: i) || matches("'''", at: i) {
                let quote = String(repeating: c, count: 3)
                var j = i + 3
                while j < chars.count, !matches(quote, at: j) { j += 1 }
                emit(.string, from: i, to: min(chars.count, j + 3))
                return true
            }
            guard spec.quotes.contains(c) else { return false }
            // Rust lifetimes / Swift-style apostrophes in prose: require a closing quote on the line.
            var j = i + 1
            let multiline = c == "`"
            while j < chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if chars[j] == c { break }
                if chars[j] == "\n", !multiline { return false }
                j += 1
            }
            if j >= chars.count && !multiline { return false }
            emit(.string, from: i, to: min(chars.count, j + 1))
            return true
        }

        private mutating func scanNumber() -> Bool {
            let c = chars[i]
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            guard c.isNumber, prev == nil || !isIdentChar(prev!) else { return false }
            var j = i + 1
            while j < chars.count {
                let d = chars[j]
                if d.isNumber || d.isHexDigit || d == "_" || d == "." || d == "x" || d == "o" || d == "b"
                    || ((d == "e" || d == "E") && j + 1 < chars.count && (chars[j + 1].isNumber || chars[j + 1] == "-")) {
                    j += 1
                } else if (d == "-" || d == "+") && (chars[j - 1] == "e" || chars[j - 1] == "E") {
                    j += 1
                } else if d.isLetter, spec.keyBeforeColon || spec.markup { // 12px, 1.5em
                    j += 1
                } else {
                    break
                }
            }
            emit(.number, from: i, to: j)
            return true
        }

        private mutating func scanAttribute() -> Bool {
            let c = chars[i]
            if spec.shellVariables, c == "$" {
                var j = i + 1
                if j < chars.count, chars[j] == "{" {
                    while j < chars.count, chars[j] != "}" { j += 1 }
                    emit(.attribute, from: i, to: min(chars.count, j + 1))
                    return true
                }
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "@" || chars[j] == "?" || chars[j] == "#" { j += 1 }
                if j > i + 1 { emit(.attribute, from: i, to: j); return true }
                return false
            }
            if spec.preprocessor, c == "#", atLineStart(i) {
                var j = i + 1
                while j < chars.count, chars[j].isLetter { j += 1 }
                emit(.attribute, from: i, to: j)
                return true
            }
            guard let prefix = spec.attributePrefix, c == prefix else { return false }
            if spec.bangMacros, i + 1 < chars.count, chars[i + 1] == "[" || (chars[i + 1] == "!" && i + 2 < chars.count && chars[i + 2] == "[") {
                var j = i
                while j < chars.count, chars[j] != "]", chars[j] != "\n" { j += 1 }
                emit(.attribute, from: i, to: min(chars.count, j + 1))
                return true
            }
            var j = i + 1
            while j < chars.count, isIdentChar(chars[j]) || chars[j] == "." { j += 1 }
            guard j > i + 1 else { return false }
            emit(.attribute, from: i, to: j)
            return true
        }

        private mutating func scanMarkupTag() -> Bool {
            guard spec.markup, chars[i] == "<" else { return false }
            var j = i + 1
            if j < chars.count, chars[j] == "/" || chars[j] == "?" || chars[j] == "!" { j += 1 }
            let nameStart = j
            while j < chars.count, isIdentChar(chars[j]) { j += 1 }
            guard j > nameStart else { return false }
            emit(.keyword, from: i, to: j)
            // Attributes until the closing ">".
            while i < chars.count, chars[i] != ">" {
                let c = chars[i]
                if c == "\"" || c == "'" {
                    var k = i + 1
                    while k < chars.count, chars[k] != c { k += 1 }
                    emit(.string, from: i, to: min(chars.count, k + 1))
                } else if isIdentStart(c) {
                    var k = i
                    while k < chars.count, isIdentChar(chars[k]) { k += 1 }
                    emit(.attribute, from: i, to: k)
                } else {
                    plain.append(c); i += 1
                }
            }
            if i < chars.count { emit(.keyword, from: i, to: i + 1) }
            return true
        }

        private mutating func scanIdentifier() -> Bool {
            let c = chars[i]
            guard isIdentStart(c) else { return false }
            var j = i + 1
            while j < chars.count, isIdentChar(chars[j]) { j += 1 }
            let word = String(chars[i..<j])
            let lookup = spec.caseInsensitive ? word.lowercased() : word
            let next = nextNonSpace(after: j)
            let kind: Kind?
            if spec.keyBeforeColon, next == ":" || next == "=" {
                kind = .attribute
            } else if spec.keywords.contains(lookup) {
                kind = .keyword
            } else if spec.types.contains(word) {
                kind = .type
            } else if spec.bangMacros, next == "!", j < chars.count, chars[j] == "!" {
                emit(.function, from: i, to: j + 1)
                return true
            } else if next == "(" {
                kind = .function
            } else if spec.capitalizedIsType, let first = word.first, first.isUppercase, word.count > 1 {
                kind = .type
            } else {
                kind = nil
            }
            if kind == nil {
                plain += word
                i = j
            } else {
                emit(kind, from: i, to: j)
            }
            return true
        }
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}
