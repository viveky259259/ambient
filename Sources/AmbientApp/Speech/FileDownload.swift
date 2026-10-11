import Foundation

/// Downloads one file to a path, reporting bytes written. Cancelling the calling task cancels the download.
final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var moveError: Error?

    private init(destination: URL, progress: @escaping (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func run(_ url: URL, to destination: URL, progress: @escaping (Int64) -> Void) async throws {
        let download = FileDownload(destination: destination, progress: progress)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                download.start(url, c)
            }
        } onCancel: {
            download.cancel()
        }
    }

    private func start(_ url: URL, _ c: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            c.resume(throwing: CancellationError())
            return
        }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        continuation = c
        task = session.downloadTask(with: url)
        lock.unlock()
        task?.resume()
        session.finishTasksAndInvalidate()
    }

    private func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "The server answered \(status)."])
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        if let error = error ?? moveError {
            c?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            c?.resume()
        }
    }
}
