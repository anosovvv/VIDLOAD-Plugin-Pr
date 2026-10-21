import Foundation
import Network

private let host = "127.0.0.1"
private let port: UInt16 = 17_383

enum OutputFormat: String, Decodable {
    case mp4
    case mp3

    var ytDlpArguments: [String] {
        switch self {
        case .mp4:
            return [
                "-f", "bv*[vcodec^=avc1][ext=mp4]+ba[acodec^=mp4a]/b[vcodec^=avc1][ext=mp4]/bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]",
                "--merge-output-format", "mp4"
            ]
        case .mp3:
            return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
    }
}

enum JobStatus: String, Codable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

enum JobStage: String, Codable {
    case preparing
    case downloading
    case converting
}

struct DownloadRequest: Decodable {
    let url: String
    let format: OutputFormat
    let consumer: String?
}

struct DownloadSnapshot: Codable {
    let id: String
    let status: JobStatus
    let stage: JobStage
    let progress: Double
    let detail: String
    let error: String?
    let outputPath: String?
}

final class DownloadJob {
    let id: String
    let sourceURL: URL
    let format: OutputFormat
    var status: JobStatus = .queued
    var stage: JobStage = .preparing
    var progress: Double = 0
    var detail = "Checking available formats"
    var error: String?
    var outputPath: String?
    var process: Process?
    var pendingOutput = ""
    var conversionDuration: TimeInterval?
    var conversionSeconds: TimeInterval = 0
    var cancelled = false

    init(sourceURL: URL, format: OutputFormat) {
        self.id = UUID().uuidString
        self.sourceURL = sourceURL
        self.format = format
    }

    func snapshot() -> DownloadSnapshot {
        DownloadSnapshot(
            id: id,
            status: status,
            stage: stage,
            progress: progress,
            detail: detail,
            error: error,
            outputPath: outputPath
        )
    }
}

final class JobStore {
    private let queue = DispatchQueue(label: "com.anosovvv.vidload-plugin-pr.jobs")
    private var jobs: [String: DownloadJob] = [:]

    func add(_ job: DownloadJob) {
        queue.sync { jobs[job.id] = job }
    }

    func withJob<T>(_ id: String, _ body: (DownloadJob) -> T) -> T? {
        queue.sync { jobs[id].map(body) }
    }

    func snapshot(for id: String) -> DownloadSnapshot? {
        queue.sync { jobs[id]?.snapshot() }
    }
}

struct ToolPaths {
    let ytDlp: URL
    let ffmpeg: URL

    static func locate() throws -> ToolPaths {
        let fileManager = FileManager.default
        let explicitYtDlp = ProcessInfo.processInfo.environment["VIDLOAD_YTDLP_PATH"].map(URL.init(fileURLWithPath:))
        let explicitFFmpeg = ProcessInfo.processInfo.environment["VIDLOAD_FFMPEG_PATH"].map(URL.init(fileURLWithPath:))

        if let explicitYtDlp, let explicitFFmpeg,
           fileManager.isExecutableFile(atPath: explicitYtDlp.path),
           fileManager.isExecutableFile(atPath: explicitFFmpeg.path) {
            return ToolPaths(ytDlp: explicitYtDlp, ffmpeg: explicitFFmpeg)
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let bundledTools = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/VIDLOADTools.bundle")

        let bundledRoots = [
            bundledTools.path,
            "/Applications/VIDLOAD.app/Contents/Resources/VIDLOADTools.bundle",
            "/Applications/VIDLOAD Plugin Pr Engine.app/Contents/Resources/VIDLOADTools.bundle"
        ]

        for root in bundledRoots {
            let ytDlp = URL(fileURLWithPath: root).appendingPathComponent("bin/yt-dlp")
            let architecture = ProcessInfo.processInfo.isiOSAppOnMac ? "arm64" : currentArchitecture
            let ffmpeg = URL(fileURLWithPath: root).appendingPathComponent("\(architecture)/bin/ffmpeg")
            if fileManager.isExecutableFile(atPath: ytDlp.path), fileManager.isExecutableFile(atPath: ffmpeg.path) {
                return ToolPaths(ytDlp: ytDlp, ffmpeg: ffmpeg)
            }
        }

        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for directory in searchPaths {
            let ytDlp = URL(fileURLWithPath: directory).appendingPathComponent("yt-dlp")
            let ffmpeg = URL(fileURLWithPath: directory).appendingPathComponent("ffmpeg")
            if fileManager.isExecutableFile(atPath: ytDlp.path), fileManager.isExecutableFile(atPath: ffmpeg.path) {
                return ToolPaths(ytDlp: ytDlp, ffmpeg: ffmpeg)
            }
        }

        throw EngineError.toolsMissing
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}

enum EngineError: LocalizedError {
    case toolsMissing
    case invalidURL
    case unsupportedSource
    case outputNotFound

    var errorDescription: String? {
        switch self {
        case .toolsMissing: "VIDLOAD Engine could not find its bundled yt-dlp and FFmpeg tools."
        case .invalidURL: "Paste a valid HTTP or HTTPS link."
        case .unsupportedSource: "This first version supports public YouTube and Instagram links."
        case .outputNotFound: "yt-dlp did not report an output file."
        }
    }
}

final class DownloadRunner {
    private let store: JobStore
    private let tools: ToolPaths
    private let destination: URL

    init(store: JobStore, tools: ToolPaths, destination: URL) {
        self.store = store
        self.tools = tools
        self.destination = destination
    }

    func start(_ job: DownloadJob) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak job] in
            guard let self, let job else { return }
            self.run(job)
        }
    }

