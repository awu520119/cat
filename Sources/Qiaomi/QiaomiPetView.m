#import "QiaomiPetView.h"
#import "KimiGlassBubble.h"
#include <stdlib.h>
#include <stdint.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

static BOOL QiaomiLooksLikeWhiteCutout(NSImage *image);
static NSImage *QiaomiImageByRemovingWhiteBackground(NSImage *image);
static BOOL QiaomiImageHasTransparency(NSImage *image);

// 私有前置声明：布局方法实现在绘制分类中。
@interface KimiPetView (LayoutForward)
- (NSRect)currentBodyRect;
- (CGFloat)idleOffset;
- (void)measureSpeechBubbleForMessage:(NSString *)message
                           attributes:(NSDictionary<NSAttributedStringKey, id> **)outAttributes
                           bubbleRect:(NSRect *)outBubbleRect
                            textRect:(NSRect *)outTextRect
                        abovePetRect:(NSRect)petRect;
@end

@interface KimiPetView ()
@property (nonatomic, strong, nullable) NSTimer *singleClickTimer;
@property (nonatomic, strong, nullable) NSTimer *messagePageTimer;
@property (nonatomic, copy) NSArray<NSString *> *messagePages;
@property (nonatomic) NSInteger messagePageIndex;
@property (nonatomic, copy) NSSet<NSString *> *builtInActionFileNames;
@property (nonatomic, strong) dispatch_queue_t mediaQueue;
// These dictionaries and the LRU order are only accessed on the main thread.
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *imageURLs;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *imageKeys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *imageCache;
@property (nonatomic, strong) NSMutableArray<NSString *> *imageCacheOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingImages;
@property (nonatomic, strong) NSMutableSet<NSString *> *failedImages;
@property (nonatomic) NSUInteger imageCacheCost;
@property (nonatomic) NSUInteger mediaGeneration;
@property (nonatomic) CFTimeInterval lastTickTime;
@property (nonatomic, copy) NSString *measuredMessage;
@property (nonatomic) NSSize measuredBounds;
@property (nonatomic) NSSize measuredBubbleSize;
@property (nonatomic) CGFloat measuredFontSize;
@property (nonatomic) BOOL restoredMedia;
@end

@implementation KimiPetView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _state = KimiStateIdle;
        _imageURLs = @{};
        _imageKeys = @{};
        _imageCache = [NSMutableDictionary dictionary];
        _imageCacheOrder = [NSMutableArray array];
        _pendingImages = [NSMutableSet set];
        _failedImages = [NSMutableSet set];
        _mediaQueue = dispatch_queue_create("com.qiaomi.media", DISPATCH_QUEUE_SERIAL);
        _videoURLs = [NSMutableDictionary dictionary];
        _mediaFiles = @[];
        _carouselFiles = @[];
        _statePools = @{};
        _statePoolIndexes = [NSMutableDictionary dictionary];
        _lastInteractionAt = [NSDate date];
        _nextNudgeAt = [[NSDate date] dateByAddingTimeInterval:18];
        _nextImageSwapAt = [[NSDate date] dateByAddingTimeInterval:10];
        _mousePassthroughEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"KimiMousePassthroughEnabled"];

        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        // 台词气泡。
        self.glassBubble = [[KimiGlassBubbleView alloc] initWithFrame:NSMakeRect(0, 0, 120, 44)];
        [self addSubview:self.glassBubble];

        [self loadMedia];
        [self setDisplayState:KimiStateIdle advanceImage:YES];

        BOOL wasSleeping = [NSUserDefaults.standardUserDefaults boolForKey:KimiWasSleepingDefaultsKey];
        if (wasSleeping) {
            _manualSleep = YES;
            [self setDisplayState:KimiStateSleeping advanceImage:YES];
            [self showMessage:@"喵" duration:2.2];
        }
        _petName = [NSUserDefaults.standardUserDefaults stringForKey:KimiPetNameDefaultsKey];
        if (_petName.length == 0) {
            _petName = @"俏咪";
        }
        NSInteger hour = [NSCalendar.currentCalendar component:NSCalendarUnitHour fromDate:[NSDate date]];
        [self showMessage:KimiPhraseForContext(KimiGreetingContextForHour(hour)) duration:2.8];

        [self startAnimationLoop];
    }
    return self;
}

// MARK: - 台词气泡（由 message 驱动）

- (void)setMessage:(NSString *)message {
    _message = [message copy];
    [self updateGlassBubbleIfNeeded];
}

- (void)updateGlassBubbleIfNeeded {
    KimiGlassBubbleView *bubble = self.glassBubble;
    if (!bubble) {
        return;
    }
    if (self.message.length == 0) {
        [bubble dismiss];
        self.lastBubbleRect = NSZeroRect;
        return;
    }

    // 与旧绘制版一致：用 bodyRect + 呼吸偏移定位，测量复用绘制分类的逻辑。
    NSRect bodyRect = [self currentBodyRect];
    NSRect petRect = NSOffsetRect(bodyRect, 0, [self idleOffset]);
    if (self.state == KimiStatePetting) {
        petRect = NSInsetRect(petRect, -2, -1);
    }

    if (![self.measuredMessage isEqualToString:self.message] || !NSEqualSizes(self.measuredBounds, self.bounds.size)) {
        NSRect measuredRect = NSZeroRect;
        NSDictionary<NSAttributedStringKey, id> *attrs = nil;
        [self measureSpeechBubbleForMessage:self.message attributes:&attrs bubbleRect:&measuredRect textRect:NULL abovePetRect:petRect];
        self.measuredMessage = self.message;
        self.measuredBounds = self.bounds.size;
        self.measuredBubbleSize = measuredRect.size;
        NSFont *font = attrs[NSFontAttributeName];
        self.measuredFontSize = font ? font.pointSize : 13.0;
    }
    NSSize size = self.measuredBubbleSize;
    NSRect bubbleRect = NSMakeRect(NSMidX(self.bounds) - size.width / 2.0,
        MAX(3, MIN(NSMaxY(self.bounds) - size.height - 6, NSMaxY(petRect) + 10)), size.width, size.height);
    if (NSIsEmptyRect(bubbleRect)) {
        [bubble dismiss];
        self.lastBubbleRect = NSZeroRect;
        return;
    }
    if (!NSEqualRects(bubble.frame, bubbleRect)) bubble.frame = bubbleRect;
    [bubble presentWithText:self.message fontSize:self.measuredFontSize];
    self.lastBubbleRect = bubbleRect;
}

- (void)dealloc {
    [self.timer invalidate];
    [self.singleClickTimer invalidate];
    [self.messagePageTimer invalidate];
    [self stopVideoPlayback];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }

    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect;
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

