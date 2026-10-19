#import "KimiShared.h"
#import <Cocoa/Cocoa.h>
#include <math.h>


NSTimeInterval const KimiTimerInterval = 1.0 / 30.0;
NSString * const KimiScaleDefaultsKey = @"QiaomiScale";
NSString * const KimiNudgeLevelDefaultsKey = @"QiaomiNudgeLevel";
NSString * const KimiActionAssetPrefix = @"qiaomi-action-";
CGFloat const KimiDefaultScale = 0.68;
CGFloat const KimiMinScale = 0.50;
CGFloat const KimiMaxScale = 1.18;
CGFloat const KimiScaleStep = 0.08;

NSSize KimiBaseSize(void) {
    return NSMakeSize(320, 360);
}

CGFloat KimiClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MIN(MAX(value, minValue), maxValue);
}

// MARK: - Persistence keys

NSString * const KimiSoundEnabledDefaultsKey = @"QiaomiSoundEnabled";
NSString * const KimiWindowOriginXDefaultsKey = @"QiaomiWindowOriginX";
NSString * const KimiWindowOriginYDefaultsKey = @"QiaomiWindowOriginY";
NSString * const KimiWindowScreenDefaultsKey = @"QiaomiWindowScreenNumber";
NSString * const KimiWasSleepingDefaultsKey = @"QiaomiWasSleeping";
NSString * const KimiCurrentMediaDefaultsKey = @"QiaomiCurrentMedia";

char QiaomiVideoStatusContext;

NSString * const KimiIntimacyCountsDefaultsKey = @"QiaomiIntimacyCounts";
NSString * const KimiPetNameDefaultsKey = @"QiaomiPetName";
NSString * const KimiQuoteEnabledDefaultsKey = @"QiaomiQuoteEnabled";
NSString * const KimiQuoteLevelDefaultsKey = @"QiaomiQuoteLevel";
static NSString * const KimiMotivationalQuotesDefaultsKey = @"QiaomiMotivationalQuotes";

NSInteger KimiIntimacyLevelForTotal(NSInteger total) {
    if (total >= 4800) return 10;
    if (total >= 3400) return 9;
    if (total >= 2400) return 8;
    if (total >= 1600) {
        return 7;
    }
    if (total >= 1000) {
        return 6;
    }
    if (total >= 600) {
        return 5;
    }
    if (total >= 300) {
        return 4;
    }
    if (total >= 150) {
        return 3;
    }
    if (total >= 60) {
        return 2;
    }
    if (total >= 20) {
        return 1;
    }
    return 0;
}

NSArray<NSString *> *KimiIntimacyLevelNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[
            NSLocalizedString(@"level.0", @""),
            NSLocalizedString(@"level.1", @""),
            NSLocalizedString(@"level.2", @""),
            NSLocalizedString(@"level.3", @""),
            NSLocalizedString(@"level.4", @""),
            NSLocalizedString(@"level.5", @""),
            NSLocalizedString(@"level.6", @""),
            NSLocalizedString(@"level.7", @""),
            NSLocalizedString(@"level.8", @""),
            NSLocalizedString(@"level.9", @""),
            NSLocalizedString(@"level.10", @"")
        ];
    });
    return names;
}


// MARK: - Sound

BOOL KimiSoundEnabled(void) {
    if (![NSUserDefaults.standardUserDefaults objectForKey:KimiSoundEnabledDefaultsKey]) {
        return YES;
    }
    return [NSUserDefaults.standardUserDefaults boolForKey:KimiSoundEnabledDefaultsKey];
}

NSMutableDictionary<NSString *, NSSound *> *KimiSoundCache(void) {
    static NSMutableDictionary<NSString *, NSSound *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

NSString *KimiSystemSoundNameForKey(NSString *key) {
    if ([key isEqualToString:@"petting"] || [key isEqualToString:@"grooming"] || [key isEqualToString:@"sleeping"]) {
        return @"Purr";
    }
    if ([key isEqualToString:@"kissing"] || [key isEqualToString:@"treating"] || [key isEqualToString:@"pickedUp"] || [key isEqualToString:@"waking"]) {
        return @"Pop";
    }
    if ([key isEqualToString:@"playing"]) {
        return @"Blow";
    }
    if ([key isEqualToString:@"levelUp"]) {
        return @"Glass";
    }
    if ([key isEqualToString:@"posing"] || [key isEqualToString:@"nudge"]) {
        return @"Tink";
    }
    return @"Purr";
}

void KimiPlaySound(NSString *key) {
    if (!KimiSoundEnabled()) {
        return;
    }
    NSMutableDictionary<NSString *, NSSound *> *cache = KimiSoundCache();
    NSSound *sound = cache[key];
    if (!sound) {
        sound = [NSSound soundNamed:KimiSystemSoundNameForKey(key)];
        if (sound) {
            cache[key] = sound;
        }
    }
    sound.volume = 0.5;
    [sound play];
}

void KimiSetSoundEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:KimiSoundEnabledDefaultsKey];
}

