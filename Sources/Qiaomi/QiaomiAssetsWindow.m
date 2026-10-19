#import "QiaomiAssetsWindow.h"
#import "QiaomiPetView.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSSet<NSString *> *QiaomiSupportedExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"tiff", @"mp4", @"m4v", @"mov"]];
    });
    return extensions;
}

@interface QiaomiDropView : NSView <NSDraggingDestination>
@property (nonatomic, copy, nullable) void (^onFilesDropped)(NSArray<NSURL *> *urls);
@end

@implementation QiaomiDropView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count > 0 && self.onFilesDropped) {
        self.onFilesDropped(urls);
        return YES;
    }
    return NO;
}

@end

@interface QiaomiAssetsWindow ()

@property (nonatomic, strong, nullable) KimiPetView *petView;
@property (nonatomic, strong) NSMutableArray<NSURL *> *mediaURLs;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextField *hintLabel;

@end

@implementation QiaomiAssetsWindow

- (instancetype)initWithPetView:(KimiPetView *)petView {
    NSRect frame = NSMakeRect(0, 0, 480, 430);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.petView = petView;
        self.mediaURLs = [NSMutableArray array];
        self.title = @"俏咪素材库";
        self.releasedWhenClosed = NO;
        self.level = NSFloatingWindowLevel;
        self.minSize = NSMakeSize(420, 320);

        [self buildContent];
        [self refresh];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.contentView;
    NSRect bounds = content.bounds;

    QiaomiDropView *dropView = [[QiaomiDropView alloc] initWithFrame:bounds];
    dropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    __weak typeof(self) weakSelf = self;
    dropView.onFilesDropped = ^(NSArray<NSURL *> *urls) {
        [weakSelf importURLs:urls];
    };
    [content addSubview:dropView];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 52, NSWidth(bounds) - 24, NSHeight(bounds) - 108)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.allowsMultipleSelection = YES;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 52.0;

    NSTableColumn *thumbColumn = [[NSTableColumn alloc] initWithIdentifier:@"thumb"];
    thumbColumn.title = @"预览";
    thumbColumn.width = 64;
    thumbColumn.minWidth = 56;
    [tableView addTableColumn:thumbColumn];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"文件名";
    nameColumn.width = 240;
    nameColumn.minWidth = 160;
    [tableView addTableColumn:nameColumn];

    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"类型";
    typeColumn.width = 60;
    typeColumn.minWidth = 50;
    [tableView addTableColumn:typeColumn];

    scrollView.documentView = tableView;
    self.tableView = tableView;
    [dropView addSubview:scrollView];

    NSButton *addButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 12, 120, 30)];
    addButton.title = @"添加素材…";
    addButton.bezelStyle = NSBezelStyleRounded;
    addButton.target = self;
    addButton.action = @selector(addButtonClicked:);
    [dropView addSubview:addButton];

    NSButton *removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(140, 12, 100, 30)];
    removeButton.title = @"删除选中";
    removeButton.bezelStyle = NSBezelStyleRounded;
    removeButton.target = self;
    removeButton.action = @selector(removeButtonClicked:);
    [dropView addSubview:removeButton];

    NSTextField *hintLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(250, 12, NSWidth(bounds) - 262, 30)];
    hintLabel.stringValue = @"可把照片/视频直接拖进窗口";
    hintLabel.font = [NSFont systemFontOfSize:11];
    hintLabel.textColor = NSColor.secondaryLabelColor;
    hintLabel.editable = NO;
    hintLabel.bezeled = NO;
    hintLabel.drawsBackground = NO;
    hintLabel.autoresizingMask = NSViewWidthSizable;
    self.hintLabel = hintLabel;
    [dropView addSubview:hintLabel];
}

- (void)refresh {
    [self.mediaURLs removeAllObjects];
    NSURL *directory = QiaomiPhotosDirectoryURL();
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
                                                             includingPropertiesForKeys:nil
                                                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  error:nil];
    NSSet<NSString *> *supported = QiaomiSupportedExtensions();
    for (NSURL *url in contents) {
        if ([supported containsObject:url.pathExtension.lowercaseString]) {
            [self.mediaURLs addObject:url];
        }
    }
    [self.mediaURLs sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];
    [self.tableView reloadData];
}

