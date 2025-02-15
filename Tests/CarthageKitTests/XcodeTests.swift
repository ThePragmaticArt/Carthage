@testable import CarthageKit
import Foundation
import Result
import Nimble
import XCTest
import ReactiveSwift
import ReactiveTask
import Tentacle
import XCDBLD

class XcodeTests: XCTestCase {
	
	// The fixture is maintained at https://github.com/ikesyo/carthage-fixtures-ReactiveCocoaLayout
	var directoryURL: URL!
	var projectURL: URL!
	var buildFolderURL: URL!
	var targetFolderURL: URL!
    var currentSwiftVersion: PinnedVersion!
	
	override func setUp() {
		
		guard let nonNilURL = Bundle(for: type(of: self)).url(forResource: "carthage-fixtures-ReactiveCocoaLayout-master", withExtension: nil) else {
			fail("Expected carthage-fixtures-ReactiveCocoaLayout-master to be loadable from resources")
			return
		}

        guard let swiftVersion = SwiftToolchain.swiftVersion().single()?.value else {
            fail("Expected swift version to not be nil")
            return
        }
        currentSwiftVersion = swiftVersion
		directoryURL = nonNilURL
		projectURL = directoryURL.appendingPathComponent("ReactiveCocoaLayout.xcodeproj")
		buildFolderURL = directoryURL.appendingPathComponent(Constants.binariesFolderPath)
		targetFolderURL = URL(
			fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString),
			isDirectory: true
		)
		_ = try? FileManager.default.removeItem(at: buildFolderURL)
		expect { try FileManager.default.createDirectory(atPath: self.targetFolderURL.path, withIntermediateDirectories: true) }.notTo(throwError())
	}
	
	override func tearDown() {
		_ = try? FileManager.default.removeItem(at: targetFolderURL)
	}

	#if !SWIFT_PACKAGE
	let testSwiftFramework = "Quick.framework"
	let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
	let testSwiftFrameworkURL = currentDirectory.appendingPathComponent(testSwiftFramework)
	#endif
	
	#if !SWIFT_PACKAGE
	func testShouldDetermineThatASwiftFrameworkIsASwiftFramework() {
		expect(isSwiftFramework(testSwiftFrameworkURL)) == true
	}
	#endif
	
	func testShouldDetermineThatAnObjcFrameworkIsNotASwiftFramework() {
		guard let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldObjc.framework", withExtension: nil) else {
			fail("Could not load FakeOldObjc.framework from resources")
			return
		}
		expect(Frameworks.isSwiftFramework(frameworkURL)) == false
	}
	
	#if !SWIFT_PACKAGE
	func testShouldDetermineAFrameworksSwiftVersion() {
		let result = frameworkSwiftVersion(testSwiftFrameworkURL).single()
		
		expect(FileManager.default.fileExists(atPath: testSwiftFrameworkURL.path)) == true
		expect(result?.value) == currentSwiftVersion
	}
	
	func testShouldDetermineADsymsSwiftVersion() {
		
		let dSYMURL = testSwiftFrameworkURL.appendingPathExtension("dSYM")
		expect(FileManager.default.fileExists(atPath: dSYMURL.path)) == true
		
		let result = dSYMSwiftVersion(dSYMURL).single()
		expect(result?.value) == currentSwiftVersion
	}
	#endif
	
	func testShouldDetermineAFrameworksSwiftVersionExcludingAnEffectiveVersion() {
		guard let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeSwift.framework", withExtension: nil) else {
			fail("Could not load FakeSwift.framework from resources")
			return
		}
		let result = Frameworks.frameworkSwiftVersion(frameworkURL).single()
		
		expect(result?.value) == PinnedVersion("4.0")
	}
	
	#if !SWIFT_PACKAGE
	func testShouldDetermineWhenASwiftFrameworkIsCompatible() {
		let result = checkSwiftFrameworkCompatibility(testSwiftFrameworkURL, usingToolchain: nil).single()
		
		expect(result?.value) == testSwiftFrameworkURL
	}
	#endif
	
	func testShouldDetermineWhenASwiftFrameworkIsIncompatible() {
		guard let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOldSwift.framework", withExtension: nil) else {
			fail("Could not load FakeOldSwift.framework from resources")
			return
		}
		let result = Frameworks.checkSwiftFrameworkCompatibility(frameworkURL, usingToolchain: nil).single()
		
		expect(result?.value).to(beNil())
		expect(result?.error) == .incompatibleFrameworkSwiftVersions(local: currentSwiftVersion, framework: PinnedVersion("0.0.0"))
	}
	
	func testShouldDetermineAFrameworksSwiftVersionForOssToolchainsFromSwiftOrg() {
		guard let frameworkURL = Bundle(for: type(of: self)).url(forResource: "FakeOSSSwift.framework", withExtension: nil) else {
			fail("Could not load FakeOSSSwift.framework from resources")
			return
		}
		let result = Frameworks.frameworkSwiftVersion(frameworkURL).single()
		
		expect(result?.value) == PinnedVersion("4.1-dev")
	}
	
	func relativePathsForProjectsInDirectory(_ directoryURL: URL) -> [String] {
		let result = ProjectLocator
			.locate(in: directoryURL)
			.map { String($0.fileURL.absoluteString[directoryURL.absoluteString.endIndex...]) }
			.collect()
			.first()
		expect(result?.error).to(beNil())
		return result?.value ?? []
	}
	
	func testShouldNotFindAnythingInTheCarthageSubdirectory() {
		let relativePaths = relativePathsForProjectsInDirectory(directoryURL)
		expect(relativePaths).toNot(beEmpty())
		let pathsStartingWithCarthage = relativePaths.filter { $0.hasPrefix("\(carthageProjectCheckoutsPath)/") }
		expect(pathsStartingWithCarthage).to(beEmpty())
	}
	
	func testShouldNotFindAnythingThatsListedAsAGitSubmodule() {
		let multipleSubprojects = "SampleGitSubmodule"
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: multipleSubprojects, withExtension: nil) else {
			fail("Could not load SampleGitSubmodule from resources")
			return
		}
		
		let relativePaths = relativePathsForProjectsInDirectory(_directoryURL)
		expect(relativePaths) == [ "SampleGitSubmodule.xcodeproj/" ]
	}
	
	
	func testShouldBuildForAllPlatforms() {
		let dependencies = [
			Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes")),
			Dependency.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")),
			]
		let version = PinnedVersion("0.1")
		
		for dependency in dependencies {
            let result = Xcode.build(dependency: dependency, version: version, rootDirectoryURL: directoryURL, withOptions: BuildOptions(configuration: "Debug"))
				.ignoreTaskData()
				.on(value: { project, scheme in // swiftlint:disable:this end_closure
					NSLog("Building scheme \"\(scheme)\" in \(project)")
				})
				.wait()
			
			expect(result.error).to(beNil())
		}
		
		let result = Xcode.buildInDirectory(directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this closure_params_parantheses
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		
		expect(result.error).to(beNil())
		
		// Verify that the build products exist at the top level.
		var dependencyNames = dependencies.map { dependency in dependency.name }
		dependencyNames.append("ReactiveCocoaLayout")
		
		for dependency in dependencyNames {
			let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
			let macdSYMPath = (macPath as NSString).appendingPathExtension("dSYM")!
			let iOSPath = buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path
			let iOSdSYMPath = (iOSPath as NSString).appendingPathExtension("dSYM")!
			
			for path in [ macPath, macdSYMPath, iOSPath, iOSdSYMPath ] {
				expect(path).to(beExistingDirectory())
			}
		}
		let frameworkFolderURL = buildFolderURL.appendingPathComponent("iOS/ReactiveCocoaLayout.framework")
		
		// Verify that the iOS framework is a universal binary for device
		// and simulator.
		let architectures = Frameworks.architecturesInPackage(frameworkFolderURL)
			.collect()
			.single()
		
		expect(architectures?.value).to(contain("i386", "armv7", "arm64"))
		
		// Verify that our dummy framework in the RCL iOS scheme built as
		// well.
		let auxiliaryFrameworkPath = buildFolderURL.appendingPathComponent("iOS/AuxiliaryFramework.framework").path
		expect(auxiliaryFrameworkPath).to(beExistingDirectory())
		
		// Copy ReactiveCocoaLayout.framework to the temporary folder.
		let targetURL = targetFolderURL.appendingPathComponent("ReactiveCocoaLayout.framework", isDirectory: true)
		
        let resultURL = Files.copyFile(from: frameworkFolderURL, to: targetURL).single()
		expect(resultURL?.value) == targetURL
		expect(targetURL.path).to(beExistingDirectory())
		
		let strippingResult = Xcode.stripFramework(targetURL, keepingArchitectures: [ "armv7", "arm64" ], strippingDebugSymbols: true, codesigningIdentity: "-").wait()
		expect(strippingResult.value).notTo(beNil())
		
		let strippedArchitectures = Frameworks.architecturesInPackage(targetURL)
			.collect()
			.single()
		
		expect(strippedArchitectures?.value).notTo(contain("i386"))
		expect(strippedArchitectures?.value).to(contain("armv7", "arm64"))
		
		/// Check whether the resulting framework contains debug symbols
		/// There are many suggestions on how to do this but no one single
		/// accepted way. This seems to work best:
		/// https://lists.apple.com/archives/unix-porting/2006/Feb/msg00021.html
		let hasDebugSymbols = SignalProducer<URL, CarthageError> { () -> Result<URL, CarthageError> in Frameworks.binaryURL(targetURL) }
			.flatMap(.merge) { binaryURL -> SignalProducer<Bool, CarthageError> in
				let nmTask = Task("/usr/bin/xcrun", arguments: [ "nm", "-ap", binaryURL.path])
				return nmTask.launch()
					.ignoreTaskData()
					.mapError(CarthageError.taskError)
					.map { String(data: $0, encoding: .utf8) ?? "" }
					.flatMap(.merge) { output -> SignalProducer<Bool, NoError> in
						return SignalProducer(value: output.contains("SO "))
				}
			}.single()
		
		expect(hasDebugSymbols?.value).to(equal(false))
		
		let modulesDirectoryURL = targetURL.appendingPathComponent("Modules", isDirectory: true)
		expect(FileManager.default.fileExists(atPath: modulesDirectoryURL.path)) == false
		
		var output: String = ""
		let codeSign = Task("/usr/bin/xcrun", arguments: [ "codesign", "--verify", "--verbose", targetURL.path ])
		
		let codesignResult = codeSign.launch()
			.on(value: { taskEvent in
				switch taskEvent {
				case let .standardError(data):
					output += String(data: data, encoding: .utf8)!
					
				default:
					break
				}
			})
			.wait()
		
		expect(codesignResult.value).notTo(beNil())
		expect(output).to(contain("satisfies its Designated Requirement"))
	}

	func testShouldBuildAllSubprojectsForAllPlatformsByDefault() {
		let multipleSubprojects = "SampleMultipleSubprojects"
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: multipleSubprojects, withExtension: nil) else {
			fail("Could not load SampleMultipleSubprojects from resources")
			return
		}
		
		let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		
		expect(result.error).to(beNil())
		
		let expectedPlatformsFrameworks = [
			("iOS", "SampleiOSFramework"),
			("Mac", "SampleMacFramework"),
			("tvOS", "SampleTVFramework"),
			("watchOS", "SampleWatchFramework"),
			]
		
		for (platform, framework) in expectedPlatformsFrameworks {
			let path = buildFolderURL.appendingPathComponent("\(platform)/\(framework).framework").path
			expect(path).to(beExistingDirectory())
		}
	}
	
	func testShouldSkipProjectsWithoutSharedFrameworkSchems() {
		let dependency = "SchemeDiscoverySampleForCarthage"
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: "\(dependency)-0.2", withExtension: nil) else {
			fail("Could not load SchemeDiscoverySampleForCarthage from resources")
			return
		}

        var builtSchemes = [String]()
		let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
                builtSchemes.append(scheme.name)
			})
			.wait()
		
		expect(result.error).to(beNil())

        XCTAssertEqual(Set(builtSchemes), Set(arrayLiteral: "SchemeDiscoverySampleForCarthage-iOS", "SchemeDiscoverySampleForCarthage-Mac"))
		
		let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
		let iOSPath = buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path
		
		for path in [ macPath, iOSPath ] {
			expect(path).to(beExistingDirectory())
		}
	}

    func testShouldFilterWithSchemeCartfile() {
        let dependency = "SchemeDiscoverySampleForCarthage"
        guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: "SchemeDiscoverySampleWithFilteringForCarthage-0.2", withExtension: nil) else {
            fail("Could not load SchemeDiscoverySampleForCarthage from resources")
            return
        }

        var builtSchemes = [String]()
        let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug"), rootDirectoryURL: directoryURL)
            .ignoreTaskData()
            .on(value: { project, scheme in // swiftlint:disable:this end_closure
                NSLog("Building scheme \"\(scheme)\" in \(project)")
                builtSchemes.append(scheme.name)
            })
            .wait()

        expect(result.error).to(beNil())

        XCTAssertEqual(Set(builtSchemes), Set(arrayLiteral: "SchemeDiscoverySampleForCarthage-iOS"))

        let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency).framework").path
        let iOSPath = buildFolderURL.appendingPathComponent("iOS/\(dependency).framework").path

        expect(iOSPath).to(beExistingDirectory())
        expect(macPath).toNot(beExistingDirectory())
    }
	
	func testShouldNotCopyBuildProductsFromNestedDependenciesProducedByWorkspace() {
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: "WorkspaceWithDependency", withExtension: nil) else {
			fail("Could not load WorkspaceWithDependency from resources")
			return
		}
		
		let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [.macOS]), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		expect(result.error).to(beNil())
		
		let framework1Path = buildFolderURL.appendingPathComponent("Mac/TestFramework1.framework").path
		let framework2Path = buildFolderURL.appendingPathComponent("Mac/TestFramework2.framework").path
		
		expect(framework1Path).to(beExistingDirectory())
		expect(framework2Path).notTo(beExistingDirectory())
	}
	
	func testShouldErrorOutWithNosharedframeworkschemesIfThereIsNoSharedFrameworkSchemes() {
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: "Swell-0.5.0", withExtension: nil) else {
			fail("Could not load Swell-0.5.0 from resources")
			return
		}
		
		let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [.macOS]), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		
		expect(result.error).notTo(beNil())
		
		let isExpectedError: Bool
		if case .noSharedFrameworkSchemes? = result.error {
			isExpectedError = true
		} else {
			isExpectedError = false
		}
		
		expect(isExpectedError) == true
		expect(result.error?.description) == "Dependency \"Swell-0.5.0\" has no shared framework schemes for any of the platforms: Mac"
	}
	
	func testShouldBuildForOnePlatform() {
		let dependency = Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes"))
		let version = PinnedVersion("0.1")
		let result = Xcode.build(dependency: dependency, version: version, rootDirectoryURL: directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS ]))
			.ignoreTaskData()
			.on(value: { project, scheme in
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		
		expect(result.error).to(beNil())
		
		// Verify that the build product exists at the top level.
		let path = buildFolderURL.appendingPathComponent("Mac/\(dependency.name).framework").path
		expect(path).to(beExistingDirectory())
		
		// Verify that the version file exists.
		let versionFileURL = URL(fileURLWithPath: buildFolderURL.appendingPathComponent(".Archimedes.version").path)
		let versionFile = VersionFile(url: versionFileURL)
		expect(versionFile).notTo(beNil())
		
		// Verify that the other platform wasn't built.
		let incorrectPath = buildFolderURL.appendingPathComponent("iOS/\(dependency.name).framework").path
		expect(FileManager.default.fileExists(atPath: incorrectPath, isDirectory: nil)) == false
	}
	
	func testShouldBuildForMultiplePlatforms() {
		let dependency = Dependency.gitHub(.dotCom, Repository(owner: "github", name: "Archimedes"))
		let version = PinnedVersion("0.1")
		let result = Xcode.build(dependency: dependency, version: version, rootDirectoryURL: directoryURL, withOptions: BuildOptions(configuration: "Debug", platforms: [ .macOS, .iOS ]))
			.ignoreTaskData()
			.on(value: { project, scheme in
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		
		expect(result.error).to(beNil())
		
		// Verify that the build products of all specified platforms exist
		// at the top level.
		let macPath = buildFolderURL.appendingPathComponent("Mac/\(dependency.name).framework").path
		let iosPath = buildFolderURL.appendingPathComponent("iOS/\(dependency.name).framework").path
		
		for path in [ macPath, iosPath ] {
			expect(path).to(beExistingDirectory())
		}
	}
	
	func testShouldLocateTheProject() {
		let result = ProjectLocator.locate(in: directoryURL).first()
		expect(result).notTo(beNil())
		expect(result?.error).to(beNil())
		expect(result?.value) == .projectFile(projectURL)
	}
	
	func testShouldLocateTheProjectFromTheParentDirectory() {
		let result = ProjectLocator.locate(in: directoryURL.deletingLastPathComponent()).collect().first()
		expect(result).notTo(beNil())
		expect(result?.error).to(beNil())
		expect(result?.value).to(contain(.projectFile(projectURL)))
	}
	
	func testShouldNotLocateTheProjectFromADirectoryNotContainingIt() {
		let result = ProjectLocator.locate(in: directoryURL.appendingPathComponent("ReactiveCocoaLayout")).first()
		expect(result).to(beNil())
	}
	
	func testShouldBuildStaticLibraryAndPlaceResultToSubdirectory() {
		guard let _directoryURL = Bundle(for: type(of: self)).url(forResource: "DynamicAndStatic", withExtension: nil) else {
			fail("Could not load DynamicAndStatic from resources")
			return
		}
		let _buildFolderURL = _directoryURL.appendingPathComponent(Constants.binariesFolderPath)
		
		_ = try? FileManager.default.removeItem(at: _buildFolderURL)
		
		let result = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug",
																			   platforms: [.iOS],
																			   derivedDataPath: Constants.Dependency.derivedDataURL.appendingPathComponent("TestFramework-o2nfjkdsajhwenrjle").path), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		expect(result.error).to(beNil())
		
		let frameworkDynamicURL = buildFolderURL.appendingPathComponent("iOS/TestFramework.framework")
		let frameworkStaticURL = buildFolderURL.appendingPathComponent("iOS/Static/TestFramework.framework")
		
		let frameworkDynamicPackagePath = frameworkDynamicURL.appendingPathComponent("TestFramework").path
		let frameworkStaticPackagePath = frameworkStaticURL.appendingPathComponent("TestFramework").path
		
		expect(frameworkDynamicURL.path).to(beExistingDirectory())
		expect(frameworkStaticURL.path).to(beExistingDirectory())
		expect(frameworkDynamicPackagePath).to(beFramework(ofType: .dynamic))
		expect(frameworkStaticPackagePath).to(beFramework(ofType: .static))
		
		let result2 = Xcode.buildInDirectory(_directoryURL, withOptions: BuildOptions(configuration: "Debug",
																				platforms: [.iOS],
																				derivedDataPath: Constants.Dependency.derivedDataURL.appendingPathComponent("TestFramework-o2nfjkdsajhwenrjle").path), rootDirectoryURL: directoryURL)
			.ignoreTaskData()
			.on(value: { project, scheme in // swiftlint:disable:this end_closure
				NSLog("Building scheme \"\(scheme)\" in \(project)")
			})
			.wait()
		expect(result2.error).to(beNil())
		expect(frameworkDynamicPackagePath).to(stillBeFramework(ofType: .dynamic))
		expect(frameworkStaticPackagePath).to(stillBeFramework(ofType: .static))
	}
}

// MARK: Matcher

internal func stillBeFramework(ofType: FrameworkType) -> Predicate<String> {
	return beFramework(ofType: ofType)
}

internal func beFramework(ofType: FrameworkType) -> Predicate<String> {
	return Predicate { actualExpression in
		var message = "exist and be a \(ofType == .static ? "static" : "dynamic") type"
		let actualPath = try actualExpression.evaluate()
		
		guard let path = actualPath else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}
		
		var stringOutput: String?
		
		let result = Task("/usr/bin/xcrun", arguments: ["file", path])
			.launch()
			.ignoreTaskData()
			.on(value: { data in
				stringOutput = String(data: data, encoding: .utf8)
			})
			.wait()
		
		expect(result.error).to(beNil())
		
		let resultBool: Bool
		
		if let nonNilOutput = stringOutput {
			if ofType == .static {
				resultBool = nonNilOutput.contains("current ar archive") && !nonNilOutput.contains("dynamically linked shared library")
			} else {
				resultBool = !nonNilOutput.contains("current ar archive") && nonNilOutput.contains("dynamically linked shared library")
			}
		} else {
			resultBool = false
		}
		
		if !resultBool {
			message += ", got \(stringOutput ?? "nil")"
		}
		
		return PredicateResult(
			bool: resultBool,
			message: .expectedActualValueTo(message)
		)
	}
}

