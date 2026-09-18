import Foundation
import AVFoundation

final class VideoWriter {

    private var assetWriter: AVAssetWriter?

    private var videoInput: AVAssetWriterInput?

    private(set) var fileURL: URL?

    private var isWriting = false
    private let lock = NSLock()
    private var isPaused = false
    private var pauseStart: CMTime?
    private var pausedDuration = CMTime.zero

    func start(
        at url: URL,
        width: Int,
        height: Int
    ) throws {

        let fileManager = FileManager.default

        if fileManager.fileExists(
            atPath: url.path
        ) {
            try fileManager.removeItem(
                at: url
            )
        }

        let writer = try AVAssetWriter(
            outputURL: url,
            fileType: .mov
        )

        let settings: [String: Any] = [

            AVVideoCodecKey:
                AVVideoCodecType.h264,

            AVVideoWidthKey:
                width,

            AVVideoHeightKey:
                height
        ]

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: settings
        )

        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw VideoWriterError.cannotAddInput
        }

        writer.add(input)

        assetWriter = writer
        videoInput = input
        fileURL = url

        isWriting = false
        isPaused = false
        pauseStart = nil
        pausedDuration = .zero
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        isPaused = true
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        isPaused = false
    }

    func append(
        _ sampleBuffer: CMSampleBuffer
    ) {

        lock.lock()
        defer { lock.unlock() }

        guard let writer = assetWriter,
              let input = videoInput else {
            return
        }

        guard CMSampleBufferDataIsReady(
            sampleBuffer
        ) else {
            return
        }

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isPaused {
            if pauseStart == nil {
                pauseStart = sourceTime
            }
            return
        }

        if let pauseStart {
            pausedDuration = CMTimeAdd(pausedDuration, CMTimeSubtract(sourceTime, pauseStart))
            self.pauseStart = nil
        }

        let adjustedBuffer = retimed(sampleBuffer, offset: pausedDuration) ?? sampleBuffer

        if !isWriting {
            writer.startWriting()
            writer.startSession(
                atSourceTime: CMSampleBufferGetPresentationTimeStamp(adjustedBuffer)
            )

            isWriting = true
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        input.append(adjustedBuffer)
    }

    func finish(
        completion: @escaping (URL?) -> Void
    ) {

        lock.lock()
        defer { lock.unlock() }

        guard let writer = assetWriter,
              let input = videoInput else {

            completion(nil)
            return
        }

        input.markAsFinished()

        writer.finishWriting { [weak self] in

            let url = self?.fileURL

            self?.assetWriter = nil
            self?.videoInput = nil
            self?.fileURL = nil
            self?.isWriting = false
            self?.isPaused = false
            self?.pauseStart = nil
            self?.pausedDuration = .zero

            completion(url)
        }
    }

    private func retimed(
        _ sampleBuffer: CMSampleBuffer,
        offset: CMTime
    ) -> CMSampleBuffer? {
        guard offset != .zero else { return sampleBuffer }
        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
        timing.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, offset)
        timing.decodeTimeStamp = timing.decodeTimeStamp.isValid
            ? CMTimeSubtract(timing.decodeTimeStamp, offset) : .invalid
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        ) == noErr else { return nil }
        return copy
    }
}

enum VideoWriterError: Error {

    case cannotAddInput
}