    func cancel(_ jobID: String) -> Bool {
        store.withJob(jobID) { job in
            guard job.status == .queued || job.status == .running else { return false }
            job.cancelled = true
            job.detail = "Cancelling"
            job.process?.terminate()
            return true
        } ?? false
    }

    private func run(_ job: DownloadJob) {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            guard !job.cancelled else {
                job.status = .cancelled
                return
            }

            job.status = .running
            job.stage = .preparing
            job.detail = "Checking available formats"

            let process = Process()
            let pipe = Pipe()
            let outputTemplate = destination.appendingPathComponent("%(title).200B [%(id)s].%(ext)s").path
            process.executableURL = tools.ytDlp
            process.arguments = [
                "--ignore-config",
                "--newline",
                "--no-playlist",
                "--progress-delta", "0.25",
                "--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path,
                "--progress-template", "download:PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                "--print", "after_move:FILE:%(filepath)s",
                "-o", outputTemplate
            ] + job.format.ytDlpArguments + [job.sourceURL.absoluteString]
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = environment(for: [tools.ytDlp, tools.ffmpeg])
            job.process = process

            pipe.fileHandleForReading.readabilityHandler = { [weak self, weak job] handle in
                let data = handle.availableData
                guard !data.isEmpty, let self, let job else { return }
                self.consumeDownloadOutput(data, job: job)
            }

            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            if !job.pendingOutput.isEmpty {
                handleDownloadLine(job.pendingOutput.trimmingCharacters(in: .whitespacesAndNewlines), job: job)
                job.pendingOutput = ""
            }

            if job.cancelled {
                job.status = .cancelled
                job.detail = "Cancelled"
                return
            }

            guard process.terminationStatus == 0 else {
                job.status = .failed
                job.error = "yt-dlp exited with code \(process.terminationStatus)."
                job.detail = "Download failed"
                return
            }

            guard let outputPath = job.outputPath else { throw EngineError.outputNotFound }
            if job.format == .mp4 {
                convertForPremiere(job: job, source: URL(fileURLWithPath: outputPath))
            } else {
                job.progress = 100
                job.status = .completed
                job.detail = "Audio ready"
            }
        } catch {
            job.status = job.cancelled ? .cancelled : .failed
            job.error = error.localizedDescription
            job.detail = job.cancelled ? "Cancelled" : "Download failed"
        }
    }

    private func consumeDownloadOutput(_ data: Data, job: DownloadJob) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        job.pendingOutput += text
        let lines = job.pendingOutput.components(separatedBy: .newlines)
        job.pendingOutput = lines.last ?? ""
        lines.dropLast().forEach { handleDownloadLine($0.trimmingCharacters(in: .whitespacesAndNewlines), job: job) }
    }

    private func handleDownloadLine(_ line: String, job: DownloadJob) {
        guard !line.isEmpty else { return }

        if let range = line.range(of: "PROGRESS:") {
            job.stage = .downloading
            job.detail = ""
            let fields = line[range.upperBound...].split(separator: "|", omittingEmptySubsequences: false)
            if let raw = fields.first {
                let percent = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                job.progress = min(max(Double(percent) ?? 0, 0), 100)
            }
            let speed = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
            let eta = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespaces) : ""
            job.detail = [speed.isEmpty ? nil : speed, eta.isEmpty ? nil : "\(eta) remaining"].compactMap { $0 }.joined(separator: " · ")
        } else if job.stage == .preparing && (line.contains("[download] Destination:") || line.contains("[download] Downloading")) {
            job.stage = .downloading
            job.detail = "Receiving data"
        }

        if let range = line.range(of: "FILE:") {
            let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { job.outputPath = path }
        }
    }

    private func convertForPremiere(job: DownloadJob, source: URL) {
        let temporary = source.deletingLastPathComponent().appendingPathComponent(".vidload-premiere-\(UUID().uuidString).mp4")
        let process = Process()
        let pipe = Pipe()
        job.stage = .converting
        job.progress = 0
        job.detail = "Preparing H.264/AAC media"
        job.conversionDuration = mediaDuration(of: source)
        job.conversionSeconds = 0
        job.process = process
        process.executableURL = tools.ffmpeg
        process.arguments = [
            "-hide_banner", "-nostats", "-y", "-i", source.path,
            "-map", "0:v:0?", "-map", "0:a?", "-map_metadata", "0",
            "-c:v", "h264_videotoolbox", "-b:v", "12M", "-maxrate", "16M", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
            "-progress", "pipe:1", temporary.path
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = environment(for: [tools.ffmpeg])
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak job] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let job else { return }
            self.consumeConversionOutput(data, job: job)
        }

        do {
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil

            guard !job.cancelled else {
                try? FileManager.default.removeItem(at: temporary)
                job.status = .cancelled
                job.detail = "Cancelled"
                return
            }

            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: temporary.path) else {
                job.status = .failed
                job.error = "FFmpeg could not prepare a Premiere-compatible MP4."
                job.detail = "Conversion failed"
                return
            }

            do {
                _ = try FileManager.default.replaceItemAt(source, withItemAt: temporary)
                job.outputPath = source.path
            } catch {
                job.outputPath = temporary.path
            }
            job.progress = 100
            job.status = .completed
            job.detail = "Premiere-compatible MP4 ready"
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            job.status = .failed
            job.error = error.localizedDescription
            job.detail = "Conversion failed"
        }
    }

    private func consumeConversionOutput(_ data: Data, job: DownloadJob) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        text.components(separatedBy: .newlines).forEach { line in
            if line.hasPrefix("out_time_us="), let value = Double(line.dropFirst("out_time_us=".count)) {
                job.conversionSeconds = value / 1_000_000
            } else if line.hasPrefix("out_time=") {
                job.conversionSeconds = parsedTime(String(line.dropFirst("out_time=".count))) ?? job.conversionSeconds
            } else {
                return
            }

            guard let duration = job.conversionDuration, duration > 0 else { return }
            job.progress = min(max((job.conversionSeconds / duration) * 100, 0), 99.5)
            job.detail = "\(formatted(job.conversionSeconds)) of \(formatted(duration))"
        }
    }

    private func mediaDuration(of source: URL) -> TimeInterval? {
        let probe = Process()
        let pipe = Pipe()
        let probeURL = tools.ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: probeURL.path) else { return nil }
        probe.executableURL = probeURL
        probe.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", source.path]
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        probe.environment = environment(for: [tools.ffmpeg])
        do {
            try probe.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            return String(data: data, encoding: .utf8).flatMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        } catch {
            return nil
        }
    }

    private func environment(for tools: [URL]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let directories = tools.map { $0.deletingLastPathComponent().path } + [environment["PATH"] ?? ""]
        environment["PATH"] = directories.filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }

    private func parsedTime(_ value: String) -> TimeInterval? {
        let components = value.split(separator: ":").compactMap { TimeInterval($0) }
        guard components.count == 3 else { return nil }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let value = max(Int(seconds), 0)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
}

