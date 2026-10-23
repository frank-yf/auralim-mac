import AppKit
import Foundation
import Sparkle
import Testing
@testable import Auralim

@MainActor
struct UpdateControllerTests {
    @Test func downloadAndPreparationNeverInvokeRestartUntilClicked() {
        let controller = UpdateController()
        var installs = 0
        #expect(controller.canCheck)
        controller.showDownloadInitiated(cancellation: {})
        #expect(controller.state == .downloading && !controller.canCheck)
        controller.restartToUpdate()
        controller.showDownloadDidStartExtractingUpdate()
        #expect(controller.state == .preparing)
        controller.showReady(toInstallAndRelaunch: { choice in
            #expect(choice == .install)
            installs += 1
        })
        #expect(controller.state == .ready(""))
        #expect(installs == 0 && !controller.canCheck)
        controller.restartToUpdate()
        #expect(installs == 1 && controller.state == .installing)
        controller.restartToUpdate()
        #expect(installs == 1)
    }

    @Test func validationFailureInvalidatesPreparedInstallAction() {
        let controller = UpdateController()
        var installs = 0, acknowledgements = 0
        controller.showReady(toInstallAndRelaunch: { _ in installs += 1 })
        controller.showUpdaterError(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue))) {
            acknowledgements += 1
        }
        controller.dismissUpdateInstallation()
        #expect(controller.state == .failed(.validation))
        #expect(controller.canCheck && acknowledgements == 1)
        controller.restartToUpdate()
        #expect(installs == 0)
    }

    @Test func wrappedFeedSignatureFailureIsReportedAsValidationFailure() {
        let controller = UpdateController()
        let underlying = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.validationError.rawValue))
        let wrapper = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.appcastError.rawValue),
            userInfo: [NSUnderlyingErrorKey: underlying])
        controller.showUpdaterError(wrapper, acknowledgement: {})
        #expect(controller.state == .failed(.validation))
    }

    @Test func missingUpdateAndNetworkFailureRemainVisibleAfterSessionDismissal() {
        let controller = UpdateController()
        var acknowledgements = 0
        controller.showUserInitiatedUpdateCheck(cancellation: {})
        #expect(controller.state == .checking && !controller.canCheck)
        controller.showUpdateNotFoundWithError(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))) {
            acknowledgements += 1
        }
        controller.dismissUpdateInstallation()
        #expect(controller.state == .upToDate && controller.canCheck)
        controller.showUpdaterError(URLError(.notConnectedToInternet)) { acknowledgements += 1 }
        controller.dismissUpdateInstallation()
        #expect(controller.state == .failed(.network) && acknowledgements == 2)
    }

    @Test func canceledTerminationCanOnlyBeRetriedByAnotherClick() {
        let controller = UpdateController()
        var terminations = 0
        controller.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: { terminations += 1 })
        #expect(terminations == 0)
        controller.restartToUpdate()
        #expect(terminations == 1)
        controller.restartToUpdate()
        #expect(terminations == 1)
    }

    @Test func authorizationFallbackWaitsForClickThenContinuesWithoutSecondPrompt() {
        let controller = UpdateController()
        var choices: [SPUUserUpdateChoice] = []
        controller.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices.isEmpty)
        controller.restartToUpdate()
        controller.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices == [.install, .install])
    }

    @Test func browserFallbackUsesOnlyTheFixedLatestReleaseURL() {
        var opened: [URL] = []
        let controller = UpdateController(openURL: { opened.append($0); return true })
        controller.showUpdaterError(URLError(.timedOut), acknowledgement: {})
        controller.openReleases()
        #expect(opened == [URL(string: "https://github.com/frank-yf/auralim-mac/releases/latest")!])
    }

    @Test func distributionConfigUsesSignedGitHubFeedAndDailyAutomaticDownloads() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["SUFeedURL"] as? String == UpdateController.feedURL.absoluteString)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86400)
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(info["CFBundleShortVersionString"] as? String == "0.3.3")
    }
}
