#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(MpvModule, NSObject)

RCT_EXTERN_METHOD(isAvailable:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

@end
