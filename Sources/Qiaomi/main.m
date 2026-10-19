#import <Cocoa/Cocoa.h>
#import <ServiceManagement/SMAppService.h>
#import "KimiShared.h"
#import "QiaomiPetView.h"
#import "QiaomiAssetsWindow.h"

@interface KimiWindow : NSWindow
@end

@implementation KimiWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong, nullable) KimiWindow *window;
@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) NSMenuItem *hideMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *sleepMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *mousePassthroughMenuItem;
@property (nonatomic, strong, nullable) NSWindow *settingsWindow;
@property (nonatomic, strong, nullable) NSWindow *quoteManagerWindow;
@property (nonatomic, strong, nullable) NSTableView *quoteTable;
@property (nonatomic, strong, nullable) NSTextField *quoteEditor;
@property (nonatomic, strong, nullable) NSTextField *quoteEmptyLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *editableQuotes;
@property (nonatomic, strong, nullable) QiaomiAssetsWindow *assetsWindow;
@property (nonatomic, strong, nullable) NSTextField *petNameField;
@property (nonatomic, strong, nullable) NSButton *soundCheckbox;
@property (nonatomic, strong, nullable) NSPopUpButton *nudgePopup;
@property (nonatomic, strong, nullable) NSButton *quoteCheckbox;
@property (nonatomic, strong, nullable) NSPopUpButton *quotePopup;
@property (nonatomic, strong, nullable) NSButton *launchCheckbox;
@property (nonatomic, strong, nullable) NSTextField *intimacyLabel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSSize size = KimiSizeForScale(KimiSavedScale());
    NSScreen *targetScreen = NSScreen.mainScreen;
    NSInteger savedScreenNumber = [NSUserDefaults.standardUserDefaults integerForKey:KimiWindowScreenDefaultsKey];
    if (savedScreenNumber != 0) {
        for (NSScreen *screen in NSScreen.screens) {
            NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
            if (number && number.integerValue == savedScreenNumber) {
                targetScreen = screen;
                break;
            }
        }
    }
    NSRect visibleFrame = targetScreen ? targetScreen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    NSPoint origin;
    if ([NSUserDefaults.standardUserDefaults objectForKey:KimiWindowOriginXDefaultsKey]) {
        origin = NSMakePoint(
            [NSUserDefaults.standardUserDefaults doubleForKey:KimiWindowOriginXDefaultsKey],
            [NSUserDefaults.standardUserDefaults doubleForKey:KimiWindowOriginYDefaultsKey]
        );
        NSRect savedFrame = NSMakeRect(origin.x, origin.y, size.width, size.height);
        if (NSMaxX(savedFrame) > NSMaxX(visibleFrame)) {
            origin.x = NSMaxX(visibleFrame) - size.width;
        }
        if (NSMinX(savedFrame) < NSMinX(visibleFrame)) {
            origin.x = NSMinX(visibleFrame);
        }
        if (NSMaxY(savedFrame) > NSMaxY(visibleFrame)) {
            origin.y = NSMaxY(visibleFrame) - size.height;
        }
        if (NSMinY(savedFrame) < NSMinY(visibleFrame)) {
            origin.y = NSMinY(visibleFrame);
        }
    } else {
        origin = NSMakePoint(NSMaxX(visibleFrame) - size.width - 42, NSMinY(visibleFrame) + 58);
    }

    KimiWindow *window = [[KimiWindow alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height)
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    window.title = NSLocalizedString(@"window.title", @"");
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = NO;
    window.level = NSFloatingWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
    window.ignoresMouseEvents = NO;
    window.releasedWhenClosed = NO;

    KimiPetView *view = [[KimiPetView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.mousePassthroughEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"KimiMousePassthroughEnabled"];
    window.contentView = view;
    window.ignoresMouseEvents = view.mousePassthroughEnabled;
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];

    self.window = window;

    [self setupStatusItem];
}

#pragma mark - Status item

- (KimiPetView *)petView {
    return (KimiPetView *)self.window.contentView;
}

