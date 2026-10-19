// 俏咪素材库窗口：导入/浏览/删除用户自己的照片与视频素材。
#import <Cocoa/Cocoa.h>

@class KimiPetView;

@interface QiaomiAssetsWindow : NSWindow <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithPetView:(KimiPetView *)petView;
- (void)refresh;

@end
