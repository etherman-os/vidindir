import Testing
@testable import Vidindir

@Suite("App preference defaults")
struct AppPreferenceDefaultsTests {
    @Test("clipboard suggestions require explicit opt-in")
    func clipboardSuggestionsRequireOptIn() {
        #expect(AppPreferenceDefaults.clipboardSuggestions == false)
    }
}
