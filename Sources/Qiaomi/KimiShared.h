// 俏咪桌宠（Qiaomi Desktop Pet）共享层：枚举、常量与工具函数。
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, KimiState) {
    KimiStateIdle,
    KimiStateBored,
    KimiStatePetting,
    KimiStateKissing,
    KimiStateTreating,
    KimiStatePlaying,
    KimiStateGrooming,
    KimiStateShowingOff,
    KimiStatePickedUp,
    KimiStateSleeping,
    KimiStateNuzzling
};

typedef NS_ENUM(NSInteger, KimiNudgeLevel) {
    KimiNudgeLevelQuiet,
    KimiNudgeLevelNormal,
    KimiNudgeLevelFrequent
};

@protocol KimiAppDelegateSettings <NSObject>
- (void)showSettingsPanel:(id)sender;
- (void)showAssetsWindow:(id)sender;
@end

extern NSTimeInterval const KimiTimerInterval;
extern NSString * const KimiScaleDefaultsKey;
extern NSString * const KimiNudgeLevelDefaultsKey;
extern NSString * const KimiActionAssetPrefix;
extern CGFloat const KimiDefaultScale;
extern CGFloat const KimiMinScale;
extern CGFloat const KimiMaxScale;
extern CGFloat const KimiScaleStep;
extern NSString * const KimiSoundEnabledDefaultsKey;
extern NSString * const KimiWindowOriginXDefaultsKey;
extern NSString * const KimiWindowOriginYDefaultsKey;
extern NSString * const KimiWindowScreenDefaultsKey;
extern NSString * const KimiWasSleepingDefaultsKey;
extern NSString * const KimiCurrentMediaDefaultsKey;
extern NSString * const KimiIntimacyCountsDefaultsKey;
extern NSString * const KimiPetNameDefaultsKey;
extern NSString * const KimiQuoteEnabledDefaultsKey;
extern NSString * const KimiQuoteLevelDefaultsKey;
extern char QiaomiVideoStatusContext;

extern NSSize KimiBaseSize(void);
extern CGFloat KimiClamp(CGFloat value, CGFloat minValue, CGFloat maxValue);
extern NSInteger KimiIntimacyLevelForTotal(NSInteger total);
extern NSArray<NSString *> *KimiIntimacyLevelNames(void);
extern NSArray<NSString *> *KimiMotivationalQuotes(void);
extern void KimiSaveMotivationalQuotes(NSArray<NSString *> *quotes);
extern BOOL KimiSoundEnabled(void);
extern void KimiPlaySound(NSString *key);
extern void KimiSetSoundEnabled(BOOL enabled);
extern NSString *KimiPhraseForContext(NSString *context);
extern NSString *KimiGreetingContextForHour(NSInteger hour);
extern BOOL KimiQuoteEnabled(void);
extern KimiNudgeLevel KimiSavedQuoteLevel(void);
extern CGFloat KimiQuoteChanceForLevel(KimiNudgeLevel level);
extern CGFloat KimiSavedScale(void);
extern KimiNudgeLevel KimiSavedNudgeLevel(void);
extern NSSize KimiSizeForScale(CGFloat scale);
extern NSTimeInterval KimiRandomInterval(NSTimeInterval min, NSTimeInterval max);
extern NSTimeInterval KimiBoredThresholdForLevel(KimiNudgeLevel level);
extern NSTimeInterval KimiSleepThresholdForLevel(KimiNudgeLevel level);
extern NSTimeInterval KimiRepeatNudgeDelayMinForLevel(KimiNudgeLevel level);
extern NSTimeInterval KimiRepeatNudgeDelayMaxForLevel(KimiNudgeLevel level);
extern NSRect KimiAspectFillRect(NSSize imageSize, NSRect target);
extern NSRect KimiAspectFitRect(NSSize imageSize, NSRect target);
extern NSURL *QiaomiPhotosDirectoryURL(void);
