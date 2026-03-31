import Foundation

@objc(MpvModule)
class MpvModule: NSObject {

    @objc static func moduleName() -> String {
        return "MpvModule"
    }

    @objc static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc func isAvailable(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        resolve(true)
    }
}
