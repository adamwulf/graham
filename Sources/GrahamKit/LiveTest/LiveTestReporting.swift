/// The service-independent result of one live-test step.
public enum LiveTestReportOutcome: Sendable, Equatable {
    case pass
    case fail(reason: String)
    case skip(reason: String)
}

/// A live-test step that the CLI can render without knowing its service.
public protocol LiveTestStepReporting: Sendable {
    var name: String { get }
    var reportOutcome: LiveTestReportOutcome { get }
    var createdIDs: [String] { get }
}

/// A live-test summary that the CLI can render without knowing its service.
public protocol LiveTestSummaryReporting: Sendable {
    var passed: Int { get }
    var failed: Int { get }
    var skipped: Int { get }
}

extension SlidesLiveTestStep: LiveTestStepReporting {
    public var reportOutcome: LiveTestReportOutcome {
        switch outcome {
        case .pass: return .pass
        case .fail(let reason): return .fail(reason: reason)
        case .skip(let reason): return .skip(reason: reason)
        }
    }
}

extension DocsLiveTestStep: LiveTestStepReporting {
    public var reportOutcome: LiveTestReportOutcome {
        switch outcome {
        case .pass: return .pass
        case .fail(let reason): return .fail(reason: reason)
        case .skip(let reason): return .skip(reason: reason)
        }
    }
}

extension SheetsLiveTestStep: LiveTestStepReporting {
    public var reportOutcome: LiveTestReportOutcome {
        switch outcome {
        case .pass: return .pass
        case .fail(let reason): return .fail(reason: reason)
        case .skip(let reason): return .skip(reason: reason)
        }
    }
}

extension DriveLiveTestStep: LiveTestStepReporting {
    public var reportOutcome: LiveTestReportOutcome {
        switch outcome {
        case .pass: return .pass
        case .fail(let reason): return .fail(reason: reason)
        case .skip(let reason): return .skip(reason: reason)
        }
    }
}

extension SlidesLiveTestSummary: LiveTestSummaryReporting {}
extension DocsLiveTestSummary: LiveTestSummaryReporting {}
extension SheetsLiveTestSummary: LiveTestSummaryReporting {}
extension DriveLiveTestSummary: LiveTestSummaryReporting {}