// Scan filenames and file versions only. Decoding happens when an image is requested.
- (void)loadMedia {
    NSUInteger generation = ++self.mediaGeneration;
    dispatch_async(self.mediaQueue, ^{
        @autoreleasepool {
            NSArray<NSURL *> *userURLs = [self mediaURLsInDirectory:QiaomiPhotosDirectoryURL()];
            NSURL *actionsURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"actions" isDirectory:YES];
            NSURL *photosURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"photos" isDirectory:YES];
            NSSet *images = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"tiff"]];
            NSSet *videos = [NSSet setWithArray:@[@"mp4", @"m4v", @"mov"]];
            NSMutableArray *supportedUser = [NSMutableArray array];
            for (NSURL *url in userURLs) {
                NSString *ext = url.pathExtension.lowercaseString;
                if ([images containsObject:ext] || [videos containsObject:ext]) [supportedUser addObject:url];
            }
            BOOL bundled = supportedUser.count == 0;
            NSArray *actionURLs = bundled ? [self mediaURLsInDirectory:actionsURL] : @[];
            NSArray *sourceURLs = bundled ? [actionURLs arrayByAddingObjectsFromArray:[self mediaURLsInDirectory:photosURL]] : supportedUser;
            NSMutableSet *actionNames = [NSMutableSet set];
            for (NSURL *url in actionURLs) {
                if ([url.pathExtension.lowercaseString isEqualToString:@"png"]) [actionNames addObject:url.lastPathComponent];
            }
            NSMutableDictionary *imageURLs = [NSMutableDictionary dictionary];
            NSMutableDictionary *imageKeys = [NSMutableDictionary dictionary];
            NSMutableDictionary *videoURLs = [NSMutableDictionary dictionary];
            NSMutableDictionary *renderKinds = [NSMutableDictionary dictionary];
            NSMutableOrderedSet *files = [NSMutableOrderedSet orderedSet];
            for (NSURL *url in sourceURLs) {
                NSString *ext = url.pathExtension.lowercaseString;
                NSString *name = url.lastPathComponent;
                if ([files containsObject:name]) continue;
                if ([videos containsObject:ext]) {
                    videoURLs[name] = url;
                    renderKinds[name] = @(KimiMediaRenderKindVideo);
                } else if ([images containsObject:ext]) {
                    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
                    if (!attrs) continue;
                    imageURLs[name] = url;
                    NSDate *modified = attrs[NSFileModificationDate];
                    imageKeys[name] = [NSString stringWithFormat:@"%@|%.9f|%@|%@|%d", url.path, modified.timeIntervalSince1970, attrs[NSFileSize], attrs[NSFileSystemFileNumber], bundled];
                    if ([actionNames containsObject:name]) renderKinds[name] = @(KimiMediaRenderKindAction);
                } else continue;
                [files addObject:name];
            }
            NSArray *mediaFiles = [files.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
            NSMutableArray *carousel = [NSMutableArray array];
            for (NSString *name in mediaFiles) if (![actionNames containsObject:name]) [carousel addObject:name];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.mediaGeneration) return;
                [self stopVideoPlayback];
                self.imageURLs = imageURLs;
                self.imageKeys = imageKeys;
                self.videoURLs = videoURLs;
                self.builtInActionFileNames = actionNames;
                self.mediaFiles = mediaFiles;
                self.carouselFiles = carousel;
                self.mediaRenderKinds = renderKinds;
                [self.failedImages removeAllObjects];
                NSSet *validKeys = [NSSet setWithArray:imageKeys.allValues];
                for (NSString *key in [self.imageCacheOrder copy]) {
                    if (![validKeys containsObject:key]) [self removeCachedImageForKey:key];
                }
                [self configureStatePools];
                [self buildActionFrames];
                NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:KimiCurrentMediaDefaultsKey];
                if (!self.restoredMedia && saved && (imageURLs[saved] || videoURLs[saved])) self.currentMediaFile = saved;
                self.restoredMedia = YES;
                if (!self.currentMediaFile || ![mediaFiles containsObject:self.currentMediaFile]) {
                    [self setDisplayState:self.state advanceImage:YES];
                } else if ([self isVideoFile:self.currentMediaFile] && !self.videoPlayer) {
                    [self startVideoPlaybackForFile:self.currentMediaFile];
                }
                [self prefetchCurrentMedia];
                self.needsDisplay = YES;
                [NSNotificationCenter.defaultCenter postNotificationName:@"QiaomiMediaDidLoad" object:self];
            });
        }
    });
}

- (void)removeCachedImageForKey:(NSString *)key {
    NSDictionary *entry = self.imageCache[key];
    if (!entry) return;
    self.imageCacheCost -= [entry[@"cost"] unsignedIntegerValue];
    [self.imageCache removeObjectForKey:key];
    [self.imageCacheOrder removeObject:key];
}

- (NSImage *)imageForFile:(NSString *)fileName {
    if (!fileName) return nil;
    NSString *key = self.imageKeys[fileName];
    NSURL *url = self.imageURLs[fileName];
    if (!key || !url) return nil;
    NSDictionary *entry = self.imageCache[key];
    if (entry) {
        [self.imageCacheOrder removeObject:key];
        [self.imageCacheOrder addObject:key];
        // The render classification is also cached; a new catalog starts with metadata only.
        if (!self.mediaRenderKinds[fileName]) {
            NSMutableDictionary *kinds = [self.mediaRenderKinds mutableCopy];
            kinds[fileName] = entry[@"kind"];
            self.mediaRenderKinds = kinds;
        }
        return entry[@"image"];
    }
    if ([self.pendingImages containsObject:key] || [self.failedImages containsObject:key]) return nil;
    [self.pendingImages addObject:key];
    NSUInteger generation = self.mediaGeneration;
    BOOL action = [self.builtInActionFileNames containsObject:fileName];
    BOOL removeWhite = ![url.path hasPrefix:[NSBundle.mainBundle.resourceURL.path stringByAppendingString:@"/"]];
    dispatch_async(self.mediaQueue, ^{
        @autoreleasepool {
            NSImage *image = nil;
            NSNumber *kind = nil;
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
            if (source) {
                NSDictionary *options = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                    (id)kCGImageSourceThumbnailMaxPixelSize: @1024,
                    (id)kCGImageSourceShouldCacheImmediately: @YES};
                CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
                if (thumbnail) {
                    image = [[NSImage alloc] initWithCGImage:thumbnail size:NSMakeSize(CGImageGetWidth(thumbnail), CGImageGetHeight(thumbnail))];
                    CGImageRelease(thumbnail);
                }
                CFRelease(source);
            }
            if (image) {
                BOOL white = !action && QiaomiLooksLikeWhiteCutout(image);
                BOOL transparent = !action && (QiaomiImageHasTransparency(image) || white);
                if (removeWhite && white) image = QiaomiImageByRemovingWhiteBackground(image);
                kind = @(action ? KimiMediaRenderKindAction : (transparent ? KimiMediaRenderKindTransparentCharacter : KimiMediaRenderKindPhoto));
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.pendingImages removeObject:key];
                if (generation != self.mediaGeneration) {
                    if ([self.imageKeys[fileName] isEqualToString:key]) [self imageForFile:fileName];
                    return;
                }
                if (![self.imageKeys[fileName] isEqualToString:key]) return;
                if (!image) {
                    [self.failedImages addObject:key];
                    NSMutableDictionary *urls = [self.imageURLs mutableCopy];
                    [urls removeObjectForKey:fileName];
                    self.imageURLs = urls;
                    NSMutableArray *files = [self.mediaFiles mutableCopy];
                    [files removeObject:fileName];
                    self.mediaFiles = files;
                    NSMutableArray *carousel = [self.carouselFiles mutableCopy];
                    [carousel removeObject:fileName];
                    self.carouselFiles = carousel;
                    [self configureStatePools];
                    [self buildActionFrames];
                    if ([self.currentMediaFile isEqualToString:fileName]) {
                        self.currentMediaFile = nil;
                        [self setDisplayState:self.state advanceImage:YES];
                    }
                    self.needsDisplay = YES;
                    [NSNotificationCenter.defaultCenter postNotificationName:@"QiaomiMediaDidLoad" object:self];
                    return;
                }
                NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * 4);
                const NSUInteger limit = 64 * 1024 * 1024;
                while (self.imageCacheOrder.count && self.imageCacheCost + cost > limit) {
                    [self removeCachedImageForKey:self.imageCacheOrder.firstObject];
                }
                if (cost <= limit) {
                    self.imageCache[key] = @{@"image": image, @"kind": kind, @"cost": @(cost)};
                    [self.imageCacheOrder addObject:key];
                    self.imageCacheCost += cost;
                }
                NSMutableDictionary *kinds = [self.mediaRenderKinds mutableCopy];
                kinds[fileName] = kind;
                self.mediaRenderKinds = kinds;
                self.needsDisplay = YES;
                [NSNotificationCenter.defaultCenter postNotificationName:@"QiaomiMediaDidLoad" object:self];
            });
        }
    });
    return nil;
}