- (void)importURLs:(NSArray<NSURL *> *)urls {
    NSURL *directory = QiaomiPhotosDirectoryURL();
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSSet<NSString *> *supported = QiaomiSupportedExtensions();
    NSUInteger imported = 0;

    for (NSURL *url in urls) {
        if (!url.isFileURL) {
            continue;
        }
        NSString *extension = url.pathExtension.lowercaseString;
        if (![supported containsObject:extension]) {
            continue;
        }

        NSString *baseName = [url.lastPathComponent stringByDeletingPathExtension];
        NSString *destinationName = [url.lastPathComponent copy];
        NSURL *destination = [directory URLByAppendingPathComponent:destinationName];
        NSUInteger suffix = 2;
        while ([fileManager fileExistsAtPath:destination.path]) {
            destinationName = [NSString stringWithFormat:@"%@ %lu.%@", baseName, (unsigned long)suffix, extension];
            destination = [directory URLByAppendingPathComponent:destinationName];
            suffix += 1;
        }

        NSError *error = nil;
        if ([fileManager copyItemAtURL:url toURL:destination error:&error]) {
            imported += 1;
        } else {
            NSLog(@"Qiaomi import failed: %@", error);
        }
    }

    if (imported > 0) {
        [self refresh];
        [self.petView reloadMedia];
        self.hintLabel.stringValue = [NSString stringWithFormat:@"已导入 %lu 个素材，俏咪马上用起来", (unsigned long)imported];
    }
}

- (void)addButtonClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[UTTypeImage, UTTypeMovie];
    if ([panel runModal] == NSModalResponseOK) {
        [self importURLs:panel.URLs];
    }
}

- (void)removeButtonClicked:(id)sender {
    NSIndexSet *indexes = self.tableView.selectedRowIndexes;
    if (indexes.count == 0) {
        return;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *removed = [NSMutableArray array];
    NSMutableArray<NSError *> *failures = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (index < self.mediaURLs.count) {
            NSURL *url = self.mediaURLs[index];
            NSError *error = nil;
            if ([fileManager removeItemAtURL:url error:&error]) {
                [removed addObject:url];
            } else if (error) {
                [failures addObject:error];
                NSLog(@"Qiaomi delete failed for %@: %@", url.lastPathComponent, error);
            }
        }
    }];
    [self refresh];
    if (removed.count > 0) {
        [self.petView reloadMedia];
    }
    if (failures.count > 0) {
        self.hintLabel.stringValue = [NSString stringWithFormat:@"已删除 %lu 个，%lu 个删除失败", (unsigned long)removed.count, (unsigned long)failures.count];
    } else if (removed.count > 0) {
        self.hintLabel.stringValue = [NSString stringWithFormat:@"已删除 %lu 个素材", (unsigned long)removed.count];
    }
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.mediaURLs.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ((NSUInteger)row >= self.mediaURLs.count) {
        return nil;
    }
    NSURL *url = self.mediaURLs[(NSUInteger)row];
    NSString *identifier = tableColumn.identifier;

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = identifier;

        if ([identifier isEqualToString:@"thumb"]) {
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 4, 44, 44)];
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            imageView.tag = 1;
            [cell addSubview:imageView];
        } else {
            NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(4, 14, 180, 20)];
            textField.font = [NSFont systemFontOfSize:12];
            textField.editable = NO;
            textField.bezeled = NO;
            textField.drawsBackground = NO;
            textField.tag = 2;
            [cell addSubview:textField];
        }
    }

    if ([identifier isEqualToString:@"thumb"]) {
        NSImageView *imageView = (NSImageView *)[cell viewWithTag:1];
        if ([self isVideoURL:url]) {
            imageView.image = [NSWorkspace.sharedWorkspace iconForContentType:[UTType typeWithFilenameExtension:url.pathExtension]];
        } else {
            // 优先复用宠物视图已处理过的图片：白底抠图在这里也显示为真正透明的角色。
            NSImage *image = self.petView.images[url.lastPathComponent];
            if (!image) {
                image = [[NSImage alloc] initWithContentsOfURL:url];
            }
            imageView.image = image;
        }
    } else {
        NSTextField *textField = (NSTextField *)[cell viewWithTag:2];
        if ([identifier isEqualToString:@"name"]) {
            textField.stringValue = url.lastPathComponent;
        } else {
            textField.stringValue = [self isVideoURL:url] ? @"视频" : @"图片";
        }
    }
    return cell;
}

- (BOOL)isVideoURL:(NSURL *)url {
    NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[@"mp4", @"m4v", @"mov"]];
    return [videoExtensions containsObject:url.pathExtension.lowercaseString];
}

@end
