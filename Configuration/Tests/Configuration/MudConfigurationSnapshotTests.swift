import Foundation
import Testing
import MudCore
@testable import MudConfiguration

@Suite("MudConfiguration snapshot")
struct MudConfigurationSnapshotTests {
    @Test func emptySuiteReturnsDefaults() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }

        let snap = tc.config.snapshot()

        #expect(snap.theme == .earthy)
        #expect(snap.upModeZoomLevel == 1.0)
        #expect(snap.allowRemoteContent == true)
        #expect(snap.doccAlertMode == .extended)
        // lineNumbers, wordWrap, codeHeader default true;
        // readableColumn and autoExpandChanges default false.
        #expect(snap.viewToggles == [
            .lineNumbers, .wordWrap, .codeHeader,
        ])
        #expect(snap.enabledExtensions == [])
    }

    @Test func snapshotReflectsEachField() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }

        tc.config.writeTheme(.blues)
        tc.config.writeUpModeZoomLevel(1.25)
        tc.config.writeAllowRemoteContent(false)
        tc.config.writeDoccAlertMode(.common)
        tc.config.writeViewToggle(.readableColumn, enabled: false)
        tc.config.writeViewToggle(.lineNumbers, enabled: true)
        tc.config.writeViewToggle(.wordWrap, enabled: false)
        tc.config.writeViewToggle(.codeHeader, enabled: false)
        tc.config.writeEnabledExtensions(["alpha"])

        let all: Set<String> = ["alpha", "beta"]
        let snap = tc.config.snapshot(defaultEnabledExtensions: all)

        #expect(snap.theme == .blues)
        #expect(snap.upModeZoomLevel == 1.25)
        #expect(snap.allowRemoteContent == false)
        #expect(snap.doccAlertMode == .common)
        #expect(snap.viewToggles == [.lineNumbers])
        #expect(snap.enabledExtensions == ["alpha"])
    }

    // MARK: - upModeHTMLClasses

    @Test func upModeHTMLClassesIncludesAllThree() {
        let snap = MudConfigurationSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.readableColumn, .wordWrap, .lineNumbers],
            allowRemoteContent: true, enabledExtensions: [],
            doccAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses == [
            "is-readable-column", "has-word-wrap", "has-line-numbers",
        ])
    }

    @Test func upModeHTMLClassesExcludesDownModeOnly() {
        let snap = MudConfigurationSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.readableColumn, .codeHeader, .autoExpandChanges],
            allowRemoteContent: true, enabledExtensions: [],
            doccAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses == ["is-readable-column"])
    }

    @Test func upModeHTMLClassesEmptyWhenNoUpToggles() {
        let snap = MudConfigurationSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.codeHeader, .autoExpandChanges],
            allowRemoteContent: true, enabledExtensions: [],
            doccAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses.isEmpty)
    }
}