- (void)prefetchCurrentMedia {
    [self imageForFile:self.currentMediaFile];
    NSUInteger index = [self.carouselFiles indexOfObject:self.currentMediaFile ?: @""];
    if (index != NSNotFound && self.carouselFiles.count > 1) {
        [self imageForFile:self.carouselFiles[(index + 1) % self.carouselFiles.count]];
    }
    if ([self isActionAssetFile:self.currentMediaFile]) {
        NSArray *frames = self.actionFramesByState[@(self.state)];
        for (NSUInteger i = 0; i < MIN(frames.count, 4); i++) [self imageForFile:frames[i]];
    }
}

static BOOL QiaomiLooksLikeWhiteCutout(NSImage *image) {
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cgImage = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!cgImage || CGImageGetWidth(cgImage) < 4 || CGImageGetHeight(cgImage) < 4) {
        return NO;
    }
    // Only a handful of samples are needed here. Rendering a full-resolution bitmap
    // just to inspect five points caused large, avoidable memory spikes on photos.
    const size_t sampleSize = 5;
    UInt8 pixels[sampleSize * sampleSize * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, sampleSize, sampleSize, 8,
                                                  sampleSize * 4, colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return NO;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, sampleSize, sampleSize), cgImage);
    NSUInteger whiteCorners = 0;
    const size_t corners[][2] = {{0, 0}, {sampleSize - 1, 0}, {0, sampleSize - 1}, {sampleSize - 1, sampleSize - 1}};
    for (NSUInteger i = 0; i < 4; i++) {
        const UInt8 *pixel = pixels + (corners[i][1] * sampleSize + corners[i][0]) * 4;
        UInt8 r = pixel[0], g = pixel[1], b = pixel[2], a = pixel[3];
        if (a > 245 && r > 230 && g > 230 && b > 230 && MAX(r, MAX(g, b)) - MIN(r, MIN(g, b)) < 18) {
            whiteCorners += 1;
        }
    }
    const UInt8 *centerPixel = pixels + (2 * sampleSize + 2) * 4;
    BOOL centerHasSubject = !(centerPixel[0] > 230 && centerPixel[1] > 230 && centerPixel[2] > 230);
    CGContextRelease(context);
    return whiteCorners >= 3 && centerHasSubject;
}

static NSImage *QiaomiImageByRemovingWhiteBackground(NSImage *image) {
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef source = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!source) {
        return image;
    }
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0 || width > SIZE_MAX / 4 || height > SIZE_MAX / width) {
        return image;
    }
    size_t pixelCount = width * height;
    // Flood fill needs a source bitmap, queue, and visited map. Keep pathological
    // image dimensions from turning a routine import into a multi-hundred-MB spike.
    if (pixelCount > 12 * 1024 * 1024 || pixelCount > UINT32_MAX) {
        return image;
    }
    size_t rowBytes = width * 4;
    if (height > SIZE_MAX / rowBytes) {
        return image;
    }
    NSMutableData *bitmapData = [NSMutableData dataWithLength:rowBytes * height];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bitmapData.mutableBytes, width, height, 8, rowBytes,
                                                   colorSpace,
                                                   kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return image;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    UInt8 *pixels = bitmapData.mutableBytes;
    UInt32 *queue = malloc(sizeof(UInt32) * pixelCount);
    if (!queue) {
        CGContextRelease(context);
        return image;
    }
    UInt8 *visited = calloc(pixelCount, sizeof(UInt8));
    if (!visited) {
        free(queue);
        CGContextRelease(context);
        return image;
    }
    size_t head = 0, tail = 0;
    for (size_t x = 0; x < width; x++) {
        queue[tail++] = (UInt32)x;
        visited[x] = YES;
        size_t bottom = (height - 1) * width + x;
        if (!visited[bottom]) {
            visited[bottom] = YES;
            queue[tail++] = (UInt32)bottom;
        }
    }
    for (size_t y = 1; y + 1 < height; y++) {
        size_t left = y * width;
        size_t right = y * width + (width - 1);
        if (!visited[left]) {
            visited[left] = YES;
            queue[tail++] = (UInt32)left;
        }
        if (!visited[right]) {
            visited[right] = YES;
            queue[tail++] = (UInt32)right;
        }
    }
    while (head < tail) {
        size_t index = queue[head++];
        UInt8 *pixel = pixels + index * 4;
        UInt8 r = pixel[0], g = pixel[1], b = pixel[2];
        BOOL nearWhite = r > 215 && g > 215 && b > 215 && MAX(r, MAX(g, b)) - MIN(r, MIN(g, b)) < 24;
        if (!nearWhite) {
            continue;
        }
        pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;
        size_t x = index % width;
        size_t y = index / width;
        if (x > 0 && !visited[index - 1]) {
            visited[index - 1] = YES;
            queue[tail++] = (UInt32)(index - 1);
        }
        if (x + 1 < width && !visited[index + 1]) {
            visited[index + 1] = YES;
            queue[tail++] = (UInt32)(index + 1);
        }
        if (y > 0 && !visited[index - width]) {
            visited[index - width] = YES;
            queue[tail++] = (UInt32)(index - width);
        }
        if (y + 1 < height && !visited[index + width]) {
            visited[index + width] = YES;
            queue[tail++] = (UInt32)(index + width);
        }
    }
    CGImageRef resultImage = CGBitmapContextCreateImage(context);
    NSImage *result = resultImage ? [[NSImage alloc] initWithCGImage:resultImage size:image.size] : image;
    if (resultImage) CGImageRelease(resultImage);
    free(visited);
    free(queue);
    CGContextRelease(context);
    return result;
}

static BOOL QiaomiImageHasTransparency(NSImage *image) {
    if (!image) {
        return NO;
    }
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef source = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!source) {
        return NO;
    }
    const size_t sampleSize = 16;
    UInt8 pixels[sampleSize * sampleSize * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, sampleSize, sampleSize, 8,
                                                   sampleSize * 4, colorSpace,
                                                   kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return NO;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, sampleSize, sampleSize), source);
    BOOL transparent = NO;
    for (size_t index = 3; index < sizeof(pixels); index += 4) {
        if (pixels[index] < 245) {
            transparent = YES;
            break;
        }
    }
    CGContextRelease(context);
    return transparent;
}

- (NSArray<NSURL *> *)mediaURLsInDirectory:(NSURL *)directory {
    if (!directory || ![NSFileManager.defaultManager fileExistsAtPath:directory.path]) {
        return @[];
    }
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
                                         includingPropertiesForKeys:nil
                                                            options:NSDirectoryEnumerationSkipsHiddenFiles
                                                              error:nil] ?: @[];
}

- (BOOL)isVideoFile:(NSString *)fileName {
    return self.videoURLs[fileName] != nil;
}

- (BOOL)isActionAssetFile:(NSString *)fileName {
    return [self mediaRenderKindForFile:fileName] == KimiMediaRenderKindAction;
}

- (KimiMediaRenderKind)mediaRenderKindForFile:(NSString *)fileName {
    NSNumber *kind = self.mediaRenderKinds[fileName];
    if (kind) {
        return (KimiMediaRenderKind)kind.integerValue;
    }
    // 兼容素材重载期间的短暂空窗：内置动作仍按动作素材处理。
    if ([fileName hasPrefix:KimiActionAssetPrefix] &&
        [fileName.pathExtension.lowercaseString isEqualToString:@"png"] &&
        [self.builtInActionFileNames containsObject:fileName]) {
        return KimiMediaRenderKindAction;
    }
    return [self isVideoFile:fileName] ? KimiMediaRenderKindVideo : KimiMediaRenderKindPhoto;
}

- (void)reloadMedia {
    [self.singleClickTimer invalidate];
    self.singleClickTimer = nil;
    [self loadMedia];
}

