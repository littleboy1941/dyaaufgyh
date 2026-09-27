import Foundation
import Photos
import SwiftSignalKit
import TelegramCore
import DeviceAccess
import AccountContext

public enum AyuSaveToCameraRollError {
    case accessDenied
    case saveFailed
}

// Ayu: unlike the upstream NoError exporter, report permission and Photos failures
// separately from successful completion. Both viewers use the same download/save path.
public func ayuSaveToCameraRoll(context: AccountContext, userLocation: MediaResourceUserLocation, customUserContentType: MediaResourceUserContentType? = nil, mediaReference: AnyMediaReference) -> Signal<Float, AyuSaveToCameraRollError> {
    guard mediaReference.media is TelegramMediaImage || (mediaReference.media as? TelegramMediaFile)?.isVideo == true else {
        return .fail(.saveFailed)
    }

    return Signal { subscriber in
        let ayuCancelled = Atomic<Bool>(value: false)
        var ayuStartedSaving = false
        let ayuFetchDisposable = (fetchMediaData(context: context, userLocation: userLocation, customUserContentType: customUserContentType, mediaReference: mediaReference)
        |> deliverOnMainQueue).start(next: { state, isImage in
            guard !ayuStartedSaving else {
                return
            }
            switch state {
            case let .progress(progress):
                subscriber.putNext(progress * 0.95)
            case let .data(data):
                guard data.isComplete else {
                    return
                }
                ayuStartedSaving = true
                DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { controller, arguments in
                    context.sharedContext.presentGlobalController(controller, arguments)
                }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
                    guard !ayuCancelled.with({ $0 }) else {
                        return
                    }
                    guard authorized else {
                        subscriber.putError(.accessDenied)
                        return
                    }
                    Queue.concurrentDefaultQueue().async {
                        guard !ayuCancelled.with({ $0 }) else {
                            return
                        }
                        let ayuVideoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Ayu-" + UUID().uuidString + ".mp4")
                        let ayuImageData: Data?
                        do {
                            if isImage {
                                ayuImageData = try Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe)
                            } else {
                                ayuImageData = nil
                                try FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: ayuVideoURL)
                            }
                        } catch {
                            if !isImage {
                                try? FileManager.default.removeItem(at: ayuVideoURL)
                            }
                            subscriber.putError(.saveFailed)
                            return
                        }
                        guard !ayuCancelled.with({ $0 }) else {
                            if !isImage {
                                try? FileManager.default.removeItem(at: ayuVideoURL)
                            }
                            return
                        }
                        PHPhotoLibrary.shared().performChanges({
                            if let ayuImageData {
                                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: ayuImageData, options: nil)
                            } else {
                                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: ayuVideoURL, options: nil)
                            }
                        }, completionHandler: { success, _ in
                            if !isImage {
                                try? FileManager.default.removeItem(at: ayuVideoURL)
                            }
                            guard !ayuCancelled.with({ $0 }) else {
                                return
                            }
                            if success {
                                subscriber.putNext(1.0)
                                subscriber.putCompletion()
                            } else {
                                subscriber.putError(.saveFailed)
                            }
                        })
                    }
                })
            }
        }, completed: {
            if !ayuStartedSaving {
                subscriber.putError(.saveFailed)
            }
        })
        return ActionDisposable {
            let _ = ayuCancelled.swap(true)
            ayuFetchDisposable.dispose()
        }
    }
}
