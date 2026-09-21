import XCTest
import Foundation
import Darwin
@testable import HeadroomCore

final class CodexParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func parse(_ json: String) throws -> CodexSnapshot {
        try CodexRateLimitsParser.parse(result: Data(json.utf8), fetchedAt: now)
    }

    func testCoreBucketWinsAndMostConstrainedWindowIsSelected() throws {
        let snapshot = try parse(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"model":{"primary":{"usedPercent":100}},"codex":{"primary":{"usedPercent":21,"windowDurationMins":10080,"resetsAt":1800100000},"secondary":{"usedPercent":67,"windowDurationMins":300,"resetsAt":1800010000}}}}"#)
        XCTAssertEqual(snapshot.remainingPercent, 33)
        XCTAssertEqual(snapshot.windowLabel, "5-hour allowance")
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 79)
        XCTAssertEqual(snapshot.weekly?.resetsAt, Date(timeIntervalSince1970: 1_800_100_000))
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertEqual(snapshot.resetsAt, Date(timeIntervalSince1970: 1_800_010_000))
    }

    func testOneWeeklyWindowDoesNotInventSecondWindow() throws {
        let snapshot = try parse(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":21,"windowDurationMins":10080},"secondary":null}}}"#)
        XCTAssertEqual(snapshot.remainingPercent, 79)
        XCTAssertEqual(snapshot.windowLabel, "Weekly allowance")
        XCTAssertNil(snapshot.resetsAt)
        XCTAssertNil(snapshot.weekly)
    }

    func testMissingOrShortDurationDoesNotBecomeWeekly() throws {
        for duration in ["", ",\"windowDurationMins\":300"] {
            let json = "{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":10,\"resetsAt\":1800100000" + duration + "}}}"
            XCTAssertNil(try parse(json).weekly)
        }
    }

    func testIdentifiedLegacyIsAccepted() throws {
        XCTAssertEqual(try parse(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":0}}}"#).remainingPercent, 100)
    }

    func testUnknownBucketsAndUnidentifiedLegacyAreUnavailable() {
        for json in [#"{"rateLimitsByLimitId":{"model":{"primary":{"usedPercent":0}}}}"#,
                     #"{"rateLimits":{"primary":{"usedPercent":0}}}"#,
                     #"{"rateLimitsByLimitId":{"codex":{"primary":null,"secondary":null}}}"#] {
            XCTAssertThrowsError(try parse(json)) { XCTAssertEqual($0 as? CodexClientError, .missingCoreQuota) }
        }
    }

    func testMalformedAndBooleanValuesAreNotPercentages() {
        for json in ["null", "not json", #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":true}}}}"#,
                     #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":null}}}}"#,
                     #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":-1}}}}"#,
                     #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":2,"resetsAt":"tomorrow"}}}}"#,
                     #"{"rateLimitsByLimitId":{"codex":{"limitId":"other","primary":{"usedPercent":2}}}}"#] {
            XCTAssertThrowsError(try parse(json)) { XCTAssertEqual($0 as? CodexClientError, .invalidResponse) }
        }
    }

    func testExpiredConstraintDoesNotImplyRecovery() {
        XCTAssertThrowsError(try parse(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":100,"resetsAt":1799999999},"secondary":{"usedPercent":0,"resetsAt":1800010000}}}}"#)) {
            XCTAssertEqual($0 as? CodexClientError, .expiredWindow)
        }
    }

    func testBackendUsageBlockIsNotOverriddenByPercentage() {
        XCTAssertThrowsError(try parse(#"{"ordinaryUsageAllowed":false,"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":0}}}}"#)) {
            XCTAssertEqual($0 as? CodexClientError, .usageUnavailable)
        }
        XCTAssertThrowsError(try parse(#"{"rateLimitsByLimitId":{"codex":{"spendControlReached":true,"primary":{"usedPercent":0}}}}"#)) {
            XCTAssertEqual($0 as? CodexClientError, .usageUnavailable)
        }
    }

    func testOverageClampsToZero() throws {
        XCTAssertEqual(try parse(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":105}}}}"#).remainingPercent, 0)
    }
}

final class CodexProcessTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("headroom-codex-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func executable(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func testHandshakeAndSuccessfulRead() async throws {
        let script = try executable(#"""
        IFS= read -r init
        case "$init" in *'"initialize"'*) ;; *) exit 2 ;; esac
        printf '%s\n' '{"id":1,"result":{"userAgent":"test"}}'
        IFS= read -r initialized
        case "$initialized" in *'"initialized"'*) ;; *) exit 3 ;; esac
        IFS= read -r usage
        case "$usage" in *'rateLimits'*) ;; *) exit 4 ;; esac
        printf '%s\n' '{"method":"account/rateLimits/updated","params":{}}'
        printf '%s\n' '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":21,"windowDurationMins":10080}}}}}'
        """#)
        let snapshot = try await CodexClient(executableURL: script, timeout: 2).read()
        XCTAssertEqual(snapshot.remainingPercent, 79)
    }

    func testProtocolErrorIsSanitized() async throws {
        let script = try executable(#"""
        IFS= read -r init
        printf '%s\n' '{"id":1,"error":{"code":-1,"message":"SECRET raw provider response"}}'
        """#)
        do { _ = try await CodexClient(executableURL: script).read(); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? CodexClientError, .serverError); XCTAssertFalse(error.localizedDescription.contains("SECRET")) }
    }

    func testClosedInputDoesNotCrashHost() async throws {
        let script = try executable("exec 0<&-\nexit 0\n")
        for _ in 0..<10 {
            do { _ = try await CodexClient(executableURL: script, timeout: 1).read(); XCTFail("Expected failure") }
            catch { XCTAssertNotNil(error as? CodexClientError) }
        }
    }

    func testOutputBound() async throws {
        let script = try executable("exec /usr/bin/head -c 1100000 /dev/zero\n")
        do { _ = try await CodexClient(executableURL: script).read(); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? CodexClientError, .outputLimit) }
    }

    func testTimeoutTerminatesOwnedProcess() async throws {
        let script = try sleepingExecutable()
        do { _ = try await CodexClient(executableURL: script, timeout: 1).read(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? CodexClientError, .timedOut) }
        try await assertOwnedProcessStopped()
    }

    func testCancellationTerminatesOwnedProcess() async throws {
        let script = try sleepingExecutable()
        let task = Task { try await CodexClient(executableURL: script).read() }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await assertOwnedProcessStopped()
    }

    func testAlreadyCancelledTaskDoesNotLaunch() async throws {
        let script = try sleepingExecutable()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CodexClient(executableURL: script).read()
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pid").path))
    }

    private func sleepingExecutable() throws -> URL {
        // Test directory is generated locally with a UUID, without shell characters.
        try executable("printf '%s' \"$$\" > '\(directory.appendingPathComponent("pid").path)'\nexec /bin/sleep 60\n")
    }

    private func assertOwnedProcessStopped() async throws {
        let text = try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
        let pid = try XCTUnwrap(Int32(text))
        XCTAssertEqual(kill(pid, 0), -1, "Owned helper should no longer exist")
        XCTAssertEqual(errno, ESRCH)
    }
}
