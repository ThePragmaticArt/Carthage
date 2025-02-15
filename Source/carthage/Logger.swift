import Foundation
import CarthageKit
import Commandant
import Result
import ReactiveSwift
import ReactiveTask

/// Logs project events put into the sink.
final class ProjectEventLogger {
    private let colorOptions: ColorOptions

    init(colorOptions: ColorOptions) {
        self.colorOptions = colorOptions
    }

    func log(event: ProjectEvent) { // swiftlint:disable:this cyclomatic_complexity
        let formatting = colorOptions.formatting

        switch event {
        case let .cloning(dependency):
            carthage.println(formatting.bullets + "Cloning " + formatting.projectName(dependency.name))

        case let .fetching(dependency):
            carthage.println(formatting.bullets + "Fetching " + formatting.projectName(dependency.name))

        case let .checkingOut(dependency, revision):
            carthage.println(formatting.bullets + "Checking out " + formatting.projectName(dependency.name) + " at " + formatting.quote(revision))

        case let .downloadingBinaryFrameworkDefinition(dependency, url):
            carthage.println(formatting.bullets + "Downloading binary-only dependency " + formatting.projectName(dependency.name)
                + " at " + formatting.quote(url.absoluteString))

        case let .downloadingBinaries(dependency, release):
            carthage.println(formatting.bullets + "Downloading " + formatting.projectName(dependency.name)
                + " binary at " + formatting.quote(release))

        case let .skippedDownloadingBinaries(dependency, message):
            carthage.println(formatting.bullets + "Skipped downloading " + formatting.projectName(dependency.name)
                + " binary due to the error:\n\t" + formatting.quote(message))

        case let .installingBinaries(dependency, release):
            carthage.println(formatting.bullets + "Installing " + formatting.projectName(dependency.name)
                + " binary at " + formatting.quote(release))

        case let .storingBinaries(dependency, release):
            carthage.println(formatting.bullets + "Storing " + formatting.projectName(dependency.name)
                + " binary at " + formatting.quote(release))

        case let .skippedInstallingBinaries(dependency, error):
            let output = """
            \(formatting.bullets)Skipped installing \(formatting.projectName(dependency.name)).framework binary:
            \(error.map { formatting.quote(String(describing: $0)) } ?? "No matching binary found")
            Falling back to building from the source
            """
            carthage.println(output)

        case let .skippedBuilding(dependency, message):
            carthage.println(formatting.bullets + "Skipped building " + formatting.projectName(dependency.name) + " due to the error:\n" + message)

        case let .skippedBuildingCached(dependency):
            carthage.println(formatting.bullets + "Valid cache found for " + formatting.projectName(dependency.name) + ", skipping build")

        case let .rebuildingCached(dependency):
            carthage.println(formatting.bullets + "Invalid cache found for " + formatting.projectName(dependency.name)
                + ", rebuilding with all downstream dependencies")

        case let .buildingUncached(dependency):
            carthage.println(formatting.bullets + "No cache found for " + formatting.projectName(dependency.name)
                + ", building with all downstream dependencies")

        case let .rebuildingBinary(dependency):
            carthage.println(formatting.bullets + "Invalid binary found for " + formatting.projectName(dependency.name)
                + ", rebuilding with all downstream dependencies")

        case let .waiting(url):
            carthage.println(formatting.bullets + "Waiting for lock on " + url.path)
        }
    }
}

final class ResolverEventLogger {
    let colorOptions: ColorOptions
    let isVerbose: Bool

    init(colorOptions: ColorOptions, verbose: Bool) {
        self.colorOptions = colorOptions
        self.isVerbose = verbose
    }

    func log(event: ResolverEvent) {
        switch event {
        case .foundVersions(let versions, let dependency, let versionSpecifier):
            if isVerbose {
                carthage.println("Versions for dependency '\(dependency)' compatible with versionSpecifier \(versionSpecifier): \(versions)")
            }
        case .foundTransitiveDependencies(let transitiveDependencies, let dependency, let version):
            if isVerbose {
                carthage.println("Dependencies for dependency '\(dependency)' with version \(version): \(transitiveDependencies)")
            }
        case .failedRetrievingTransitiveDependencies(let error, let dependency, let version):
            carthage.println("Caught error while retrieving dependencies for \(dependency) at version \(version): \(error)")
        case .failedRetrievingVersions(let error, let dependency, _):
            carthage.println("Caught error while retrieving versions for \(dependency): \(error)")
        case .rejected(let dependencySet, let error):
            if isVerbose {
                carthage.println("Rejected dependency set:\n\(dependencySet)\n\nReason: \(error)\n")
            }
        }
    }
}