internal func beExistingDirectory() -> Predicate<String> {
	return Predicate { actualExpression in
		var message = "exist and be a directory"
		let actualPath = try actualExpression.evaluate()
		
		guard let path = actualPath else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}
		
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
		
		if !exists {
			message += ", but does not exist"
		} else if !isDirectory.boolValue {
			message += ", but is not a directory"
		}
		
		return PredicateResult(
			bool: exists && isDirectory.boolValue,
			message: .expectedActualValueTo(message)
		)
	}
}

internal func beRelativeSymlinkToDirectory(_ directory: URL) -> Predicate<URL> {
	return Predicate { actualExpression in
		let message = "be a relative symlink to \(directory)"
		let actualURL = try actualExpression.evaluate()
		
		guard var url = actualURL else {
			return PredicateResult(status: .fail, message: .expectedActualValueTo(message))
		}
		
		var isSymlink: Bool = false
		do {
			url.removeCachedResourceValue(forKey: .isSymbolicLinkKey)
			isSymlink = try url.resourceValues(forKeys: [ .isSymbolicLinkKey ]).isSymbolicLink ?? false
		} catch {}
		
		guard isSymlink else {
			return PredicateResult(
				status: .fail,
				message: .expectedActualValueTo(message + ", but is not a symlink")
			)
		}
		
		guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
			return PredicateResult(
				status: .fail,
				message: .expectedActualValueTo(message + ", but could not load destination")
			)
		}
		
		guard !(destination as NSString).isAbsolutePath else {
			return PredicateResult(
				status: .fail,
				message: .expectedActualValueTo(message + ", but is not a relative symlink")
			)
		}
		
		let standardDestination = url.resolvingSymlinksInPath().standardizedFileURL
		let desiredDestination = directory.standardizedFileURL
		
		let urlsEqual = standardDestination == desiredDestination
		let expectationMessage: ExpectationMessage = urlsEqual
			? .expectedActualValueTo(message)
			: .expectedActualValueTo(message + ", but does not point to the correct destination. Instead it points to \(standardDestination)")
		return PredicateResult(bool: urlsEqual, message: expectationMessage)
	}
}