- (void)setCurrentMediaFile:(NSString *)currentMediaFile {
    if ([_currentMediaFile isEqualToString:currentMediaFile]) {
        if (currentMediaFile && [self isVideoFile:currentMediaFile] && !self.videoPlayer) {
            [self startVideoPlaybackForFile:currentMediaFile];
        }
        return;
    }

    [self stopVideoPlayback];
    _currentMediaFile = [currentMediaFile copy];

    if (currentMediaFile && [self isVideoFile:currentMediaFile]) {
        [self startVideoPlaybackForFile:currentMediaFile];
    } else {
        [self prefetchCurrentMedia];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context == &QiaomiVideoStatusContext && [object isKindOfClass:[AVPlayerItem class]]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusFailed) {
            // 旧 AVPlayerItem 的失败回调可能晚于素材切换到达，不能误删当前素材。
            dispatch_async(dispatch_get_main_queue(), ^{
                if (item == self.videoPlayer.currentItem) {
                    [self handleFailedVideoFile:self.currentMediaFile];
                }
            });
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)handleFailedVideoFile:(NSString *)fileName {
    if (!fileName) {
        return;
    }
    [self.videoURLs removeObjectForKey:fileName];
    [self configureStatePools];
    [self buildActionFrames];
    if ([self.currentMediaFile isEqualToString:fileName]) {
        [self stopVideoPlayback];
        [self setDisplayState:self.state advanceImage:YES];
    }
}

- (void)startVideoPlaybackForFile:(NSString *)fileName {
    NSURL *url = self.videoURLs[fileName];
    if (!url) {
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [item addObserver:self forKeyPath:@"status" options:0 context:&QiaomiVideoStatusContext];
    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    player.muted = YES;
    player.volume = 0.0;
    self.videoPlayer = player;
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.masksToBounds = YES;
    layer.hidden = YES;
    self.videoLayer = layer;
    [self.layer insertSublayer:layer atIndex:0];

    __weak typeof(self) weakSelf = self;
    self.videoEndObserver = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                                object:item
                                                                                 queue:NSOperationQueue.mainQueue
                                                                            usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.videoPlayer.currentItem != note.object) {
            return;
        }

        [self.videoPlayer seekToTime:kCMTimeZero
                    toleranceBefore:kCMTimeZero
                     toleranceAfter:kCMTimeZero
                  completionHandler:^(BOOL finished) {
            if (finished && !self.isHidden && self.videoPlayer.currentItem == item && self.currentMediaFile && [self isVideoFile:self.currentMediaFile]) {
                [self.videoPlayer play];
            }
        }];
    }];

    if (!self.isHidden) [player play];
}

- (void)stopVideoPlayback {
    if (self.videoEndObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.videoEndObserver];
        self.videoEndObserver = nil;
    }

    AVPlayerItem *item = self.videoPlayer.currentItem;
    if (item) {
        [item removeObserver:self forKeyPath:@"status" context:&QiaomiVideoStatusContext];
    }
    [self.videoPlayer pause];
    self.videoPlayer = nil;
    [self.videoLayer removeFromSuperlayer];
    self.videoLayer = nil;
}


- (void)configureStatePools {
    // app 内置动作素材仅在用户素材库为空时启用；用户库有内容时，所有状态共用用户库。
    self.statePools = @{
        @(KimiStateIdle): [self existingFilesFromPreferred:@[@"qiaomi-action-idle.png"]],
        @(KimiStateBored): [self existingFilesFromPreferred:@[@"qiaomi-action-bored.png"]],
        @(KimiStatePetting): [self existingFilesFromPreferred:@[@"qiaomi-action-petting.png"]],
        @(KimiStateKissing): [self existingFilesFromPreferred:@[@"qiaomi-action-kissing.png"]],
        @(KimiStateTreating): [self existingFilesFromPreferred:@[@"qiaomi-action-treating.png"]],
        @(KimiStatePlaying): [self existingFilesFromPreferred:@[@"qiaomi-action-playing.png"]],
        @(KimiStateGrooming): [self existingFilesFromPreferred:@[@"qiaomi-action-grooming.png"]],
        @(KimiStateShowingOff): [self existingFilesFromPreferred:@[@"qiaomi-action-showing-off.png"]],
        @(KimiStatePickedUp): [self existingFilesFromPreferred:@[@"qiaomi-action-picked-up.png"]],
        @(KimiStateSleeping): [self existingFilesFromPreferred:@[@"qiaomi-action-sleeping.png"]],
        @(KimiStateNuzzling): [self existingFilesFromPreferred:@[@"qiaomi-action-petting.png"]]
    };
}

- (NSArray<NSString *> *)existingFilesFromPreferred:(NSArray<NSString *> *)preferred {
    NSMutableArray<NSString *> *existing = [NSMutableArray array];
    for (NSString *file in preferred) {
        if (self.imageURLs[file] || self.videoURLs[file]) {
            [existing addObject:file];
        }
    }

    // 有状态专属素材时只使用专属素材；没有时才回退到当前素材库轮播池。
    // 这样用户导入 3 张图后，不会在某个状态里混入其它状态/旧素材。
    return existing.count > 0 ? existing : self.carouselFiles;
}

#pragma mark - Action frame animation

- (NSString *)actionPrefixForState:(KimiState)state {
    switch (state) {
        case KimiStateIdle: return @"qiaomi-action-idle-";
        case KimiStateBored: return @"qiaomi-action-bored-";
        case KimiStatePetting: return @"qiaomi-action-petting-";
        case KimiStateKissing: return @"qiaomi-action-kissing-";
        case KimiStateTreating: return @"qiaomi-action-treating-";
        case KimiStatePlaying: return @"qiaomi-action-playing-";
        case KimiStateGrooming: return @"qiaomi-action-grooming-";
        case KimiStateShowingOff: return @"qiaomi-action-showing-off-";
        case KimiStatePickedUp: return @"qiaomi-action-picked-up-";
        case KimiStateSleeping: return @"qiaomi-action-sleeping-";
        case KimiStateNuzzling: return @"qiaomi-action-nuzzling-";
    }
}

- (CGFloat)actionFrameFPSForState:(KimiState)state {
    switch (state) {
        case KimiStateIdle: return 4.0;
        case KimiStateBored: return 4.0;
        case KimiStateSleeping: return 3.0;
        default: return 6.0;
    }
}

- (void)buildActionFrames {
    NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    NSArray<NSNumber *> *states = @[
        @(KimiStateIdle), @(KimiStateBored), @(KimiStatePetting), @(KimiStateKissing),
        @(KimiStateTreating), @(KimiStatePlaying), @(KimiStateGrooming), @(KimiStateShowingOff),
        @(KimiStatePickedUp), @(KimiStateSleeping), @(KimiStateNuzzling)
    ];

    for (NSNumber *stateValue in states) {
        NSString *prefix = [self actionPrefixForState:stateValue.integerValue];
        NSMutableDictionary<NSNumber *, NSString *> *byIndex = [NSMutableDictionary dictionary];
        for (NSString *file in self.mediaFiles) {
            if (![file hasPrefix:prefix] || ![self isActionAssetFile:file]) {
                continue;
            }
            NSString *suffix = [file substringFromIndex:prefix.length];
            suffix = [suffix stringByDeletingPathExtension];
            NSInteger number = suffix.integerValue;
            if (number >= 0) {
                byIndex[@(number)] = file;
            }
        }
        if (byIndex.count > 0) {
            NSArray<NSNumber *> *sorted = [byIndex.allKeys sortedArrayUsingSelector:@selector(compare:)];
            NSMutableArray<NSString *> *frames = [NSMutableArray array];
            for (NSNumber *number in sorted) {
                [frames addObject:byIndex[number]];
            }
            result[stateValue] = frames;
        }
    }
    self.actionFramesByState = result;
}

- (NSString *)currentActionFrameFileForState:(KimiState)state {
    NSArray<NSString *> *frames = self.actionFramesByState[@(state)];
    if (frames.count < 2) {
        return nil;
    }
    CGFloat fps = [self actionFrameFPSForState:state];
    NSInteger index = ((NSInteger)(self.animationTime * fps)) % frames.count;
    return frames[index];
}

