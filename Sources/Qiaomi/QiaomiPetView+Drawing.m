#import "QiaomiPetView.h"

@implementation KimiPetView (Drawing)
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.clearColor setFill];
    NSRectFill(dirtyRect);

    NSRect bodyRect = [self currentBodyRect];
    CGFloat offsetY = [self idleOffset];
    NSRect petRect = NSOffsetRect(bodyRect, 0, offsetY);

    // Each action gets a small character-led gesture: hop, sway or proud pulse.
    // It stays attached to the pet, so interaction reads clearly without particles or floating badges.
    if (self.transientStateUntil && [self.transientStateUntil timeIntervalSinceNow] > 0) {
        NSTimeInterval duration = MAX(0.1, [self.transientStateUntil timeIntervalSinceDate:self.lastInteractionAt]);
        NSTimeInterval elapsed = MAX(0, [[NSDate date] timeIntervalSinceDate:self.lastInteractionAt]);
        CGFloat progress = KimiClamp(elapsed / duration, 0, 1);
        CGFloat envelope = 0.45 + 0.55 * (1.0 - progress);
        CGFloat phase = (CGFloat)elapsed * 9.0;
        CGFloat sway = sin(phase) * envelope;
        switch (self.state) {
            case KimiStatePetting:
                petRect.origin.x += sway * 2.5;
                petRect.origin.y += fabs(sway) * 1.5;
                break;
            case KimiStateKissing:
            case KimiStateNuzzling:
                petRect.origin.x += sway * 2.0;
                petRect.origin.y += MAX(0, sin(phase)) * 6.0 * envelope;
                break;
            case KimiStateTreating:
                petRect.origin.y += MAX(0, sin(phase * 1.15)) * 8.0 * envelope;
                break;
            case KimiStatePlaying:
                petRect.origin.x += sway * 5.0;
                petRect.origin.y += MAX(0, sin(phase * 1.25)) * 3.0 * envelope;
                break;
            case KimiStateGrooming:
                petRect.origin.x += sway * 1.8;
                petRect.origin.y += sin(phase * 0.72) * 1.5 * envelope;
                break;
            case KimiStateShowingOff: {
                CGFloat scale = 1.0 + (0.018 + MAX(0, sin(phase * 0.55)) * 0.018) * envelope;
                petRect.size.width *= scale;
                petRect.size.height *= scale;
                petRect.origin.x = NSMidX(bodyRect) - petRect.size.width / 2.0;
                break;
            }
            default:
                break;
        }
    }

    if (self.state == KimiStatePetting) {
        petRect = NSInsetRect(petRect, -2, -1);
    }

    // 弹簧形变：绕脚底中心缩放，互动/落地时由冲量驱动。
    CGFloat squash = self.squashValue;
    if (fabs(squash) > 0.001) {
        NSRect base = petRect;
        petRect.size.width = base.size.width * (1.0 + squash);
        petRect.size.height = base.size.height * (1.0 - squash);
        petRect.origin.x = NSMidX(base) - petRect.size.width / 2.0;
        petRect.origin.y = NSMinY(base);
    }

    // 背景柔光晕和地面软阴影跟随主体定位。
    // 台词气泡由独立视图承载，角色绘制层只负责宠物本身与环境阴影。
    [self drawAmbientHaloForPetRect:bodyRect];
    [self drawGroundShadowForPetRect:bodyRect];

    [self drawPetMediaInRect:petRect];
}

- (void)drawAmbientHaloForPetRect:(NSRect)rect {
    CGFloat hoverBoost = (self.isMouseInside && !self.didDragWindow) ? 0.06 : 0.0;
    CGFloat alpha = 0.10 + hoverBoost;
    if (alpha <= 0.01) {
        return;
    }

    NSRect haloRect = NSInsetRect(rect, -rect.size.width * 0.16, -rect.size.height * 0.10);
    haloRect.origin.y = rect.origin.y + rect.size.height * 0.02;

    NSGradient *gradient = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedRed:1.00 green:0.96 blue:0.88 alpha:alpha], 0.0,
        [NSColor colorWithCalibratedRed:1.00 green:0.98 blue:0.94 alpha:alpha * 0.5], 0.55,
        [NSColor colorWithCalibratedWhite:1.00 alpha:0.0], 1.0,
        nil];
    [gradient drawInRect:haloRect relativeCenterPosition:NSMakePoint(0, 0.12)];
}

