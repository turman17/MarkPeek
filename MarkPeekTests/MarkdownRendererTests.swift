import XCTest

final class MarkdownRendererTests: XCTestCase {
    private let theme = Theme.modern

    private func fragment(_ md: String, sourceMap: Bool = false) -> String {
        MarkdownRenderer.fragment(markdown: md, theme: theme, options: RenderOptions(sourceMap: sourceMap))
    }

    func testBasicBlocks() {
        let html = fragment("# Title\n\nSome *text* with `code`.\n\n- [x] done\n")
        XCTAssertTrue(html.contains("<h1 id=\"title\">Title</h1>"))
        XCTAssertTrue(html.contains("<em>text</em>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("class=\"task done\""))
    }

    func testScriptsAndHandlersAreRemoved() {
        let md = """
        <div onclick="alert(1)" class="x">hi</div>

        <script>alert('xss')</script>

        Inline <a href="javascript:alert(1)">link</a> and <img src=x onerror="alert(1)">
        """
        let html = fragment(md)
        XCTAssertFalse(html.lowercased().contains("<script"))
        XCTAssertFalse(html.lowercased().contains("onclick"))
        XCTAssertFalse(html.lowercased().contains("onerror"))
        XCTAssertFalse(html.lowercased().contains("javascript:"))
        XCTAssertTrue(html.contains("class=\"x\""), "harmless attributes survive")
    }

    func testSourceMapLinesSurviveFrontMatterAndMath() {
        let md = """
        ---
        title: T
        ---

        # Heading

        $$
        x = 1
        $$

        Para
        """
        let html = fragment(md, sourceMap: true)
        XCTAssertTrue(html.contains("<h1 id=\"heading\" data-line=\"5-5\">"), html)
        XCTAssertTrue(html.contains("<div class=\"math-display\" data-line=\"7-9\">"),
                      "display math replaces its paragraph, so hover covers the formula: \(html)")
        XCTAssertFalse(html.contains("<p data-line=\"7-9\">"), html)
        XCTAssertTrue(html.contains("<p data-line=\"11-11\">Para</p>"), html)
        XCTAssertFalse(fragment(md).contains("data-line"), "exports stay clean")
    }

    func testOutlineAndHeadingIds() {
        let outline = MarkdownRenderer.outline(markdown: "# A b\n## A b\n### C!\n")
        XCTAssertEqual(outline.map(\.id), ["a-b", "a-b-2", "c"])
        XCTAssertEqual(outline.map(\.level), [1, 2, 3])
    }

    func testFeaturesDetection() {
        XCTAssertTrue(MarkdownRenderer.features(of: "```mermaid\ngraph TD\n```").mermaid)
        XCTAssertTrue(MarkdownRenderer.features(of: "cost is $5 and $x^2$ math").math)
        XCTAssertFalse(MarkdownRenderer.features(of: "costs $5 and $10").math)
    }

    func testFrontMatterTable() {
        let html = fragment("---\nauthor: Me\n---\n\nText\n")
        XCTAssertTrue(html.contains("mp-frontmatter"))
        XCTAssertTrue(html.contains("<th>author</th><td>Me</td>"))
    }
}
