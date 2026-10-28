import Foundation
import Testing
@testable import FleetConsoleApp

struct TaskComposerTests {
    @MainActor @Test func workingDirectoryDefaultsToCurrentUsersHome() {
        let model = TaskComposerModel()
        #expect(model.cwd == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @MainActor @Test func emptyWorkingDirectoryUsesCurrentUsersHome() throws {
        let model = TaskComposerModel()
        model.taskName = "Fixture task"
        model.command = "/usr/bin/true"
        model.cwd = ""
        let request = try #require(model.validated())
        #expect(request.cwd == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @MainActor @Test func explicitWorkingDirectoryIsPreserved() throws {
        let model = TaskComposerModel()
        model.taskName = "Fixture task"
        model.command = "/usr/bin/true"
        model.cwd = "/Users/operator/project"
        let request = try #require(model.validated())
        #expect(request.cwd == "/Users/operator/project")
    }
}
