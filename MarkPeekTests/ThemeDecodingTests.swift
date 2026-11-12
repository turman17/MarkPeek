import XCTest

final class ThemeDecodingTests: XCTestCase {
    func testEmptyObjectDecodesToDefaults() throws {
        let theme = try Theme.decode(Data("{}".utf8))
        XCTAssertEqual(theme.name, "Untitled")
        XCTAssertEqual(theme.typography.fontSize, 16)
        XCTAssertEqual(theme.light, .defaultLight)
        XCTAssertEqual(theme.dark, .defaultDark)
    }

    func testPartialDarkPaletteKeepsDarkDefaults() throws {
        let json = ##"{ "name": "Night", "dark": { "link": "#FF00FF" } }"##
        let theme = try Theme.decode(Data(json.utf8))
        XCTAssertEqual(theme.dark.link, "#FF00FF")
        XCTAssertEqual(theme.dark.background, Theme.Palette.defaultDark.background, "missing dark keys must not fall back to light values")
        XCTAssertEqual(theme.dark.text, Theme.Palette.defaultDark.text)
        XCTAssertEqual(theme.dark.syntax, Theme.Palette.defaultDark.syntax)
        XCTAssertEqual(theme.dark.accent, "#FF00FF", "accent follows a supplied link")
    }

    func testPartialLightPaletteDerivesColors() throws {
        let json = ##"{ "light": { "background": "#FAFAF0", "text": "#222222", "syntax": { "keyword": "#123456" } } }"##
        let theme = try Theme.decode(Data(json.utf8))
        XCTAssertEqual(theme.light.heading, "#222222", "heading follows a supplied text color")
        XCTAssertEqual(theme.light.syntax.keyword, "#123456")
        XCTAssertEqual(theme.light.syntax.string, Theme.Palette.Syntax.defaultLight.string)
    }

    func testBuiltInThemesRoundTrip() throws {
        for theme in Theme.builtIn {
            let data = try theme.encoded()
            let decoded = try Theme.decode(data)
            XCTAssertEqual(decoded, theme, theme.name)
        }
    }

    func testWrongTypesFallBackInsteadOfFailing() throws {
        let json = #"{ "name": "Odd", "typography": { "fontSize": "big" }, "appearance": "sepia" }"#
        let theme = try Theme.decode(Data(json.utf8))
        XCTAssertEqual(theme.name, "Odd")
        XCTAssertEqual(theme.appearance, .system)
    }
}
