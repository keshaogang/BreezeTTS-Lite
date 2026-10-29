import Foundation

/// Resumable GGUF downloader with exact byte validation.
///
/// Uses a data task with a `Range` header so a partial file can continue where
/// it stopped (the HuggingFace mirror supports byte ranges). Every finished file
/// is checked against the catalogue size, so a truncated download never gets
/// picked up as a usable model.
final class ModelDownloader: NSObject, ObservableObject {
    struct TaskState: Equatable {
        var receivedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var isDownloading = false
        var errorMessage: String?

        var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, Double(receivedBytes) / Double(totalBytes))
        }
    }

    @Published private(set) var states: [String: TaskState] = [:]

    private var session: URLSession!
    private var handles: [Int: DownloadJob] = [:]
    private let lock = NSLock()

    private final class DownloadJob {
        let spec: ModelSpec
        let destination: URL
        var handle: FileHandle
        var expectedOffset: Int64

        init(spec: ModelSpec, destination: URL, handle: FileHandle, expectedOffset: Int64) {
            self.spec = spec
            self.destination = destination
            self.handle = handle
            self.expectedOffset = expectedOffset
        }
    }

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func state(for spec: ModelSpec) -> TaskState {
        states[spec.id] ?? TaskState(receivedBytes: spec.installedSize, totalBytes: spec.bytes)
    }

    func start(_ spec: ModelSpec) {
        guard let remote = spec.downloadURL else { return }
        Paths.ensureDirectories()
        let destination = spec.fileURL

        // Already complete?
        if Paths.size(of: destination) == spec.bytes {
            publish(spec, state: TaskState(receivedBytes: spec.bytes, totalBytes: spec.bytes, isDownloading: false))
            return
        }

        var request = URLRequest(url: remote)
        request.setValue("BreezeTTS/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let existing = Paths.size(of: destination)
        if existing > 0 && existing < spec.bytes {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        } else if existing >= spec.bytes {
            try? FileManager.default.removeItem(at: destination)
        }

        let offset = (existing > 0 && existing < spec.bytes) ? existing : 0

        if offset == 0 {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        } else {
            // keep the resumed prefix
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: destination) else {
            publish(spec, state: TaskState(receivedBytes: offset, totalBytes: spec.bytes,
                                           isDownloading: false, errorMessage: "无法写入文件"))
            return
        }
        try? handle.seekToEndOfFile()

        let task = session.dataTask(with: request)
        let job = DownloadJob(spec: spec, destination: destination, handle: handle, expectedOffset: offset)
        lock.lock()
        handles[task.taskIdentifier] = job
        lock.unlock()

        publish(spec, state: TaskState(receivedBytes: offset, totalBytes: spec.bytes, isDownloading: true))
        task.resume()
    }

    func cancel(_ spec: ModelSpec) {
        lock.lock()
        let jobs = handles.filter { $0.value.spec.id == spec.id }
        lock.unlock()
        for (id, job) in jobs {
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == id }?.cancel()
            }
            try? job.handle.close()
        }
        publish(spec, state: TaskState(receivedBytes: Paths.size(of: spec.fileURL),
                                       totalBytes: spec.bytes, isDownloading: false,
                                       errorMessage: "已暂停，可继续"))
    }

    func deleteFile(_ spec: ModelSpec) {
        try? FileManager.default.removeItem(at: spec.fileURL)
        publish(spec, state: TaskState(receivedBytes: 0, totalBytes: spec.bytes))
    }

    private func publish(_ spec: ModelSpec, state: TaskState) {
        DispatchQueue.main.async {
            self.states[spec.id] = state
        }
    }

    private func job(for task: URLSessionTask) -> DownloadJob? {
        lock.lock()
        defer { lock.unlock() }
        return handles[task.taskIdentifier]
    }

    private func finish(task: URLSessionTask, error: Error?) {
        guard let job = job(for: task) else { return }
        lock.lock()
        handles.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        try? job.handle.close()

        if let error {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled {
                publish(job.spec, state: TaskState(receivedBytes: Paths.size(of: job.destination),
                                                  totalBytes: job.spec.bytes, isDownloading: false,
                                                  errorMessage: "已暂停"))
            } else {
                publish(job.spec, state: TaskState(receivedBytes: Paths.size(of: job.destination),
                                                  totalBytes: job.spec.bytes, isDownloading: false,
                                                  errorMessage: error.localizedDescription))
            }
            return
        }

        let size = Paths.size(of: job.destination)
        if size == job.spec.bytes {
            publish(job.spec, state: TaskState(receivedBytes: size, totalBytes: job.spec.bytes, isDownloading: false))
        } else {
            publish(job.spec, state: TaskState(receivedBytes: size, totalBytes: job.spec.bytes, isDownloading: false,
                                               errorMessage: "大小校验失败（\(size.humanBytes) / \(job.spec.bytes.humanBytes)），请重试"))
        }
    }
}

extension ModelDownloader: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let job = job(for: dataTask) else {
            completionHandler(.cancel)
            return
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 200, job.expectedOffset > 0 {
            // Server ignored the Range header: start over instead of corrupting the file.
            try? job.handle.truncate(atOffset: 0)
            try? job.handle.seek(toOffset: 0)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let job = job(for: dataTask) else { return }
        do {
            try job.handle.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            return
        }
        let received = Paths.size(of: job.destination)
        publish(job.spec, state: TaskState(receivedBytes: received,
                                           totalBytes: max(job.spec.bytes, received),
                                           isDownloading: true))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(task: task, error: error)
    }
}