- (void)startAnimationLoop {
    self.timer = [NSTimer timerWithTimeInterval:KimiTimerInterval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)timer {
    CFTimeInterval time = CACurrentMediaTime();
    NSTimeInterval elapsed = self.lastTickTime > 0 ? MIN(MAX(time - self.lastTickTime, 0), 0.25) : KimiTimerInterval;
    self.lastTickTime = time;
    self.animationTime += elapsed;
    NSDate *now = [NSDate date];

    if (self.transientStateUntil && [now compare:self.transientStateUntil] != NSOrderedAscending) {
        self.transientStateUntil = nil;
        [self setDisplayState:KimiStateIdle advanceImage:YES];
    }

    if (self.messageUntil && [now compare:self.messageUntil] != NSOrderedAscending) {
        // 鼠标悬停在气泡上时续读：只要用户还在看，气泡就不消失。
        BOOL keepForReading = NO;
        if (self.message && self.isMouseInside && self.window && !NSIsEmptyRect(self.lastBubbleRect)) {
            NSPoint point = [self convertPoint:[self.window mouseLocationOutsideOfEventStream] fromView:nil];
            keepForReading = NSPointInRect(point, self.lastBubbleRect);
        }
        if (keepForReading) {
            self.messageUntil = [now dateByAddingTimeInterval:1.6];
        } else {
            [self.messagePageTimer invalidate];
            self.messagePageTimer = nil;
            self.messagePages = @[];
            self.messagePageIndex = 0;
            self.message = nil;
            self.messageUntil = nil;
            [self updateHoverToolTip];
        }
    }

    [self applyPassiveBehaviorWithDate:now];
    [self maybeSwapPassiveImageAtDate:now];

    // 静态状态以 15fps 更新，互动、气泡和视频位置以 30fps 更新。
    self.renderAccumulator += elapsed;
    BOOL highFrequency = (self.transientStateUntil != nil || self.messageUntil != nil || self.videoPlayer != nil);
    NSTimeInterval renderInterval = highFrequency ? KimiTimerInterval : (1.0 / 15.0);
    if (self.renderAccumulator >= renderInterval - 0.0005) {
        self.renderAccumulator = 0;
        self.needsDisplay = YES;
    }

    // 台词气泡跟随猫的呼吸浮动微调位置。
    if (self.message.length > 0 && !self.glassBubble.hidden) {
        [self updateGlassBubbleIfNeeded];
    }

    // 弹簧形变积分：二阶阻尼弹簧，向 0 收敛。
    {
        CGFloat dt = MIN(elapsed, 1.0 / 30.0);
        CGFloat stiffness = 90.0;
        CGFloat damping = 9.0;
        self.squashVelocity += (-stiffness * self.squashValue - damping * self.squashVelocity) * dt;
        self.squashValue += self.squashVelocity * dt;
        if (fabs(self.squashValue) < 0.002 && fabs(self.squashVelocity) < 0.01) {
            self.squashValue = 0.0;
            self.squashVelocity = 0.0;
        }
    }
}

- (void)addSquashImpulse:(CGFloat)impulse {
    self.squashVelocity += impulse;
}

- (void)applyPassiveBehaviorWithDate:(NSDate *)now {
    if (self.transientStateUntil || self.isHidden || self.manualSleep) {
        return;
    }

    NSTimeInterval idleSeconds = [now timeIntervalSinceDate:self.lastInteractionAt];
    KimiNudgeLevel nudgeLevel = KimiSavedNudgeLevel();

    if (idleSeconds > KimiSleepThresholdForLevel(nudgeLevel)) {
        if (self.state != KimiStateSleeping) {
            [self setDisplayState:KimiStateSleeping advanceImage:YES];
            [self showMessage:@"喵" duration:2.2];
        }
        return;
    }

    if (idleSeconds > KimiBoredThresholdForLevel(nudgeLevel)) {
        if (self.state != KimiStateBored) {
            [self setDisplayState:KimiStateBored advanceImage:YES];
            [self showMessage:KimiPhraseForContext(@"bored") duration:3.4];
            self.nextNudgeAt = [now dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
        } else if ([now compare:self.nextNudgeAt] != NSOrderedAscending) {
            [self showMessage:KimiPhraseForContext(@"bored") duration:3.0];
            self.nextNudgeAt = [now dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
        }
        return;
    }

    if (self.state == KimiStateBored || self.state == KimiStateSleeping) {
        [self setDisplayState:KimiStateIdle advanceImage:YES];
    }

    if ([now compare:self.nextNudgeAt] != NSOrderedAscending) {
        // 空闲时按设置的概率穿插展示励志语录，其余时候说普通闲话。
        if (KimiQuoteEnabled() && (double)arc4random_uniform(1000) / 1000.0 < KimiQuoteChanceForLevel(KimiSavedQuoteLevel())) {
            [self showQuote:KimiPhraseForContext(@"quote")];
        } else {
            [self showMessage:KimiPhraseForContext(@"idle") duration:2.8];
        }
        self.nextNudgeAt = [now dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
    }
}

- (void)maybeSwapPassiveImageAtDate:(NSDate *)now {
    if (self.isHidden || self.transientStateUntil || [now compare:self.nextImageSwapAt] == NSOrderedAscending) {
        return;
    }

    if (self.state == KimiStateIdle || self.state == KimiStateBored || self.state == KimiStateSleeping) {
        self.currentMediaFile = [self nextImageFileForState:self.state];
    }

    self.nextImageSwapAt = [now dateByAddingTimeInterval:KimiRandomInterval(9, 16)];
}

- (void)setDisplayState:(KimiState)newState advanceImage:(BOOL)advanceImage {
    self.state = newState;

    BOOL currentIsUserMedia = self.currentMediaFile.length > 0 && ![self isActionAssetFile:self.currentMediaFile];
    if ((advanceImage && !currentIsUserMedia) || !self.currentMediaFile ||
        (!self.imageURLs[self.currentMediaFile] && !self.videoURLs[self.currentMediaFile])) {
        self.currentMediaFile = [self nextImageFileForState:newState];
        self.nextImageSwapAt = [[NSDate date] dateByAddingTimeInterval:KimiRandomInterval(9, 16)];
    }
    [self prefetchCurrentMedia];
}

- (NSString *)nextImageFileForState:(KimiState)state {
    NSArray<NSString *> *pool = self.statePools[@(state)];
    if (pool.count == 0) {
        pool = self.carouselFiles;
    }
    if (pool.count == 0) {
        return nil;
    }

    NSNumber *key = @(state);
    NSInteger currentIndex = self.statePoolIndexes[key] ? self.statePoolIndexes[key].integerValue : -1;
    NSInteger nextIndex = (currentIndex + 1) % pool.count;
    self.statePoolIndexes[key] = @(nextIndex);
    return pool[nextIndex];
}

- (void)setTransientState:(KimiState)newState duration:(NSTimeInterval)duration phrase:(NSString *)phrase {
    // 连续点击合并为同一条互动序列，旧特效/HUD 回调不再与新状态竞争。
    // 用户素材是用户当前选择的“角色”，互动期间保持它不变；只有内置动作素材才切换到对应状态帧。
    BOOL isUserMedia = self.currentMediaFile.length > 0 && ![self isActionAssetFile:self.currentMediaFile];
    self.manualSleep = NO;
    [self setDisplayState:newState advanceImage:!isUserMedia];
    self.transientStateUntil = [[NSDate date] dateByAddingTimeInterval:duration];
    self.lastInteractionAt = [NSDate date];
    KimiNudgeLevel nudgeLevel = KimiSavedNudgeLevel();
    self.nextNudgeAt = [[NSDate date] dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
    [self showMessage:phrase duration:MIN(duration, 3.2)];
}

- (void)performPendingSingleClick {
    self.singleClickTimer = nil;
    if (!self.isHidden) [self triggerPetting];
}

- (void)showMessage:(NSString *)text duration:(NSTimeInterval)duration {
    [self.messagePageTimer invalidate];
    self.messagePageTimer = nil;
    self.messagePages = [self messagePagesForText:text];
    self.messagePageIndex = 0;
    self.message = self.messagePages.firstObject ?: text;
    // 展示时长按真实文本行数计算（按当前窗口宽度与字号测量），保证整句能读完。
    NSTimeInterval readingTime = [self totalReadingTimeForPages];
    self.messageUntil = [[NSDate date] dateByAddingTimeInterval:MAX(duration, readingTime + (self.messagePages.count > 1 ? 0.6 : 0.0))];
    [self updateGlassBubbleIfNeeded];
    [self updateHoverToolTip];
    [self scheduleNextMessagePageIfNeeded];
}

- (NSTimeInterval)readingTimeForMessage:(NSString *)text {
    if (text.length == 0) {
        return 2.0;
    }
    CGFloat fontSize = KimiClamp(self.bounds.size.width * 0.060, 12.0, 14.5);
    CGFloat availableWidth = MAX(80, self.bounds.size.width - 56);
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByCharWrapping;
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSParagraphStyleAttributeName: paragraph
    }];
    NSRect bounds = [attributed boundingRectWithSize:NSMakeSize(availableWidth, 10000)
                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    NSUInteger lines = MAX(1, (NSUInteger)ceil(bounds.size.height / MAX(8.0, fontSize * 1.25)));
    // 首行 2.4s，每多一行 +1.6s，上限 14s（语录最长可到 12s 以上）。
    return MIN(2.4 + (double)(lines - 1) * 1.6, 14.0);
}

- (void)showQuote:(NSString *)text {
    [self.messagePageTimer invalidate];
    self.messagePageTimer = nil;
    self.messagePages = [self messagePagesForText:text];
    self.messagePageIndex = 0;
    self.message = self.messagePages.firstObject ?: text;
    NSTimeInterval readingTime = [self totalReadingTimeForPages];
    self.messageUntil = [[NSDate date] dateByAddingTimeInterval:MAX(3.2, readingTime + (self.messagePages.count > 1 ? 0.6 : 0.0))];
    [self updateGlassBubbleIfNeeded];
    [self updateHoverToolTip];
    [self scheduleNextMessagePageIfNeeded];
}

- (NSTimeInterval)totalReadingTimeForPages {
    NSTimeInterval total = 0;
    for (NSString *page in self.messagePages) {
        total += [self readingTimeForMessage:page] + 0.25;
    }
    return MAX(2.0, total);
}

- (NSArray<NSString *> *)messagePagesForText:(NSString *)text {
    if (text.length == 0) return @[];
    CGFloat maxWidth = MAX(120, self.bounds.size.width - 16);
    CGFloat inset = 17.0;
    CGFloat maxHeight = MAX(60, self.bounds.size.height - 30) - 14;
    CGFloat fontSize = KimiClamp(self.bounds.size.width * 0.060, 11.0, 14.5);
    NSDictionary *attrs = [self messageTextAttributesForPageFontSize:fontSize];
    NSMutableArray<NSString *> *pages = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        [current appendString:substring];
        NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:current attributes:attrs];
        NSRect bounds = [attributed boundingRectWithSize:NSMakeSize(maxWidth - inset * 2, CGFLOAT_MAX)
                                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
        if (bounds.size.height > maxHeight && current.length > substring.length) {
            NSString *page = [current substringToIndex:current.length - substring.length];
            [pages addObject:page];
            [current setString:substring];
        }
    }];
    if (current.length > 0) [pages addObject:current.copy];
    return pages.count > 0 ? pages : @[text];
}

- (NSDictionary<NSAttributedStringKey, id> *)messageTextAttributesForPageFontSize:(CGFloat)fontSize {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByCharWrapping;
    paragraph.lineSpacing = 1.0;
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSParagraphStyleAttributeName: paragraph
    };
}

- (void)scheduleNextMessagePageIfNeeded {
    if (self.messagePageIndex + 1 >= (NSInteger)self.messagePages.count) return;
    NSTimeInterval delay = [self readingTimeForMessage:self.message] + 0.25;
    __weak typeof(self) weakSelf = self;
    self.messagePageTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.messagePageIndex + 1 >= (NSInteger)strongSelf.messagePages.count) return;
        strongSelf.messagePageIndex += 1;
        strongSelf.message = strongSelf.messagePages[strongSelf.messagePageIndex];
        NSTimeInterval pageTime = [strongSelf readingTimeForMessage:strongSelf.message];
        strongSelf.messageUntil = [[NSDate date] dateByAddingTimeInterval:pageTime + 0.3];
        [strongSelf updateGlassBubbleIfNeeded];
        [strongSelf updateHoverToolTip];
        [strongSelf scheduleNextMessagePageIfNeeded];
    }];
}