- (NSImage *)statusItemIcon {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(18, 18)];
    [image lockFocus];
    NSColor *ink = NSColor.blackColor;
    [ink setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5, 2.5, 8, 8)] fill];
    NSArray<NSValue *> *toes = @[
        [NSValue valueWithPoint:NSMakePoint(2.8, 10.4)],
        [NSValue valueWithPoint:NSMakePoint(6.6, 11.8)],
        [NSValue valueWithPoint:NSMakePoint(10.4, 10.4)]
    ];
    for (NSValue *value in toes) {
        NSPoint point = value.pointValue;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x, point.y, 3.2, 3.2)] fill];
    }
    [image unlockFocus];
    image.template = YES;
    return image;
}

- (void)setupStatusItem {
    NSStatusItem *item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    item.button.image = [self statusItemIcon];
    item.button.toolTip = NSLocalizedString(@"app.name", @"");
    item.menu = [self statusItemMenu];
    self.statusItem = item;
}

- (NSMenu *)statusItemMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"app.name", @"")];
    menu.delegate = self;

    NSString *petName = [self petView].petName;
    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"menu.hide.fmt", @""), petName] action:@selector(menuToggleHide:) keyEquivalent:@""];
    hideItem.target = self;
    self.hideMenuItem = hideItem;
    [menu addItem:hideItem];

    NSMenuItem *sleepItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"menu.sleep.fmt", @""), petName] action:@selector(menuToggleSleep:) keyEquivalent:@""];
    sleepItem.target = self;
    self.sleepMenuItem = sleepItem;
    [menu addItem:sleepItem];

    NSMenuItem *passthroughItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.mousePassthrough", @"") action:@selector(menuToggleMousePassthrough:) keyEquivalent:@""];
    passthroughItem.target = self;
    self.mousePassthroughMenuItem = passthroughItem;
    [menu addItem:passthroughItem];

    NSMenuItem *assetsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.assets", @"") action:@selector(showAssetsWindow:) keyEquivalent:@""];
    assetsItem.target = self;
    [menu addItem:assetsItem];

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.settings", @"") action:@selector(showSettingsPanel:) keyEquivalent:@","];
    settingsItem.target = self;
    [menu addItem:settingsItem];

    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"menu.quit.fmt", @""), petName] action:@selector(menuQuit:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    return menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    KimiPetView *view = [self petView];
    NSString *petName = view.petName;
    self.hideMenuItem.title = view.isHidden
        ? [NSString stringWithFormat:NSLocalizedString(@"menu.show.fmt", @""), petName]
        : [NSString stringWithFormat:NSLocalizedString(@"menu.hide.fmt", @""), petName];
    self.hideMenuItem.state = view.isHidden ? NSControlStateValueOn : NSControlStateValueOff;
    self.sleepMenuItem.title = view.state == KimiStateSleeping
        ? [NSString stringWithFormat:NSLocalizedString(@"menu.wake.fmt", @""), petName]
        : [NSString stringWithFormat:NSLocalizedString(@"menu.sleep.fmt", @""), petName];
    self.mousePassthroughMenuItem.state = view.mousePassthroughEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)menuToggleHide:(id)sender {
    KimiPetView *view = [self petView];
    if (view.isHidden) {
        [view showPet];
    } else {
        [view hidePet];
    }
}

- (void)menuToggleSleep:(id)sender {
    [[self petView] toggleSleep];
}

- (void)menuToggleMousePassthrough:(id)sender {
    [[self petView] toggleMousePassthrough];
}

- (void)menuQuit:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - Settings panel

- (NSButton *)makeCheckboxWithTitle:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:frame];
    checkbox.title = title;
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.target = self;
    checkbox.action = action;
    return checkbox;
}

- (NSPopUpButton *)makePopupWithItems:(NSArray<NSString *> *)items action:(SEL)action frame:(NSRect)frame {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
    [popup addItemsWithTitles:items];
    popup.target = self;
    popup.action = action;
    return popup;
}

- (void)addSectionLabel:(NSString *)title y:(CGFloat)y inView:(NSView *)content {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 340, 18)];
    label.stringValue = title;
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    label.textColor = NSColor.secondaryLabelColor;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    [content addSubview:label];
}

- (void)addFieldLabel:(NSString *)title x:(CGFloat)x y:(CGFloat)y inView:(NSView *)content {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 96, 20)];
    label.stringValue = title;
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = NSColor.labelColor;
    label.alignment = NSTextAlignmentRight;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    [content addSubview:label];
}