// 地面软阴影：椭圆径向渐变，固定在猫脚底，随呼吸轻微缩放，不随身体上下浮动。
- (void)drawGroundShadowForPetRect:(NSRect)rect {
    CGFloat widthRatio = 0.62;
    CGFloat alpha = 0.24;
    if (self.state == KimiStateSleeping) {
        widthRatio = 0.82;
        alpha = 0.26;
    } else if (self.state == KimiStatePickedUp) {
        widthRatio = 0.40;
        alpha = 0.12;
    }

    CGFloat breathe = 1.0 + sin(self.animationTime * 2.0) * 0.035;
    CGFloat shadowWidth = rect.size.width * widthRatio * breathe;
    CGFloat shadowHeight = KimiClamp(rect.size.height * 0.055, 9, 14);
    if (self.state == KimiStateSleeping) {
        shadowHeight = 11;
    }
    NSRect shadowRect = NSMakeRect(
        NSMidX(rect) - shadowWidth / 2.0,
        NSMinY(rect) - shadowHeight * 0.45,
        shadowWidth,
        shadowHeight
    );

    NSGradient *gradient = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor.blackColor colorWithAlphaComponent:alpha], 0.0,
        [NSColor.blackColor colorWithAlphaComponent:alpha * 0.55], 0.6,
        [NSColor.clearColor colorWithAlphaComponent:0.0], 1.0,
        nil];
    [gradient drawInRect:shadowRect relativeCenterPosition:NSZeroPoint];
}

- (NSRect)currentBodyRect {
    CGFloat sideInset = MAX(12, self.bounds.size.width * 0.0625);
    CGFloat bottomInset = MAX(14, self.bounds.size.height * 0.06);
    CGFloat topSpace = KimiClamp(self.bounds.size.height * 0.25, 56, 82);

    if (self.state == KimiStateSleeping) {
        return NSMakeRect(
            MAX(8, sideInset - 8),
            bottomInset + 4,
            self.bounds.size.width - MAX(16, sideInset),
            self.bounds.size.height - topSpace - bottomInset - 14
        );
    }

    return NSMakeRect(
        sideInset,
        bottomInset,
        self.bounds.size.width - sideInset * 2,
        self.bounds.size.height - topSpace - bottomInset
    );
}

- (CGFloat)idleOffset {
    switch (self.state) {
        case KimiStateIdle:
            return sin(self.animationTime * 2.0) * 2.0;
        case KimiStateBored:
            return sin(self.animationTime * 1.4) * 1.2;
        case KimiStatePetting:
            return sin(self.animationTime * 8.0) * 2.4;
        case KimiStateKissing:
            return sin(self.animationTime * 6.0) * 1.8;
        case KimiStateTreating:
            return sin(self.animationTime * 7.5) * 2.6;
        case KimiStatePlaying:
            return sin(self.animationTime * 9.5) * 3.1;
        case KimiStateGrooming:
            return sin(self.animationTime * 2.8) * 1.4;
        case KimiStateShowingOff:
            return sin(self.animationTime * 8.2) * 2.8;
        case KimiStatePickedUp:
            return sin(self.animationTime * 10.0) * 3.0;
        case KimiStateSleeping:
            return sin(self.animationTime * 1.1) * 0.9;
        case KimiStateNuzzling:
            return sin(self.animationTime * 6.0) * 2.2;
    }
}

- (void)drawPetMediaInRect:(NSRect)rect {
    NSImage *actionImage = self.currentMediaFile ? self.images[self.currentMediaFile] : nil;
    KimiMediaRenderKind renderKind = [self mediaRenderKindForFile:self.currentMediaFile];
    // 当前媒体正在切换/视频首帧尚未到达时保持透明，不回退到照片卡片，避免一闪而过的非透明素材。
    if (self.currentMediaFile.length > 0 && !actionImage &&
        !(renderKind == KimiMediaRenderKindVideo && self.currentVideoFrame)) {
        return;
    }
    if (actionImage && renderKind == KimiMediaRenderKindAction) {
        NSString *frameFile = [self currentActionFrameFileForState:self.state];
        NSImage *frameImage = frameFile ? self.images[frameFile] : actionImage;
        [self drawActionAssetImage:frameImage inRect:rect];
        return;
    }

    // 用户素材库中的透明角色在加载时已确定类型，绘制阶段不再重复采样或误判。
    if (actionImage && renderKind == KimiMediaRenderKindTransparentCharacter) {
        [self drawTransparentCharacterImage:actionImage inRect:rect];
        return;
    }

    // 普通照片和视频直接展示，不叠加贴纸底板、描边或内阴影。
    NSImage *image = actionImage ?: self.currentVideoFrame;
    if (!image) return;
    NSRect mediaRect = NSInsetRect(rect, 2, 2);
    NSRect drawRect = KimiAspectFillRect(image.size, mediaRect);
    CGFloat radius = KimiClamp(mediaRect.size.height * 0.055, 12, 22);
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:mediaRect xRadius:radius yRadius:radius] addClip];
    [image drawInRect:drawRect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:NO
               hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawTransparentCharacterImage:(NSImage *)image inRect:(NSRect)rect {
    NSRect drawRect = KimiAspectFitRect(image.size, NSInsetRect(rect, -5, -7));
    [image drawInRect:drawRect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:NO
               hints:nil];
}

- (void)drawActionAssetImage:(NSImage *)image inRect:(NSRect)rect {
    // 内置动作 PNG 的白色圆角相框约占每边 8%–10%。裁进照片内容，
    // 避免不同动画帧在边缘露出白线或圆角残影。
    NSRect sourceRect = NSMakeRect(image.size.width * 0.12,
                                   image.size.height * 0.12,
                                   image.size.width * 0.76,
                                   image.size.height * 0.76);
    NSRect drawRect = KimiAspectFillRect(sourceRect.size, NSInsetRect(rect, 2, 2));
    CGFloat radius = KimiClamp(drawRect.size.height * 0.055, 12, 22);

    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:drawRect
                                                                xRadius:radius
                                                                yRadius:radius];
    [clipPath addClip];
    NSRect sourceDrawRect = KimiAspectFillRect(sourceRect.size, drawRect);
    [image drawInRect:sourceDrawRect
             fromRect:sourceRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:NO
               hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

- (NSDictionary<NSAttributedStringKey, id> *)messageTextAttributesWithFontSize:(CGFloat)fontSize {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    // 中英文都按字符安全换行，避免无空格长词或中文连续文本溢出。
    paragraph.lineBreakMode = NSLineBreakByCharWrapping;

    NSColor *color = [NSColor colorWithCalibratedWhite:0.06 alpha:1.0];
    NSFontWeight weight = NSFontWeightBold;

    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:weight],
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph
    };
}