- (void)triggerQuote {
    self.lastInteractionAt = [NSDate date];
    self.manualSleep = NO;
    BOOL isUserMedia = self.currentMediaFile.length > 0 && ![self isActionAssetFile:self.currentMediaFile];
    if (self.state == KimiStateSleeping) {
        // 打气前先叫醒
        [self setDisplayState:KimiStateIdle advanceImage:!isUserMedia];
    }
    [self setDisplayState:KimiStateShowingOff advanceImage:!isUserMedia];
    self.transientStateUntil = [[NSDate date] dateByAddingTimeInterval:2.6];
    KimiNudgeLevel nudgeLevel = KimiSavedNudgeLevel();
    self.nextNudgeAt = [[NSDate date] dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
    [self showQuote:KimiPhraseForContext(@"quote")];
    KimiPlaySound(@"posing");
    self.needsDisplay = YES;
}

- (void)saveWindowState {
    NSWindow *window = self.window;
    if (!window) {
        return;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:window.frame.origin.x forKey:KimiWindowOriginXDefaultsKey];
    [defaults setDouble:window.frame.origin.y forKey:KimiWindowOriginYDefaultsKey];
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    if (screenNumber) {
        [defaults setInteger:screenNumber.integerValue forKey:KimiWindowScreenDefaultsKey];
    }
    [defaults setBool:self.state == KimiStateSleeping forKey:KimiWasSleepingDefaultsKey];
    if (self.currentMediaFile) {
        [defaults setObject:self.currentMediaFile forKey:KimiCurrentMediaDefaultsKey];
    }
}

#pragma mark - Visibility

- (void)hidePet {
    if (self.isHidden || !self.window) return;
    [self saveWindowState];
    self.isHidden = YES;
    self.message = nil;
    self.messageUntil = nil;
    [self.messagePageTimer invalidate];
    self.messagePageTimer = nil;
    [self.glassBubble dismiss];
    [self.videoPlayer pause];
    [self.timer invalidate];
    self.timer = nil;
    self.lastTickTime = 0;
    [self.window orderOut:nil];
}

- (void)showPet {
    if (!self.isHidden || !self.window) return;
    self.isHidden = NO;
    [self startAnimationLoop];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self];
    if (self.currentMediaFile && [self isVideoFile:self.currentMediaFile]) [self.videoPlayer play];
}

- (void)setMousePassthroughEnabled:(BOOL)mousePassthroughEnabled {
    _mousePassthroughEnabled = mousePassthroughEnabled;
    [NSUserDefaults.standardUserDefaults setBool:mousePassthroughEnabled forKey:@"KimiMousePassthroughEnabled"];
    self.window.ignoresMouseEvents = mousePassthroughEnabled;
    if (mousePassthroughEnabled) {
        self.isMouseInside = NO;
        [self updateHoverToolTip];
    }
    self.needsDisplay = YES;
}

- (void)toggleMousePassthrough {
    self.mousePassthroughEnabled = !self.mousePassthroughEnabled;
}

- (void)triggerPetting {
    [self setTransientState:KimiStatePetting duration:3.0 phrase:KimiPhraseForContext(@"petting")];
    KimiPlaySound(@"petting");
    [self recordInteractionForKey:@"petting"];
    [self addSquashImpulse:0.55];
}