- (void)buildSettingsWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 410)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"settings.title", @"");
    window.releasedWhenClosed = NO;
    window.level = NSFloatingWindowLevel;
    NSView *content = window.contentView;

    [self addSectionLabel:NSLocalizedString(@"settings.role", @"") y:355 inView:content];
    [self addFieldLabel:NSLocalizedString(@"settings.name", @"") x:16 y:326 inView:content];
    NSTextField *petNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 323, 160, 24)];
    petNameField.placeholderString = NSLocalizedString(@"settings.name.placeholder", @"");
    petNameField.target = self;
    petNameField.action = @selector(petNameChanged:);
    self.petNameField = petNameField;
    [content addSubview:petNameField];

    [self addSectionLabel:NSLocalizedString(@"settings.sound", @"") y:290 inView:content];
    NSButton *soundCheckbox = [self makeCheckboxWithTitle:NSLocalizedString(@"settings.sound.enabled", @"")
                                                    action:@selector(soundEnabledChanged:)
                                                     frame:NSMakeRect(20, 261, 240, 24)];
    self.soundCheckbox = soundCheckbox;
    [content addSubview:soundCheckbox];

    [self addSectionLabel:NSLocalizedString(@"settings.nudge", @"") y:227 inView:content];
    NSPopUpButton *nudgePopup = [self makePopupWithItems:@[NSLocalizedString(@"menu.nudge.quiet", @""), NSLocalizedString(@"menu.nudge.normal", @""), NSLocalizedString(@"menu.nudge.frequent", @"")]
                                                 action:@selector(nudgeChanged:)
                                                  frame:NSMakeRect(130, 195, 150, 26)];
    self.nudgePopup = nudgePopup;
    [content addSubview:nudgePopup];

    [self addSectionLabel:NSLocalizedString(@"settings.quote", @"") y:162 inView:content];
    NSButton *manageQuotesButton = [[NSButton alloc] initWithFrame:NSMakeRect(246, 154, 114, 24)];
    manageQuotesButton.title = NSLocalizedString(@"settings.quote.manage", @"");
    manageQuotesButton.bezelStyle = NSBezelStyleRounded;
    manageQuotesButton.target = self;
    manageQuotesButton.action = @selector(showQuoteManager:);
    [content addSubview:manageQuotesButton];
    NSButton *quoteCheckbox = [self makeCheckboxWithTitle:NSLocalizedString(@"settings.quote.enabled", @"")
                                                    action:@selector(quoteEnabledChanged:)
                                                     frame:NSMakeRect(20, 132, 220, 24)];
    self.quoteCheckbox = quoteCheckbox;
    [content addSubview:quoteCheckbox];
    NSPopUpButton *quotePopup = [self makePopupWithItems:@[NSLocalizedString(@"menu.nudge.quiet", @""), NSLocalizedString(@"menu.nudge.normal", @""), NSLocalizedString(@"menu.nudge.frequent", @"")]
                                                 action:@selector(quoteChanged:)
                                                  frame:NSMakeRect(240, 130, 120, 26)];
    self.quotePopup = quotePopup;
    [content addSubview:quotePopup];

    NSButton *launchCheckbox = [self makeCheckboxWithTitle:NSLocalizedString(@"settings.launch", @"")
                                                     action:@selector(launchAtLoginChanged:)
                                                      frame:NSMakeRect(20, 98, 240, 24)];
    self.launchCheckbox = launchCheckbox;
    [content addSubview:launchCheckbox];

    NSButton *assetsButton = [[NSButton alloc] initWithFrame:NSMakeRect(260, 92, 100, 30)];
    assetsButton.title = NSLocalizedString(@"settings.assets", @"");
    assetsButton.bezelStyle = NSBezelStyleRounded;
    assetsButton.target = self;
    assetsButton.action = @selector(showAssetsWindow:);
    [content addSubview:assetsButton];

    NSTextField *intimacyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 46, 340, 20)];
    intimacyLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    intimacyLabel.textColor = NSColor.labelColor;
    intimacyLabel.editable = NO;
    intimacyLabel.bezeled = NO;
    intimacyLabel.drawsBackground = NO;
    self.intimacyLabel = intimacyLabel;
    [content addSubview:intimacyLabel];

    NSTextField *versionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 10, 380, 18)];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1";
    versionLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"settings.version", @""), version];
    versionLabel.font = [NSFont systemFontOfSize:11];
    versionLabel.textColor = NSColor.tertiaryLabelColor;
    versionLabel.alignment = NSTextAlignmentCenter;
    versionLabel.editable = NO;
    versionLabel.bezeled = NO;
    versionLabel.drawsBackground = NO;
    [content addSubview:versionLabel];
    self.settingsWindow = window;
}

