import Foundation
import React

@objc(MpvPlayerViewManager)
class MpvViewManager: RCTViewManager {

    override func view() -> UIView! {
        return MpvPlayerView()
    }

    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    // Commands dispatched from JS
    @objc func seekTo(_ node: NSNumber, seconds: Double) {
        DispatchQueue.main.async {
            guard let view = self.bridge?.uiManager.view(forReactTag: node) as? MpvPlayerView else { return }
            view.seekTo(seconds)
        }
    }

    @objc func seekRelative(_ node: NSNumber, seconds: Double) {
        DispatchQueue.main.async {
            guard let view = self.bridge?.uiManager.view(forReactTag: node) as? MpvPlayerView else { return }
            view.seekRelative(seconds)
        }
    }

    @objc func setAudioTrack(_ node: NSNumber, trackId: Int) {
        DispatchQueue.main.async {
            guard let view = self.bridge?.uiManager.view(forReactTag: node) as? MpvPlayerView else { return }
            view.setAudioTrack(trackId)
        }
    }

    @objc func setSubtitleTrack(_ node: NSNumber, trackId: Int) {
        DispatchQueue.main.async {
            guard let view = self.bridge?.uiManager.view(forReactTag: node) as? MpvPlayerView else { return }
            view.setSubtitleTrack(trackId)
        }
    }

    @objc func stop(_ node: NSNumber) {
        DispatchQueue.main.async {
            guard let view = self.bridge?.uiManager.view(forReactTag: node) as? MpvPlayerView else { return }
            view.stop()
        }
    }
}