- (void)triggerKissing {
    [self setTransientState:KimiStateKissing duration:3.2 phrase:KimiPhraseForContext(@"kissing")];
    KimiPlaySound(@"kissing");
    [self recordInteractionForKey:@"kissing"];
    [self addSquashImpulse:0.75];
}

- (void)triggerTreating {
    [self setTransientState:KimiStateTreating duration:3.5 phrase:KimiPhraseForContext(@"treating")];
    KimiPlaySound(@"treating");
    [self recordInteractionForKey:@"treating"];
    [self addSquashImpulse:0.60];
}

- (void)triggerPlaying {
    [self setTransientState:KimiStatePlaying duration:3.4 phrase:KimiPhraseForContext(@"playing")];
    KimiPlaySound(@"playing");
    [self recordInteractionForKey:@"playing"];
    [self addSquashImpulse:0.50];
}

- (void)triggerGrooming {
    [self setTransientState:KimiStateGrooming duration:3.2 phrase:KimiPhraseForContext(@"grooming")];
    KimiPlaySound(@"grooming");
    [self recordInteractionForKey:@"grooming"];
    [self addSquashImpulse:0.45];
}

- (void)triggerShowingOff {
    [self setTransientState:KimiStateShowingOff duration:2.8 phrase:KimiPhraseForContext(@"posing")];
    KimiPlaySound(@"posing");
    [self recordInteractionForKey:@"showingoff"];
    [self addSquashImpulse:0.40];
}

- (void)triggerNuzzling {
    [self setTransientState:KimiStateNuzzling duration:3.0 phrase:KimiPhraseForContext(@"nuzzling")];
    KimiPlaySound(@"petting");
    [self recordInteractionForKey:@"nuzzling"];
    [self addSquashImpulse:0.50];
}

- (void)triggerPickedUp {
    [self setDisplayState:KimiStatePickedUp advanceImage:!self.didDragWindow];
    self.transientStateUntil = nil;
    self.lastInteractionAt = [NSDate date];
    if (!self.message) {
        [self showMessage:@"喵" duration:1.6];
    }
    KimiPlaySound(@"pickedUp");
}

- (void)releasePickedUp {
    [self setTransientState:KimiStateIdle duration:1.2 phrase:KimiPhraseForContext(@"released")];
    // 落地：较大的压扁冲量 + 回弹。
    [self addSquashImpulse:1.30];
}

- (void)toggleSleep {
    self.lastInteractionAt = [NSDate date];
    self.transientStateUntil = nil;
    BOOL isUserMedia = self.currentMediaFile.length > 0 && ![self isActionAssetFile:self.currentMediaFile];

    if (self.state == KimiStateSleeping) {
        self.manualSleep = NO;
        [self setDisplayState:KimiStateIdle advanceImage:!isUserMedia];
        [self showMessage:KimiPhraseForContext(@"wake") duration:2.8];
        KimiPlaySound(@"waking");
    } else {
        self.manualSleep = YES;
        [self setDisplayState:KimiStateSleeping advanceImage:!isUserMedia];
        [self showMessage:@"喵" duration:2.2];
        KimiPlaySound(@"sleeping");
    }
}

- (void)resizeByDelta:(CGFloat)delta {
    [self resizeToScale:KimiSavedScale() + delta showHint:YES];
}

- (void)resetSize {
    [self resizeToScale:KimiDefaultScale showHint:YES];
}

- (void)resizeToScale:(CGFloat)scale showHint:(BOOL)showHint {
    if (self.isHidden || !self.window) {
        return;
    }

    CGFloat clamped = KimiClamp(scale, KimiMinScale, KimiMaxScale);
    NSSize newSize = KimiSizeForScale(clamped);
    NSRect oldFrame = self.window.frame;
    NSRect newFrame = NSMakeRect(
        NSMidX(oldFrame) - newSize.width / 2,
        NSMinY(oldFrame),
        newSize.width,
        newSize.height
    );

    NSRect visibleFrame = self.window.screen ? self.window.screen.visibleFrame : NSScreen.mainScreen.visibleFrame;
    if (NSMaxX(newFrame) > NSMaxX(visibleFrame)) {
        newFrame.origin.x = NSMaxX(visibleFrame) - newFrame.size.width;
    }
    if (NSMinX(newFrame) < NSMinX(visibleFrame)) {
        newFrame.origin.x = NSMinX(visibleFrame);
    }
    if (NSMaxY(newFrame) > NSMaxY(visibleFrame)) {
        newFrame.origin.y = NSMaxY(visibleFrame) - newFrame.size.height;
    }
    if (NSMinY(newFrame) < NSMinY(visibleFrame)) {
        newFrame.origin.y = NSMinY(visibleFrame);
    }

    [NSUserDefaults.standardUserDefaults setDouble:clamped forKey:KimiScaleDefaultsKey];
    [self.window setFrame:newFrame display:YES animate:YES];
    [self saveWindowState];

    if (showHint) {
        NSInteger percent = (NSInteger)round(clamped * 100);
        [self showMessage:[NSString stringWithFormat:@"%ld%%", (long)percent] duration:1.4];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyWindow];
    self.isMouseInside = YES;
    self.lastDragScreenPoint = [self eventScreenPoint:event];
    self.hasLastDragScreenPoint = YES;
    self.didDragWindow = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.isHidden || !self.window || !self.hasLastDragScreenPoint) return;
    NSPoint point = [self eventScreenPoint:event];
    CGFloat dx = point.x - self.lastDragScreenPoint.x;
    CGFloat dy = point.y - self.lastDragScreenPoint.y;
    if (hypot(dx, dy) > 0.5) {
        if (!self.didDragWindow) {
            self.didDragWindow = YES;
            [self triggerPickedUp];
        }
        NSRect frame = self.window.frame;
        frame.origin.x += dx;
        frame.origin.y += dy;
        [self.window setFrame:frame display:YES];
    }
    self.lastDragScreenPoint = point;
}

- (void)mouseUp:(NSEvent *)event {
    BOOL didDrag = self.didDragWindow;
    self.hasLastDragScreenPoint = NO;
    self.didDragWindow = NO;
    if (didDrag) {
        [self releasePickedUp];
        [self saveWindowState];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.message && NSPointInRect(point, self.lastBubbleRect)) {
        self.messageUntil = [[NSDate date] dateByAddingTimeInterval:3.0];
        return;
    }
    if (event.clickCount >= 2) {
        [self.singleClickTimer invalidate];
        self.singleClickTimer = nil;
        [self toggleSleep];
        return;
    }
    [self.singleClickTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.singleClickTimer = [NSTimer scheduledTimerWithTimeInterval:0.18 repeats:NO block:^(NSTimer *timer) {
        [weakSelf performPendingSingleClick];
    }];
}

- (void)mouseEntered:(NSEvent *)event {
    self.isMouseInside = YES;
    [self updateHoverToolTip];
}

- (void)mouseMoved:(NSEvent *)event {
    self.isMouseInside = YES;
}

- (void)mouseExited:(NSEvent *)event {
    self.isMouseInside = NO;
    [self updateHoverToolTip];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (fabs(event.magnification) < 0.01) {
        return;
    }
    [self resizeToScale:KimiSavedScale() + event.magnification * 0.55 showHint:YES];
}

- (void)rightMouseDown:(NSEvent *)event {
    [NSMenu popUpContextMenu:[self contextMenu] withEvent:event forView:self];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self contextMenu];
}