// MARK: - Phrase pools

NSDictionary<NSString *, NSArray<NSString *> *> *KimiPhrasePoolsZH(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *pools = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pools = @{
            @"greet.morning": @[@"早上好呀", @"新的一天,记得理我", @"早安,摸摸我嘛"],
            @"greet.noon": @[@"午饭吃了吗", @"午休啦,陪我一会儿", @"吃饱了就开始想你"],
            @"greet.evening": @[@"下午/晚上好,忙完了吗", @"天黑了,想你了", @"晚上也要陪陪我"],
            @"greet.lateNight": @[@"这么晚还不睡?", @"熬夜会变丑的,喵", @"陪我一起睡吧"],
            @"idle": @[@"喵", @"想你了", @"在看你哦", @"发呆中…", @"今天的我也很可爱", @"来摸摸我嘛", @"哼,才没有等你", @"工作累了吧,歇会儿"],
            @"bored": @[@"别只工作不理我", @"理我一下嘛", @"好无聊啊…", @"你忙你的,我看着", @"无聊到数星星了"],
            @"wake": @[@"喵?", @"睡醒了,想你了", @"这一觉好香"],
            @"petting": @[@"喵", @"再摸一会儿", @"哼,勉强让你摸", @"好舒服", @"痒痒的"],
            @"kissing": @[@"想你了", @"啵", @"脸红了喵", @"再来一下?"],
            @"treating": @[@"小鱼干!", @"最喜欢你了", @"还有吗?", @"吃饱了超开心"],
            @"playing": @[@"抓到了", @"真好玩", @"再来再来", @"尾巴别跑!"],
            @"grooming": @[@"舒服", @"毛毛顺了", @"轻一点嘛"],
            @"nuzzling": @[@"蹭蹭你", @"好喜欢你", @"再蹭一会儿"],
            @"posing": @[@"看我", @"好看吧", @"今天也是全场最靓"],
            @"pickedUp": @[@"喵?", @"起飞!", @"举高高"],
            @"released": @[@"别只工作不理我", @"放我下来嘛", @"哼"],
            @"levelUp": @[@"我们更亲近了呢", @"升级啦!", @"最喜欢你啦"],
            @"quote": @[
                @"今天也要元气满满呀",
                @"慢慢来,比较快",
                @"你认真努力的样子,最可爱了",
                @"跌倒了就爬起来,喵会陪着你",
                @"每一点进步,都算数",
                @"先完成一小步,再一小步",
                @"你比你想象的更厉害",
                @"休息不是偷懒,是为了走更远",
                @"温柔且坚定,做自己的光",
                @"坚持很难,但坚持很酷",
                @"别怕,你身后还有我",
                @"专注当下,未来会给你答案",
                @"小小的努力,也会开花结果",
                @"你已经很棒了,真的",
                @"新的一天,新的可能",
                @"少想一点,多做一点",
                @"给今天的自己一朵小红花",
                @"人生没有白走的路,每一步都算数",
                @"加油!我一直在你身边",
                @"累了就歇歇,喵陪你",
                @"你的存在,本身就是美好",
                @"把烦恼丢给风,把希望留给明天",
                @"相信自己,你可以的",
                @"心之所向,素履以往"
            ]
        };
    });
    return pools;
}

