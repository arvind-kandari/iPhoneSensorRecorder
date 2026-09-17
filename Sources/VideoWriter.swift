import Foundation
import AVFoundation

final class VideoWriter {

    private var assetWriter: AVAssetWriter?

    private var videoInput: AVAssetWriterInput?

    private(set) var fileURL: URL?

    private var isWriting = false

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
    }

    func append(
        _ sampleBuffer: CMSampleBuffer
    ) {

        guard let writer = assetWriter,
              let input = videoInput else {
            return
        }

        guard CMSampleBufferDataIsReady(
            sampleBuffer
        ) else {
            return
        }

        if !isWriting {

            let timestamp =
                CMSampleBufferGetPresentationTimeStamp(
                    sampleBuffer
                )

            writer.startWriting()

            writer.startSession(
                atSourceTime: timestamp
            )

            isWriting = true
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }

    func finish(
        completion: @escaping (URL?) -> Void
    ) {

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

            completion(url)
        }
    }
}

enum VideoWriterError: Error {

    case cannotAddInput
}