- (void)showQuoteManager:(id)sender {
    if (!self.quoteManagerWindow) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 430, 390)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing:NSBackingStoreBuffered defer:NO];
        window.title = NSLocalizedString(@"quotes.title", @"");
        window.releasedWhenClosed = NO;
        [window center];
        NSView *content = window.contentView;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 112, 398, 254)];
        scroll.hasVerticalScroller = YES;
        NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"quote"];
        column.title = NSLocalizedString(@"settings.quote", @"");
        column.width = 380;
        [table addTableColumn:column];
        table.headerView = nil;
        table.rowHeight = 30;
        table.dataSource = self;
        table.delegate = self;
        scroll.documentView = table;
        [content addSubview:scroll];
        self.quoteTable = table;
        NSTextField *emptyLabel = [NSTextField labelWithString:NSLocalizedString(@"quotes.empty", @"")];
        emptyLabel.frame = NSMakeRect(24, 218, 382, 42);
        emptyLabel.alignment = NSTextAlignmentCenter;
        emptyLabel.textColor = NSColor.secondaryLabelColor;
        emptyLabel.maximumNumberOfLines = 2;
        self.quoteEmptyLabel = emptyLabel;
        [content addSubview:emptyLabel];

        NSTextField *editor = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 76, 398, 26)];
        editor.placeholderString = NSLocalizedString(@"quotes.placeholder", @"");
        self.quoteEditor = editor;
        [content addSubview:editor];
        NSArray<NSDictionary *> *buttons = @[
            @{ @"title": NSLocalizedString(@"quotes.add", @""), @"action": NSStringFromSelector(@selector(addQuote:)), @"x": @16, @"width": @112 },
            @{ @"title": NSLocalizedString(@"quotes.save", @""), @"action": NSStringFromSelector(@selector(saveEditedQuote:)), @"x": @136, @"width": @166 },
            @{ @"title": NSLocalizedString(@"quotes.delete", @""), @"action": NSStringFromSelector(@selector(deleteQuote:)), @"x": @310, @"width": @104 }
        ];
        for (NSDictionary *spec in buttons) {
            NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect([spec[@"x"] doubleValue], 30, [spec[@"width"] doubleValue], 30)];
            button.title = spec[@"title"];
            button.bezelStyle = NSBezelStyleRounded;
            button.target = self;
            button.action = NSSelectorFromString(spec[@"action"]);
            [content addSubview:button];
        }
        self.quoteManagerWindow = window;
    }
    self.editableQuotes = [KimiMotivationalQuotes() mutableCopy];
    [self.quoteTable reloadData];
    self.quoteEmptyLabel.hidden = self.editableQuotes.count > 0;
    self.quoteEditor.stringValue = @"";
    [NSApp activateIgnoringOtherApps:YES];
    [self.quoteManagerWindow makeKeyAndOrderFront:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.editableQuotes.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"quoteCell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"quoteCell";
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    cell.stringValue = self.editableQuotes[row];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.quoteTable.selectedRow;
    self.quoteEditor.stringValue = (row >= 0 && row < (NSInteger)self.editableQuotes.count) ? self.editableQuotes[(NSUInteger)row] : @"";
}

- (void)persistQuotesAndRefresh {
    KimiSaveMotivationalQuotes(self.editableQuotes);
    [self.quoteTable reloadData];
    self.quoteEmptyLabel.hidden = self.editableQuotes.count > 0;
}

- (void)addQuote:(id)sender {
    NSString *quote = [self.quoteEditor.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (quote.length == 0) return;
    [self.editableQuotes addObject:quote];
    [self persistQuotesAndRefresh];
    [self.quoteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:self.editableQuotes.count - 1] byExtendingSelection:NO];
}

