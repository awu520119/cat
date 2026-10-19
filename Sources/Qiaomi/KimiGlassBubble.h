// 俏咪对话气泡视图：浅色矢量底板、文字与短尾巴。
// hitTest 返回 nil：点击/悬停事件穿透到桌宠视图（气泡续读逻辑不受影响）。
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface KimiGlassBubbleView : NSView

/// 显示台词；text 为空时隐藏。
- (void)presentWithText:(nullable NSString *)text fontSize:(CGFloat)fontSize;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
