import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Options for File ▸ Export as PDF. Choices are remembered between exports.
struct ExportSheet: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var themes = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.paper") private var paper: PDFExporter.Paper = .a4
    @AppStorage("export.orientation") private var orientation: PDFExporter.Orientation = .portrait
    @AppStorage("export.margins") private var margins: PDFExporter.Margins = .normal
    @AppStorage("export.layout") private var layout: PDFExporter.PageLayout = .pages
    @AppStorage("export.appearance") private var appearance: PDFExporter.Appearance = .theme
    @AppStorage("export.openAfter") private var openAfter = true
    @AppStorage("export.pageNumbers") private var pageNumbers = true
    @AppStorage("export.headerTitle") private var headerTitle = false

    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Paper") {
                    Picker("Size", selection: $paper) {
                        ForEach(PDFExporter.Paper.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Orientation", selection: $orientation) {
                        ForEach(PDFExporter.Orientation.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Margins", selection: $margins) {
                        ForEach(PDFExporter.Margins.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Document") {
                    Picker("Layout", selection: $layout) {
                        ForEach(PDFExporter.PageLayout.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(PDFExporter.Appearance.allCases) { Text($0.name).tag($0) }
                    }
                    LabeledContent("Theme", value: themes.activeLabel)
                    Toggle("Page numbers", isOn: $pageNumbers)
                        .disabled(layout == .continuous)
                    Toggle("Title at the top of each page", isOn: $headerTitle)
                        .disabled(layout == .continuous)
                    Toggle("Open in Preview when done", isOn: $openAfter)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if isExporting {
                    ProgressView().controlSize(.small)
                    Text("Exporting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { Task { await export() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
            }
            .padding(Design.Space.l)
        }
        .frame(width: 440, height: 500)
    }

    private func export() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (document.title as NSString).deletingPathExtension + ".pdf"
        panel.directoryURL = document.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        errorMessage = nil
        let options = PDFExporter.Options(
            paper: paper, orientation: orientation, margins: margins, layout: layout, appearance: appearance,
            pageNumbers: pageNumbers, headerTitle: headerTitle)
        let scheme = PDFExporter.resolvedScheme(for: themes.active, preferred: appearance)
        let features = MarkdownRenderer.features(of: document.draft)
        let html = MarkdownRenderer.document(
            markdown: document.draft, theme: themes.active,
            options: RenderOptions(surface: .print, colorScheme: scheme, imageResolver: document.imageResolver,
                                   scripts: ScriptLibrary.scripts(for: features, scheme: scheme)))
        do {
            try await PDFExporter.export(html: html, baseURL: document.folderURL, options: options, scheme: scheme, to: url,
                                         title: (document.title as NSString).deletingPathExtension)
            isExporting = false
            if openAfter { NSWorkspace.shared.open(url) }
            dismiss()
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }
}
