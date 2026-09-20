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
        audioEnabled: Bool
    ) throws {

        lock.lock()
        defer { lock.unlock() }

        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

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

        guard let input = input else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard let writer = writer else {
            return
        }

        guard writer.status == .unknown || writer.status == .writing else {
            return
        }

        let sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !isStarted {

            guard writer.status == .unknown else {
                return
            }

            writer.startWriting()
            writer.startSession(atSourceTime: sourceTime)

            isStarted = true
        }

        if isPaused {

            if pauseStartTime == nil {
                pauseStartTime = sourceTime
            }

            return
        }

        var retimedBuffer = sampleBuffer

        if pausedDuration > .zero {

            var timingInfo = [CMSampleTimingInfo](
                repeating: CMSampleTimingInfo(
                    duration: .zero,
                    presentationTimeStamp: .zero,
                    decodeTimeStamp: .invalid
                ),
                count: CMSampleBufferGetNumSamples(sampleBuffer)
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

        guard isStarted else {
            return
        }

        isPaused = true
        pauseStartTime = nil
    }

    func resume() {

        lock.lock()
        defer { lock.unlock() }

        guard isStarted else {
            return
        }

        isPaused = false

        pauseStartTime = nil
    }

    func finish(completion: @escaping (URL?) -> Void) {

        lock.lock()

        guard let writer = writer else {
            lock.unlock()
            completion(videoURL)
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let outputURL = videoURL

        writer.finishWriting { [weak self] in

            self?.lock.lock()

            let success = writer.status == .completed

            self?.writer = nil
            self?.videoInput = nil
            self?.audioInput = nil
            self?.isStarted = false
            self?.isPaused = false

            self?.lock.unlock()

            completion(success ? outputURL : nil)
        }

        lock.unlock()
    }
}