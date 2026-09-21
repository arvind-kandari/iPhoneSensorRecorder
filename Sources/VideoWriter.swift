import AVFoundation

enum VideoWriterError: Error {
    case cannotCreateWriter
    case cannotAddVideoInput
    case cannotAddAudioInput
    case cannotStartWriting
    case cannotFinishWriting
}

final class VideoWriter {

    private let lock = NSLock()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    private var isStarted = false
    private var isPaused = false

    private var pauseStartTime: CMTime?
    private var pausedDuration = CMTime.zero

    private var videoURL: URL?

    func start(
        url: URL,
        width: Int,
        height: Int,
        fps: Double,
        audioEnabled: Bool,
        transform: CGAffineTransform
    ) throws {

        lock.lock()
        defer { lock.unlock() }

        let assetWriter = try AVAssetWriter(
            outputURL: url,
            fileType: .mov
        )

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps)
            ]
        ]

        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )

        video.expectsMediaDataInRealTime = true

        // IMPORTANT:
        // Store portrait orientation in the video file.
        video.transform = transform

        guard assetWriter.canAdd(video) else {
            throw VideoWriterError.cannotAddVideoInput
        }

        assetWriter.add(video)

        var audio: AVAssetWriterInput?

        if audioEnabled {

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]

            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioSettings
            )

            audioInput.expectsMediaDataInRealTime = true

            guard assetWriter.canAdd(audioInput) else {
                throw VideoWriterError.cannotAddAudioInput
            }

            assetWriter.add(audioInput)
            audio = audioInput
        }

        writer = assetWriter
        videoInput = video
        audioInput = audio
        videoURL = url

        isStarted = false
        isPaused = false
        pauseStartTime = nil
        pausedDuration = .zero
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        appendBuffer(
            sampleBuffer,
            to: videoInput
        )
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        appendBuffer(
            sampleBuffer,
            to: audioInput
        )
    }

    private func appendBuffer(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?
    ) {

        guard let input else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard let writer else {
            return
        }

        guard writer.status == .unknown || writer.status == .writing else {
            return
        }

        let sourceTime =
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Start writer on first received sample.
        if !isStarted {

            guard writer.status == .unknown else {
                return
            }

            guard writer.startWriting() else {
                return
            }

            writer.startSession(atSourceTime: sourceTime)

            isStarted = true
        }

        // During pause, don't write frames.
        if isPaused {

            if pauseStartTime == nil {
                pauseStartTime = sourceTime
            }

            return
        }

        // We have resumed.
        // Calculate the complete duration of the pause using
        // the first frame received after resume.
        if let pauseStartTime {

            let currentPauseDuration =
                CMTimeSubtract(
                    sourceTime,
                    pauseStartTime
                )

            if currentPauseDuration.isValid &&
                currentPauseDuration > .zero {

                pausedDuration =
                    CMTimeAdd(
                        pausedDuration,
                        currentPauseDuration
                    )
            }

            self.pauseStartTime = nil
        }

        var retimedBuffer = sampleBuffer

        // Remove all accumulated pause time from the timestamps.
        if pausedDuration > .zero {

            var timingInfo = [
                CMSampleTimingInfo
            ](
                repeating: CMSampleTimingInfo(
                    duration: .zero,
                    presentationTimeStamp: .zero,
                    decodeTimeStamp: .invalid
                ),
                count: CMSampleBufferGetNumSamples(
                    sampleBuffer
                )
            )

            var count = timingInfo.count

            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: count,
                arrayToFill: &timingInfo,
                entriesNeededOut: &count
            )

            for index in 0..<count {

                timingInfo[index].presentationTimeStamp =
                    CMTimeSubtract(
                        timingInfo[index].presentationTimeStamp,
                        pausedDuration
                    )

                if timingInfo[index].decodeTimeStamp.isValid {

                    timingInfo[index].decodeTimeStamp =
                        CMTimeSubtract(
                            timingInfo[index].decodeTimeStamp,
                            pausedDuration
                        )
                }
            }

            var newBuffer: CMSampleBuffer?

            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: count,
                sampleTimingArray: timingInfo,
                sampleBufferOut: &newBuffer
            )

            if let newBuffer {
                retimedBuffer = newBuffer
            }
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        input.append(retimedBuffer)
    }

    func pause() {

        lock.lock()
        defer { lock.unlock() }

        guard isStarted, !isPaused else {
            return
        }

        isPaused = true
        pauseStartTime = nil
    }

    func resume() {

        lock.lock()
        defer { lock.unlock() }

        guard isStarted, isPaused else {
            return
        }

        // IMPORTANT:
        // Do NOT clear pauseStartTime here.
        // The first frame after resume is used to calculate
        // the exact pause duration.

        isPaused = false
    }

    func finish(
        completion: @escaping (URL?) -> Void
    ) {

        lock.lock()

        guard let writer else {
            lock.unlock()
            completion(videoURL)
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let outputURL = videoURL

        writer.finishWriting { [weak self] in

            self?.lock.lock()

            let success =
                writer.status == .completed

            self?.writer = nil
            self?.videoInput = nil
            self?.audioInput = nil
            self?.isStarted = false
            self?.isPaused = false
            self?.pauseStartTime = nil
            self?.pausedDuration = .zero

            self?.lock.unlock()

            completion(
                success
                    ? outputURL
                    : nil
            )
        }

        lock.unlock()
    }
}