final class HTTPServer {
    private let listener: NWListener
    private let store: JobStore
    private let runner: DownloadRunner

    init(store: JobStore, runner: DownloadRunner) throws {
        self.store = store
        self.runner = runner
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("VIDLOAD Plugin Engine listening on http://\(host):\(port)")
            case .failed(let error):
                fputs("VIDLOAD Plugin Engine could not listen on port \(port): \(error.localizedDescription)\n", stderr)
                exit(1)
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "com.anosovvv.vidload-plugin-pr.server"))
        dispatchMain()
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = self.parse(data) else {
                self?.respond(connection, status: 400, body: ["error": "Malformed request"])
                return
            }
            self.route(request, connection: connection)
        }
    }

    private func parse(_ data: Data) -> HTTPRequest? {
        guard let message = String(data: data, encoding: .utf8), let separator = message.range(of: "\r\n\r\n") else { return nil }
        let header = String(message[..<separator.lowerBound])
        let bodyStart = separator.upperBound
        let body = Data(message[bodyStart...].utf8)
        guard let firstLine = header.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1].split(separator: "?").first ?? ""), body: body)
    }

    private func route(_ request: HTTPRequest, connection: NWConnection) {
        if request.method == "OPTIONS" {
            respond(connection, status: 204, body: Optional<String>.none)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            respond(connection, status: 200, body: ["status": "ready", "version": "0.1.0"])

        case ("POST", "/v1/downloads"):
            do {
                let payload = try JSONDecoder().decode(DownloadRequest.self, from: request.body)
                let url = try validatedURL(from: payload.url)
                let job = DownloadJob(sourceURL: url, format: payload.format)
                store.add(job)
                runner.start(job)
                respond(connection, status: 202, body: ["id": job.id, "status": JobStatus.queued.rawValue])
            } catch {
                respond(connection, status: 422, body: ["error": error.localizedDescription])
            }

        default:
            if let id = jobID(from: request.path) {
                if request.method == "GET", let job = store.snapshot(for: id) {
                    respond(connection, status: 200, body: job)
                } else if request.method == "DELETE" {
                    let cancelled = runner.cancel(id)
                    respond(connection, status: cancelled ? 202 : 404, body: ["cancelled": cancelled])
                } else {
                    respond(connection, status: 404, body: ["error": "Job not found"])
                }
            } else {
                respond(connection, status: 404, body: ["error": "Not found"])
            }
        }
    }

    private func jobID(from path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "v1", parts[1] == "downloads" else { return nil }
        return String(parts[2])
    }

    private func respond<T: Encodable>(_ connection: NWConnection, status: Int, body: T?) {
        let bodyData = (try? JSONEncoder().encode(body)) ?? Data()
        let reason = status == 200 ? "OK" : status == 202 ? "Accepted" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : status == 404 ? "Not Found" : "Unprocessable Entity"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func validatedURL(from raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased() else {
            throw EngineError.invalidURL
        }

        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        let isInstagram = host == "instagram.com" || host.hasSuffix(".instagram.com")
        guard isYouTube || isInstagram else { throw EngineError.unsupportedSource }
        return url
    }
}

let store = JobStore()
let tools: ToolPaths
do {
    tools = try ToolPaths.locate()
} catch {
    fputs("VIDLOAD Plugin Engine: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
let destination = downloads.appendingPathComponent("VIDLOAD Plugin Pr", isDirectory: true)
let runner = DownloadRunner(store: store, tools: tools, destination: destination)

do {
    try HTTPServer(store: store, runner: runner).start()
} catch {
    fputs("VIDLOAD Plugin Engine could not start: \(error.localizedDescription)\n", stderr)
    exit(1)
}