- (NSMenu *)contextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:self.petName];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:[self intimacyMenuTitle] action:nil keyEquivalent:@""]];

    NSMenu *actions = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"menu.actions", @"")];
    NSArray<NSDictionary *> *choices = @[
        @{@"title": [NSString stringWithFormat:NSLocalizedString(@"menu.kiss.fmt", @""), self.petName], @"action": NSStringFromSelector(@selector(menuKiss:))},
        @{@"title": NSLocalizedString(@"menu.treat", @""), @"action": NSStringFromSelector(@selector(menuTreat:))},
        @{@"title": [NSString stringWithFormat:NSLocalizedString(@"menu.play.fmt", @""), self.petName], @"action": NSStringFromSelector(@selector(menuPlay:))},
        @{@"title": NSLocalizedString(@"menu.groom", @""), @"action": NSStringFromSelector(@selector(menuGroom:))},
        @{@"title": [NSString stringWithFormat:NSLocalizedString(@"menu.nuzzle.fmt", @""), self.petName], @"action": NSStringFromSelector(@selector(menuNuzzle:))},
        @{@"title": NSLocalizedString(@"menu.pose", @""), @"action": NSStringFromSelector(@selector(menuPose:))}
    ];
    for (NSDictionary *choice in choices) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[@"title"] action:NSSelectorFromString(choice[@"action"]) keyEquivalent:@""];
        item.target = self;
        [actions addItem:item];
    }
    NSMenuItem *actionsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.actions", @"") action:nil keyEquivalent:@""];
    actionsItem.submenu = actions;
    [menu addItem:actionsItem];

    NSMenuItem *quote = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.quote", @"") action:@selector(menuQuote:) keyEquivalent:@""];
    quote.target = self;
    [menu addItem:quote];
    NSString *sleepTitle = self.state == KimiStateSleeping
        ? [NSString stringWithFormat:NSLocalizedString(@"menu.wake.fmt", @""), self.petName]
        : [NSString stringWithFormat:NSLocalizedString(@"menu.sleep.fmt", @""), self.petName];
    NSMenuItem *sleep = [[NSMenuItem alloc] initWithTitle:sleepTitle action:@selector(menuSleep:) keyEquivalent:@""];
    sleep.target = self;
    [menu addItem:sleep];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.hide.self", @"") action:@selector(menuToggleHidden:) keyEquivalent:@""];
    hide.target = self;
    [menu addItem:hide];
    NSMenuItem *passthrough = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.mousePassthrough", @"") action:@selector(menuToggleMousePassthrough:) keyEquivalent:@""];
    passthrough.target = self;
    passthrough.state = self.mousePassthroughEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:passthrough];
    NSMenuItem *assets = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.assets", @"") action:@selector(menuShowAssets:) keyEquivalent:@""];
    assets.target = self;
    [menu addItem:assets];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.settings", @"") action:@selector(menuShowSettings:) keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];

    NSMenu *size = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"menu.size", @"")];
    NSArray<NSDictionary *> *sizes = @[
        @{@"title": NSLocalizedString(@"menu.smaller", @""), @"action": NSStringFromSelector(@selector(menuSmaller:))},
        @{@"title": NSLocalizedString(@"menu.larger", @""), @"action": NSStringFromSelector(@selector(menuLarger:))},
        @{@"title": NSLocalizedString(@"menu.resetSize", @""), @"action": NSStringFromSelector(@selector(menuResetSize:))}
    ];
    for (NSDictionary *choice in sizes) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[@"title"] action:NSSelectorFromString(choice[@"action"]) keyEquivalent:@""];
        item.target = self;
        [size addItem:item];
    }
    NSMenuItem *sizeItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.size", @"") action:nil keyEquivalent:@""];
    sizeItem.submenu = size;
    [menu addItem:sizeItem];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.quit.short", @"") action:@selector(menuQuit:) keyEquivalent:@""];
    quit.target = self;
    [menu addItem:quit];
    return menu;
}

- (void)menuKiss:(id)sender {
    [self triggerKissing];
}

- (void)menuTreat:(id)sender {
    [self triggerTreating];
}

- (void)menuPlay:(id)sender {
    [self triggerPlaying];
}

- (void)menuGroom:(id)sender {
    [self triggerGrooming];
}

- (void)menuNuzzle:(id)sender {
    [self triggerNuzzling];
}

- (void)menuPose:(id)sender {
    [self triggerShowingOff];
}

- (void)menuSleep:(id)sender {
    [self toggleSleep];
}

- (void)menuToggleHidden:(id)sender {
    if (self.isHidden) {
        [self showPet];
    } else {
        [self hidePet];
    }
}

- (void)menuToggleMousePassthrough:(id)sender {
    [self toggleMousePassthrough];
}

- (void)menuShowSettings:(id)sender {
    [(id<KimiAppDelegateSettings>)NSApp.delegate showSettingsPanel:self];
}

- (void)menuShowAssets:(id)sender {
    id delegate = NSApp.delegate;
    if ([delegate respondsToSelector:@selector(showAssetsWindow:)]) {
        [delegate showAssetsWindow:self];
    }
}

- (void)reloadNudgeLevel {
    KimiNudgeLevel nudgeLevel = KimiSavedNudgeLevel();
    self.nextNudgeAt = [[NSDate date] dateByAddingTimeInterval:KimiRandomInterval(KimiRepeatNudgeDelayMinForLevel(nudgeLevel), KimiRepeatNudgeDelayMaxForLevel(nudgeLevel))];
}

- (void)refreshIntimacyLabel:(NSTextField *)label {
    [self refreshIntimacyUIInLabel:label];
}

// Intimacy system internals.
- (NSMutableDictionary<NSString *, NSNumber *> *)intimacyCounts {
    NSDictionary<NSString *, NSNumber *> *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:KimiIntimacyCountsDefaultsKey];
    return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

- (NSInteger)totalInteractionsInCounts:(NSDictionary<NSString *, NSNumber *> *)counts {
    NSInteger total = 0;
    for (NSNumber *value in counts.allValues) {
        total += value.integerValue;
    }
    return total;
}

- (NSInteger)totalInteractions {
    return [self totalInteractionsInCounts:[self intimacyCounts]];
}

- (NSInteger)intimacyLevel {
    return KimiIntimacyLevelForTotal([self totalInteractions]);
}

- (NSString *)intimacyMenuTitle {
    NSInteger level = [self intimacyLevel];
    return [NSString stringWithFormat:NSLocalizedString(@"intimacy.level", @""), (long)level, KimiIntimacyLevelNames()[level]];
}

- (void)recordInteractionForKey:(NSString *)key {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary<NSString *, NSNumber *> *counts = [self intimacyCounts];
    NSInteger totalBefore = [self totalInteractionsInCounts:counts];
    counts[key] = @((counts[key] ? counts[key].integerValue : 0) + 1);
    [defaults setObject:counts forKey:KimiIntimacyCountsDefaultsKey];

    NSInteger levelBefore = KimiIntimacyLevelForTotal(totalBefore);
    NSInteger levelAfter = KimiIntimacyLevelForTotal(totalBefore + 1);
    if (levelAfter > levelBefore) {
        [self celebrateLevelUpTo:levelAfter];
    }

}

- (void)celebrateLevelUpTo:(NSInteger)level {
    NSString *message = [NSString stringWithFormat:@"升级啦! Lv.%ld %@", (long)level, KimiIntimacyLevelNames()[level]];
    [self showMessage:message duration:3.6];
    KimiPlaySound(@"levelUp");
    [self addSquashImpulse:0.72];
}

- (void)refreshIntimacyUIInLabel:(NSTextField *)label {
    label.stringValue = [self intimacyMenuTitle];
}

- (void)menuSmaller:(id)sender {
    [self resizeByDelta:-KimiScaleStep];
}

- (void)menuLarger:(id)sender {
    [self resizeByDelta:KimiScaleStep];
}

- (void)menuResetSize:(id)sender {
    [self resetSize];
}

- (void)menuQuit:(id)sender {
    [NSApp terminate:nil];
}

- (void)menuQuote:(id)sender {
    [self triggerQuote];
}

- (void)updateHoverToolTip {
    self.toolTip = self.messagePages.count > 0 ? [self.messagePages componentsJoinedByString:@""] : self.message;
}

- (NSPoint)eventScreenPoint:(NSEvent *)event {
    if (!self.window) {
        return event.locationInWindow;
    }
    return [self.window convertPointToScreen:event.locationInWindow];
}

@end
