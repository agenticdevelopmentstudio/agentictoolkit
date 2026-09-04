import CodeEditLanguages
import Foundation

public enum LanguageDetection {
    /// Detects the CodeLanguage for a given file URL based on its extension.
    ///
    /// Consults user-defined custom file type mappings first. If a custom
    /// mapping exists for the file's extension, attempts to find a matching
    /// CodeLanguage by name. Falls back to the built-in CodeEditLanguages
    /// detection, and ultimately to `.default` (plain text).
    public static func language(for url: URL) -> CodeLanguage {
        let ext = url.pathExtension.lowercased()

        // Check custom mappings first
        if !ext.isEmpty, let custom = CustomFileTypeMappings.mapping(for: ext) {
            // Try to find a matching CodeLanguage by the custom language name
            let customName = custom.languageName.lowercased()
            if let match = CodeLanguage.allLanguages.first(where: {
                $0.tsName.lowercased() == customName
                || $0.extensions.contains(where: { $0.lowercased() == customName })
            }) {
                return match
            }
        }

        return CodeLanguage.detectLanguageFrom(url: url)
    }

    /// Maps a detected `CodeLanguage` to the language identifier the Language
    /// Server Protocol expects (the `languageId` on `textDocument/didOpen`,
    /// etc.) — see the LSP spec's "Text Document Item" `languageId` table
    /// (`csharp`, `javascriptreact`, `shellscript`, `plaintext`, ...).
    /// `CodeEditLanguages.TreeSitterLanguage`'s raw values are named for
    /// tree-sitter grammars, not LSP, and disagree with the spec in exactly
    /// the cases enumerated below (`cSharp` vs `csharp`, `jsx` vs
    /// `javascriptreact`, `bash` vs `shellscript`, `objc` vs `objective-c`,
    /// `plainText` vs `plaintext`, `goMod`/`ocamlInterface`, `markdownInline`).
    /// Every other language's tree-sitter raw value already matches its LSP
    /// identifier (`swift`, `python`, `json`, `html`, `css`, `yaml`, ...), so
    /// only the mismatches are special-cased and everything else falls
    /// through to the raw value. This is the single place that mapping is
    /// made — nowhere else in the toolkit should derive an LSP `languageId`
    /// from a file extension independently.
    public static func lspLanguageId(for language: CodeLanguage) -> String {
        switch language.id {
        case .bash: return "shellscript"
        case .cSharp: return "csharp"
        case .jsx: return "javascriptreact"
        case .tsx: return "typescriptreact"
        case .objc: return "objective-c"
        case .plainText: return "plaintext"
        case .goMod: return "go.mod"
        case .ocamlInterface: return "ocaml.interface"
        case .markdownInline: return "markdown"
        default: return language.id.rawValue
        }
    }
}