NSDictionary<NSString *, NSArray<NSString *> *> *KimiPhrasePoolsEN(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *pools = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pools = @{
            @"greet.morning": @[@"Good morning!", @"New day, don't forget me", @"Morning — pet me?"],
            @"greet.noon": @[@"Had lunch yet?", @"Break time! Keep me company", @"Full tummy, thinking of you"],
            @"greet.evening": @[@"Good evening, done working?", @"It's dark out. Miss you", @"Keep me company tonight"],
            @"greet.lateNight": @[@"Still up this late?", @"Staying up makes you ugly, meow", @"Sleep with me"],
            @"idle": @[@"Meow", @"Miss you", @"Watching you…", @"Just spacing out…", @"I'm extra cute today", @"Come pet me", @"Hmph, I wasn't waiting", @"Tired? Rest a bit"],
            @"bored": @[@"Don't just work and ignore me", @"Pay attention to me!", @"Sooo bored…", @"You work, I'll watch", @"Bored enough to count stars"],
            @"wake": @[@"Meow?", @"Woke up, miss you", @"That was a nice nap"],
            @"petting": @[@"Meow", @"A bit more", @"Hmph, I'll allow it", @"So comfy", @"Tingly"],
            @"kissing": @[@"Miss you", @"Mwah", @"Blushing meow", @"One more?"],
            @"treating": @[@"Fish snack!", @"Love you the most", @"Any more?", @"So happy when full"],
            @"playing": @[@"Got it!", @"So fun", @"Again again", @"Tail, don't run!"],
            @"grooming": @[@"Comfy", @"Fur is smooth now", @"Gently please"],
            @"nuzzling": @[@"Nuzzle nuzzle", @"Love you so much", @"A bit more nuzzling"],
            @"posing": @[@"Look at me", @"Cute right?", @"Best looking today"],
            @"pickedUp": @[@"Meow?", @"Taking off!", @"Lift me higher"],
            @"released": @[@"Don't just work and ignore me", @"Put me down", @"Hmph"],
            @"levelUp": @[@"We're closer now!", @"Level up!", @"Love you the most"],
            @"quote": @[
                @"You've got this!",
                @"Small steps count, too.",
                @"Be kind to yourself today.",
                @"One step at a time.",
                @"You're doing better than you think.",
                @"Rest is part of the journey.",
                @"Stay curious, keep going.",
                @"Today is full of new possibilities.",
                @"You are enough, just as you are.",
                @"Little by little, day by day.",
                @"Progress, not perfection.",
                @"Your future self will thank you.",
                @"Breathe. You're exactly where you need to be.",
                @"Don't give up — I'm right here with you.",
                @"Every expert was once a beginner.",
                @"Make today count.",
                @"You're stronger than you know.",
                @"Shine your own light.",
                @"Keep going, your story isn't over.",
                @"Believe in yourself, meow."
            ]
        };
    });
    return pools;
}

NSDictionary<NSString *, NSArray<NSString *> *> *KimiPhrasePools(void) {
    NSString *language = NSLocale.preferredLanguages.firstObject ?: @"zh";
    if ([language hasPrefix:@"en"]) {
        return KimiPhrasePoolsEN();
    }
    return KimiPhrasePoolsZH();
}

NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *KimiPhraseHistories(void) {
    static NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *histories = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        histories = [NSMutableDictionary dictionary];
    });
    return histories;
}

NSString *KimiPhraseForContext(NSString *context) {
    NSArray<NSString *> *pool = KimiPhrasePools()[context];
    if ([context isEqualToString:@"quote"]) {
        NSArray<NSString *> *customQuotes = [NSUserDefaults.standardUserDefaults stringArrayForKey:KimiMotivationalQuotesDefaultsKey];
        if ([NSUserDefaults.standardUserDefaults objectForKey:KimiMotivationalQuotesDefaultsKey]) pool = customQuotes ?: @[];
    }
    if (pool.count == 0) {
        return @"喵";
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *histories = KimiPhraseHistories();
    NSMutableArray<NSNumber *> *history = histories[context];
    if (!history) {
        history = [NSMutableArray array];
        histories[context] = history;
    }

    NSInteger index = -1;
    if (pool.count == 1) {
        index = 0;
    } else {
        for (NSInteger attempt = 0; attempt < 24; attempt++) {
            NSInteger candidate = (NSInteger)arc4random_uniform((uint32_t)pool.count);
            if (![history containsObject:@(candidate)]) {
                index = candidate;
                break;
            }
        }
        if (index < 0) {
            index = (NSInteger)arc4random_uniform((uint32_t)pool.count);
        }
    }

    [history addObject:@(index)];
    while (history.count > 5) {
        [history removeObjectAtIndex:0];
    }

    return pool[index];
}

NSArray<NSString *> *KimiMotivationalQuotes(void) {
    NSArray<NSString *> *saved = [NSUserDefaults.standardUserDefaults stringArrayForKey:KimiMotivationalQuotesDefaultsKey];
    return saved ?: KimiPhrasePools()[@"quote"] ?: @[];
}

void KimiSaveMotivationalQuotes(NSArray<NSString *> *quotes) {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id value in quotes) {
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) [clean addObject:trimmed];
    }
    [NSUserDefaults.standardUserDefaults setObject:clean forKey:KimiMotivationalQuotesDefaultsKey];
}

NSString *KimiGreetingContextForHour(NSInteger hour) {
    if (hour >= 5 && hour < 11) {
        return @"greet.morning";
    }
    if (hour >= 11 && hour < 14) {
        return @"greet.noon";
    }
    if (hour >= 14 && hour < 20) {
        return @"greet.evening";
    }
    return @"greet.lateNight";
}

CGFloat KimiSavedScale(void) {
    CGFloat saved = [NSUserDefaults.standardUserDefaults doubleForKey:KimiScaleDefaultsKey];
    if (saved <= 0) {
        return KimiDefaultScale;
    }
    return KimiClamp(saved, KimiMinScale, KimiMaxScale);
}