// 测量气泡布局：以最终文本绘制宽度二次测量高度，保证气泡恰好容纳全部文本、绝不省略。
- (void)measureSpeechBubbleForMessage:(NSString *)message
                           attributes:(NSDictionary<NSAttributedStringKey, id> **)outAttributes
                           bubbleRect:(NSRect *)outBubbleRect
                            textRect:(NSRect *)outTextRect
                        abovePetRect:(NSRect)petRect {
    CGFloat maxWidth = MAX(120, self.bounds.size.width - 16);
    CGFloat inset = 17.0;
    CGFloat availableWidth = maxWidth - inset * 2;
    CGFloat maxBubbleHeight = MAX(60, self.bounds.size.height - 28);
    CGFloat maxTextHeight = maxBubbleHeight - 14;

    CGFloat fontSize = KimiClamp(self.bounds.size.width * 0.060, 12.0, 14.5);
    NSDictionary<NSAttributedStringKey, id> *attrs = [self messageTextAttributesWithFontSize:fontSize];
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:message attributes:attrs];
    NSRect textBounds = [attributed boundingRectWithSize:NSMakeSize(availableWidth, 10000)
                                                 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    CGFloat textWidth = MIN(availableWidth, ceil(textBounds.size.width));
    CGFloat textHeight = ceil(textBounds.size.height);

    // 超长文本自动缩小字号，保证整句完整可见。
    NSArray<NSNumber *> *smallerSizes = @[@(11.0)];
    for (NSNumber *size in smallerSizes) {
        if (textHeight <= maxTextHeight) {
            break;
        }
        attrs = [self messageTextAttributesWithFontSize:size.doubleValue];
        attributed = [[NSAttributedString alloc] initWithString:message attributes:attrs];
        textBounds = [attributed boundingRectWithSize:NSMakeSize(availableWidth, 10000)
                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
        textWidth = MIN(availableWidth, ceil(textBounds.size.width));
        textHeight = ceil(textBounds.size.height);
    }

    CGFloat bubbleWidth = MIN(maxWidth, MAX(72, textWidth + inset * 2 + 8));
    // 以最终文本宽度重新测量，得到精确行数与高度，绘制时不会发生换行溢出。
    CGFloat finalTextWidth = bubbleWidth - inset * 2;
    NSRect finalBounds = [attributed boundingRectWithSize:NSMakeSize(finalTextWidth, 10000)
                                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    CGFloat finalTextHeight = ceil(finalBounds.size.height);
    CGFloat bubbleHeight = MIN(finalTextHeight + 20, maxBubbleHeight);
    CGFloat drawTextHeight = finalTextHeight;

    NSRect bubbleRect = NSMakeRect(
        NSMidX(self.bounds) - bubbleWidth / 2.0,
        MAX(3, MIN(NSMaxY(self.bounds) - bubbleHeight - 6, NSMaxY(petRect) + 10)),
        bubbleWidth,
        bubbleHeight
    );
    NSRect textRect = NSMakeRect(
        NSMinX(bubbleRect) + inset,
        NSMidY(bubbleRect) - drawTextHeight / 2.0,
        finalTextWidth,
        drawTextHeight
    );

    if (outAttributes) {
        *outAttributes = attrs;
    }
    if (outBubbleRect) {
        *outBubbleRect = bubbleRect;
    }
    if (outTextRect) {
        *outTextRect = textRect;
    }
}

// 台词气泡由 KimiGlassBubbleView 承载；measureSpeechBubbleForMessage 负责共用尺寸测量。


@end
