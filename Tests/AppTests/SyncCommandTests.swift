import Foundation
@testable import App
import Testing
import Vapor

@Suite struct SyncCommandTests {
    @Test func boxAndRegionCannotBeCombined() async throws {
        let app = try await Application.make(.testing)
        var context = CommandContext(console: app.console, input: CommandInput(arguments: ["sync", "ecmwf_ifs025", "temperature_2m", "--bounding-box", "1,2,3,4", "--region", "a.json"]))
        context.application = app
        await #expect(throws: ForecastApiError.self) { try await SyncCommand().run(using: &context) }
        try await app.asyncShutdown()
    }
}
