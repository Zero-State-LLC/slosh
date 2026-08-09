import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Whether an error means "the caller stopped caring", from any layer.
///
/// Swift concurrency and URLSession disagree about how to report this, and the
/// disagreement is silent. `Task.sleep` and `Task.checkCancellation()` throw
/// `CancellationError`, but `URLSession`'s async methods throw
/// `URLError(.cancelled)` instead. Matching only the former means every
/// cancellation on the live transport is misread as a network failure — which
/// then looks like partial station coverage rather than an abandoned request.
///
/// Keeping the judgement in one place is the point: the provider and the
/// coordinator have to agree, or a cancelled fetch is classified one way on the
/// way out and another way on the way in.
func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}
