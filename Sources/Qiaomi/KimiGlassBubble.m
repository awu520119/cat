#import "KimiGlassBubble.h"
#import <QuartzCore/QuartzCore.h>

@interface KimiGlassBubbleView ()
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) CAShapeLayer *bubbleLayer;
@property (nonatomic, strong) CAShapeLayer *tailLayer;
@end

@implementation KimiGlassBubbleView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.bubbleLayer = [CAShapeLayer layer];
        // Keep the surface warm white; teal is only a quiet edge accent, not a competing fill.
        NSColor *bubbleFill = [NSColor colorWithCalibratedRed:1.00 green:0.995 blue:0.975 alpha:0.99];
        self.bubbleLayer.fillColor = bubbleFill.CGColor;
        self.bubbleLayer.strokeColor = [NSColor colorWithCalibratedRed:0.31 green:0.52 blue:0.52 alpha:0.28].CGColor;
        self.bubbleLayer.lineWidth = 0.8;
        [self.layer addSublayer:self.bubbleLayer];

        self.tailLayer = [CAShapeLayer layer];
        self.tailLayer.fillColor = bubbleFill.CGColor;
        self.tailLayer.strokeColor = self.bubbleLayer.strokeColor;
        self.tailLayer.lineWidth = 1.0;
        [self.layer addSublayer:self.tailLayer];

        self.label = [NSTextField labelWithString:@""];
        self.label.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightBold];
        self.label.textColor = [NSColor colorWithCalibratedWhite:0.04 alpha:1.0];
        self.label.maximumNumberOfLines = 0;
        self.label.lineBreakMode = NSLineBreakByCharWrapping;
        self.label.usesSingleLineMode = NO;
        self.label.cell.wraps = YES;
        self.label.cell.truncatesLastVisibleLine = NO;
        self.label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:self.label];

        self.hidden = YES;
    }
    return self;
}

- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds) || self.hidden) {
        return;
    }

    self.label.frame = NSInsetRect(bounds, 12, 8);

    CGRect bubbleRect = CGRectInset(bounds, 0.5, 0.5);
    self.bubbleLayer.path = [NSBezierPath bezierPathWithRoundedRect:bubbleRect xRadius:14 yRadius:14].CGPath;

    CGFloat tailWidth = 10.0;
    CGFloat tailHeight = 5.0;
    CGFloat tailX = NSMidX(bounds) + MIN(26, bounds.size.width * 0.20);
    NSBezierPath *tail = [NSBezierPath bezierPath];
    [tail moveToPoint:NSMakePoint(tailX - tailWidth / 2.0, NSMinY(bounds) + 1)];
    [tail lineToPoint:NSMakePoint(tailX, NSMinY(bounds) - tailHeight)];
    [tail lineToPoint:NSMakePoint(tailX + tailWidth / 2.0, NSMinY(bounds) + 1)];
    self.tailLayer.path = tail.CGPath;
}

// MARK: - 显示/隐藏

- (void)presentWithText:(NSString *)text
                fontSize:(CGFloat)fontSize {
    if (text.length == 0) {
        [self dismiss];
        return;
    }
    BOOL contentChanged = ![_label.stringValue isEqualToString:text];
    _label.stringValue = text;
    _label.font = [NSFont systemFontOfSize:MIN(MAX(fontSize, 11.0), 14.5)
                                   weight:NSFontWeightBold];

    if (self.hidden) {
        self.hidden = NO;
        [self setNeedsLayout:YES];
        // No spring, glow or scale pulse.
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(0.0);
        fade.toValue = @(1.0);
        fade.duration = 0.132;
        [self.layer addAnimation:fade forKey:@"bubbleFade"];
    } else if (contentChanged) {
        [self setNeedsLayout:YES];
    }
}

- (void)dismiss {
    if (self.hidden) {
        return;
    }
    self.hidden = YES;
    [self.layer removeAllAnimations];
}

- (NSView *)hitTest:(NSPoint)point {
    // 事件穿透：气泡不拦截点击/悬停，桌宠视图继续处理（续读、逗弄等）。
    return nil;
}

@end
