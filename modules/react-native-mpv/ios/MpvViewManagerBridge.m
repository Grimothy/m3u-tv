#import <React/RCTViewManager.h>
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(MpvPlayerViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(uri, NSString)
RCT_EXPORT_VIEW_PROPERTY(userAgent, NSString)
RCT_EXPORT_VIEW_PROPERTY(paused, BOOL)
RCT_EXPORT_VIEW_PROPERTY(startPosition, double)

RCT_EXPORT_VIEW_PROPERTY(onMpvLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMpvProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMpvBuffer, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMpvError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMpvEnd, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMpvTracksChanged, RCTDirectEventBlock)

RCT_EXTERN_METHOD(seekTo:(nonnull NSNumber *)node seconds:(double)seconds)
RCT_EXTERN_METHOD(seekRelative:(nonnull NSNumber *)node seconds:(double)seconds)
RCT_EXTERN_METHOD(setAudioTrack:(nonnull NSNumber *)node trackId:(NSInteger)trackId)
RCT_EXTERN_METHOD(setSubtitleTrack:(nonnull NSNumber *)node trackId:(NSInteger)trackId)
RCT_EXTERN_METHOD(stop:(nonnull NSNumber *)node)

@end
