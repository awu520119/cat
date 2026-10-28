#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "KimiShared.h"
@class KimiGlassBubbleView;
NS_ASSUME_NONNULL_BEGIN

// 素材渲染类型在加载时确定，绘制阶段不再根据当前帧临时猜测，避免透明角色与照片卡片互相串台。
typedef NS_ENUM(NSInteger, KimiMediaRenderKind) {
    KimiMediaRenderKindPhoto = 0,
    KimiMediaRenderKindTransparentCharacter,
    KimiMediaRenderKindAction,
    KimiMediaRenderKindVideo
};

@interface KimiPetView : NSView
@property (nonatomic) KimiState state;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURL *> *videoURLs;
@property (nonatomic, copy) NSArray<NSString *> *mediaFiles;
@property (nonatomic, copy) NSArray<NSString *> *carouselFiles;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *mediaRenderKinds;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSArray<NSString *> *> *statePools;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *statePoolIndexes;
@property (nonatomic, copy, nullable) NSString *currentMediaFile;
@property (nonatomic, strong, nullable) AVPlayer *videoPlayer;
@property (nonatomic, strong, nullable) AVPlayerLayer *videoLayer;
@property (nonatomic, strong, nullable) id videoEndObserver;
@property (nonatomic) CGFloat animationTime;
@property (nonatomic) NSTimeInterval renderAccumulator;
@property (nonatomic, strong) NSDate *lastInteractionAt;
@property (nonatomic, strong, nullable) NSDate *transientStateUntil;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic, strong, nullable) NSDate *messageUntil;
@property (nonatomic, strong) NSDate *nextNudgeAt;
@property (nonatomic, strong) NSDate *nextImageSwapAt;
@property (nonatomic) NSPoint lastDragScreenPoint;
@property (nonatomic) BOOL hasLastDragScreenPoint;
@property (nonatomic) BOOL didDragWindow;
@property (nonatomic) BOOL isHidden;
@property (nonatomic) BOOL manualSleep;
@property (nonatomic) BOOL mousePassthroughEnabled;
@property (nonatomic) NSRect lastBubbleRect;
@property (nonatomic, strong, nullable) NSDictionary<NSNumber *, NSArray<NSString *> *> *actionFramesByState;
@property (nonatomic) BOOL isMouseInside;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, copy) NSString *petName;

// 独立呈现的台词气泡
@property (nonatomic, strong, nullable) KimiGlassBubbleView *glassBubble;

// 弹簧形变：正值为压扁（宽/矮），负值为拉伸（窄/高）。
// tick 中做阻尼弹簧积分，绘制时绕脚底中心缩放。
@property (nonatomic) CGFloat squashValue;
@property (nonatomic) CGFloat squashVelocity;

// 施加一次形变冲量（互动反馈用）
- (void)addSquashImpulse:(CGFloat)impulse;

// 刷新台词气泡的位置与内容（气泡由 message 驱动）
- (void)updateGlassBubbleIfNeeded;

// 生命周期与窗口
- (void)saveWindowState;
- (void)toggleSleep;
- (void)hidePet;
- (void)showPet;
- (void)toggleMousePassthrough;
- (void)reloadMedia;

// 设置面板联动
- (void)reloadNudgeLevel;
- (void)refreshIntimacyLabel:(NSTextField *)label;

// 素材与帧动画（供绘制分类使用）
- (nullable NSImage *)imageForFile:(nullable NSString *)fileName;
- (BOOL)isActionAssetFile:(NSString *)fileName;
- (KimiMediaRenderKind)mediaRenderKindForFile:(NSString *)fileName;
- (BOOL)isVideoFile:(NSString *)fileName;
- (NSString *)currentActionFrameFileForState:(KimiState)state;
- (NSInteger)intimacyLevel;

@end
NS_ASSUME_NONNULL_END