- (void)saveEditedQuote:(id)sender {
    NSInteger row = self.quoteTable.selectedRow;
    NSString *quote = [self.quoteEditor.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (row < 0 || row >= (NSInteger)self.editableQuotes.count || quote.length == 0) return;
    self.editableQuotes[(NSUInteger)row] = quote;
    [self persistQuotesAndRefresh];
    [self.quoteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (void)deleteQuote:(id)sender {
    NSInteger row = self.quoteTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.editableQuotes.count) return;
    [self.editableQuotes removeObjectAtIndex:(NSUInteger)row];
    [self.quoteEditor setStringValue:@""];
    [self persistQuotesAndRefresh];
}

- (void)showSettingsPanel:(id)sender {
    if (!self.settingsWindow) {
        [self buildSettingsWindow];
    }
    [self refreshSettingsControls];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindow makeKeyAndOrderFront:nil];
}

- (void)refreshSettingsControls {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.soundCheckbox.state = KimiSoundEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    [self.nudgePopup selectItemAtIndex:KimiSavedNudgeLevel()];
    self.quoteCheckbox.state = KimiQuoteEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    [self.quotePopup selectItemAtIndex:KimiSavedQuoteLevel()];
    self.launchCheckbox.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *petName = [defaults stringForKey:KimiPetNameDefaultsKey];
    self.petNameField.stringValue = petName.length > 0 ? petName : @"俏咪";
    [[self petView] refreshIntimacyLabel:self.intimacyLabel];
}

- (void)petNameChanged:(id)sender {
    NSString *name = self.petNameField.stringValue;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        trimmed = @"俏咪";
        self.petNameField.stringValue = trimmed;
    }
    if (trimmed.length > 12) {
        NSRange composedPrefix = [trimmed rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 12)];
        trimmed = [trimmed substringToIndex:NSMaxRange(composedPrefix)];
        self.petNameField.stringValue = trimmed;
    }
    [NSUserDefaults.standardUserDefaults setObject:trimmed forKey:KimiPetNameDefaultsKey];
    [self petView].petName = trimmed;
}

- (void)showAssetsWindow:(id)sender {
    if (!self.assetsWindow) {
        self.assetsWindow = [[QiaomiAssetsWindow alloc] initWithPetView:[self petView]];
    }
    [self.assetsWindow refresh];
    [NSApp activateIgnoringOtherApps:YES];
    [self.assetsWindow makeKeyAndOrderFront:nil];
}

- (void)soundEnabledChanged:(id)sender {
    KimiSetSoundEnabled(self.soundCheckbox.state == NSControlStateValueOn);
}

- (void)nudgeChanged:(id)sender {
    NSInteger level = [self.nudgePopup indexOfSelectedItem];
    if (level >= KimiNudgeLevelQuiet && level <= KimiNudgeLevelFrequent) {
        [NSUserDefaults.standardUserDefaults setInteger:level forKey:KimiNudgeLevelDefaultsKey];
        [[self petView] reloadNudgeLevel];
    }
}

- (void)quoteEnabledChanged:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:self.quoteCheckbox.state == NSControlStateValueOn
                                          forKey:KimiQuoteEnabledDefaultsKey];
}

- (void)quoteChanged:(id)sender {
    NSInteger level = [self.quotePopup indexOfSelectedItem];
    if (level >= KimiNudgeLevelQuiet && level <= KimiNudgeLevelFrequent) {
        [NSUserDefaults.standardUserDefaults setInteger:level forKey:KimiQuoteLevelDefaultsKey];
    }
}

- (void)launchAtLoginChanged:(id)sender {
    BOOL enabled = self.launchCheckbox.state == NSControlStateValueOn;
    NSError *error = nil;
    if (enabled) {
        if (![SMAppService.mainAppService registerAndReturnError:&error]) {
            self.launchCheckbox.state = NSControlStateValueOff;
            NSLog(@"SMAppService register failed: %@", error);
        }
    } else {
        if (![SMAppService.mainAppService unregisterAndReturnError:&error]) {
            self.launchCheckbox.state = NSControlStateValueOn;
            NSLog(@"SMAppService unregister failed: %@", error);
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if ([self.window.contentView isKindOfClass:[KimiPetView class]]) {
        [(KimiPetView *)self.window.contentView saveWindowState];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