KimiNudgeLevel KimiSavedNudgeLevel(void) {
    if (![NSUserDefaults.standardUserDefaults objectForKey:KimiNudgeLevelDefaultsKey]) {
        return KimiNudgeLevelNormal;
    }

    NSInteger saved = [NSUserDefaults.standardUserDefaults integerForKey:KimiNudgeLevelDefaultsKey];
    if (saved < KimiNudgeLevelQuiet || saved > KimiNudgeLevelFrequent) {
        return KimiNudgeLevelNormal;
    }
    return (KimiNudgeLevel)saved;
}

NSSize KimiSizeForScale(CGFloat scale) {
    NSSize base = KimiBaseSize();
    CGFloat clamped = KimiClamp(scale, KimiMinScale, KimiMaxScale);
    return NSMakeSize(round(base.width * clamped), round(base.height * clamped));
}

// MARK: - Motivational quotes

BOOL KimiQuoteEnabled(void) {
    if (![NSUserDefaults.standardUserDefaults objectForKey:KimiQuoteEnabledDefaultsKey]) {
        return YES;
    }
    return [NSUserDefaults.standardUserDefaults boolForKey:KimiQuoteEnabledDefaultsKey];
}

KimiNudgeLevel KimiSavedQuoteLevel(void) {
    if (![NSUserDefaults.standardUserDefaults objectForKey:KimiQuoteLevelDefaultsKey]) {
        return KimiNudgeLevelNormal;
    }
    NSInteger saved = [NSUserDefaults.standardUserDefaults integerForKey:KimiQuoteLevelDefaultsKey];
    if (saved < KimiNudgeLevelQuiet || saved > KimiNudgeLevelFrequent) {
        return KimiNudgeLevelNormal;
    }
    return (KimiNudgeLevel)saved;
}

CGFloat KimiQuoteChanceForLevel(KimiNudgeLevel level) {
    switch (level) {
        case KimiNudgeLevelQuiet:
            return 0.35;
        case KimiNudgeLevelFrequent:
            return 0.65;
        case KimiNudgeLevelNormal:
            return 0.50;
    }
}

NSTimeInterval KimiRandomInterval(NSTimeInterval min, NSTimeInterval max) {
    double value = (double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX;
    return min + (max - min) * value;
}

NSTimeInterval KimiBoredThresholdForLevel(KimiNudgeLevel level) {
    switch (level) {
        case KimiNudgeLevelQuiet:
            return 42;
        case KimiNudgeLevelFrequent:
            return 24;
        case KimiNudgeLevelNormal:
            return 32;
    }
}

NSTimeInterval KimiSleepThresholdForLevel(KimiNudgeLevel level) {
    switch (level) {
        case KimiNudgeLevelQuiet:
            return 118;
        case KimiNudgeLevelFrequent:
            return 64;
        case KimiNudgeLevelNormal:
            return 85;
    }
}

NSTimeInterval KimiRepeatNudgeDelayMinForLevel(KimiNudgeLevel level) {
    switch (level) {
        case KimiNudgeLevelQuiet:
            return 48;
        case KimiNudgeLevelFrequent:
            return 24;
        case KimiNudgeLevelNormal:
            return 34;
    }
}

NSTimeInterval KimiRepeatNudgeDelayMaxForLevel(KimiNudgeLevel level) {
    switch (level) {
        case KimiNudgeLevelQuiet:
            return 76;
        case KimiNudgeLevelFrequent:
            return 42;
        case KimiNudgeLevelNormal:
            return 58;
    }
}

NSRect KimiAspectFillRect(NSSize imageSize, NSRect target) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
        return target;
    }

    CGFloat scale = MAX(target.size.width / imageSize.width, target.size.height / imageSize.height);
    CGFloat width = imageSize.width * scale;
    CGFloat height = imageSize.height * scale;

    return NSMakeRect(
        NSMidX(target) - width / 2.0,
        NSMidY(target) - height / 2.0,
        width,
        height
    );
}

NSRect KimiAspectFitRect(NSSize imageSize, NSRect target) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
        return target;
    }

    CGFloat scale = MIN(target.size.width / imageSize.width, target.size.height / imageSize.height);
    CGFloat width = imageSize.width * scale;
    CGFloat height = imageSize.height * scale;

    return NSMakeRect(
        NSMidX(target) - width / 2.0,
        NSMidY(target) - height / 2.0,
        width,
        height
    );
}

NSURL *QiaomiPhotosDirectoryURL(void) {
    NSURL *appSupport = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
                                                             inDomain:NSUserDomainMask
                                                    appropriateForURL:nil create:YES error:nil];
    NSURL *dir = [appSupport URLByAppendingPathComponent:@"Qiaomi/photos" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}
