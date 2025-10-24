#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// Reuse your overlay infra (adjust the paths if your repo differs)
#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"

#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/QTMIcon.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTPlayerViewController.h>

#define TweakKey @"YouSubscribe"

// ---------- HUD / Snackbar ----------
@interface YTHUDMessage : NSObject
+ (id)messageWithText:(id)text;
@end

@interface GOOHUDManagerInternal : NSObject
- (void)showMessageMainThread:(id)message;
+ (id)sharedInstance;
@end

static inline void ShowHUD(NSString *text) {
    [[%c(GOOHUDManagerInternal) sharedInstance]
        showMessageMainThread:[%c(YTHUDMessage) messageWithText:text ?: @""]];
}

// ---------- Forward declarations for internal YT classes (runtime-resolved) ----------
// NB: These headers move often; we forward-declare the bits we need.
@interface YTISubscribeEndpoint : NSObject
- (void)setChannelId:(NSString *)channelId;
@end

@interface YTIUnsubscribeEndpoint : NSObject
- (void)setChannelId:(NSString *)channelId;
@end

@interface YTICommand : NSObject
- (void)setSubscribeEndpoint:(YTISubscribeEndpoint *)endpoint;
- (void)setUnsubscribeEndpoint:(YTIUnsubscribeEndpoint *)endpoint;
@end

// Command executor — class name varies across versions. We try a few.
@interface YTCommandResolver : NSObject
+ (instancetype)sharedInstance;
- (void)executeCommand:(id)command;
@end

@interface YTCommandExecutor : NSObject
+ (instancetype)sharedInstance;
- (void)executeCommand:(id)command;
@end

// ---------- Overlay category stubs ----------
@interface YTMainAppVideoPlayerOverlayViewController (YouSubscribe)
@property (nonatomic, weak) YTPlayerViewController *parentViewController;
@end

@interface YTMainAppVideoPlayerOverlayView (YouSubscribe)
@property (nonatomic, weak, readwrite) YTMainAppVideoPlayerOverlayViewController *delegate;
@end

@interface YTMainAppControlsOverlayView (YouSubscribe)
@property (nonatomic, weak) YTPlayerViewController *playerViewController;
- (void)didPressYouSubscribe:(id)arg;
@end

@interface YTInlinePlayerBarController : NSObject
@end

@interface YTInlinePlayerBarContainerView (YouSubscribe)
@property (nonatomic, strong) YTInlinePlayerBarController *delegate;
- (void)didPressYouSubscribe:(id)arg;
@end

// ---------- Subscribe icon (expects an asset named "Subscribe@3" in the target app's bundle or your injected bundle) ----------
static UIImage *subscribeImage(NSString *qualityLabel) {
    return [%c(QTMIcon) tintImage:[UIImage imageNamed:[NSString stringWithFormat:@"Subscribe@%@", qualityLabel]
                                              inBundle:nil
                         compatibleWithTraitCollection:nil]
                              color:[%c(YTColor) white1]];
}

// ---------- Helper: find channel ID from the current player by probing common keys ----------
static NSString *YSChannelIDFromPlayer(YTPlayerViewController *pvc) {
    if (!pvc) return nil;
    // Try a bunch of likely properties/ivars via KVC. This is resilient across YT versions.
    NSArray<NSString *> *keys = @[
        @"channelId", @"channelID", @"uploaderChannelId", @"uploaderChannelID",
        @"videoChannelId", @"watchChannelId", @"currentChannelId",
        @"playerResponse.channelId", @"playerResponse.videoDetails.channelId",
        @"currentVideo.author.channelId"
    ];
    for (NSString *key in keys) {
        @try {
            id val = [pvc valueForKeyPath:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) {
                return (NSString *)val;
            }
        } @catch (__unused NSException *e) {
            // ignore missing keys
        }
    }
    return nil;
}

// ---------- Helper: get a command executor instance (class name varies) ----------
static id YSCommandExecutor(void) {
    Class cls = NSClassFromString(@"YTCommandResolver");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    }
    cls = NSClassFromString(@"YTCommandExecutor");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    }
    // Fallback: return nil; caller will show an error HUD.
    return nil;
}

// ---------- Main logic ----------
%group Main
%hook YTPlayerViewController

%new
- (void)didPressYouSubscribe {
    NSString *channelId = YSChannelIDFromPlayer(self);
    if (!channelId) {
        ShowHUD(@"Can't find channel ID");
        return;
    }

    // Build endpoint & command dynamically
    id endpoint = [[%c(YTISubscribeEndpoint) alloc] init];
    if (!endpoint || ![endpoint respondsToSelector:@selector(setChannelId:)]) {
        ShowHUD(@"Subscribe endpoint unavailable");
        return;
    }
    [endpoint setChannelId:channelId];

    id cmd = [[%c(YTICommand) alloc] init];
    if (!cmd || ![cmd respondsToSelector:@selector(setSubscribeEndpoint:)]) {
        ShowHUD(@"Subscribe command unavailable");
        return;
    }
    [cmd setSubscribeEndpoint:endpoint];

    id exec = YSCommandExecutor();
    if (exec && [exec respondsToSelector:@selector(executeCommand:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(exec, @selector(executeCommand:), cmd);
        ShowHUD(@"Subscribed");
    } else {
        ShowHUD(@"Command executor not found");
    }
}
%end
%end

%group Top
%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakKey] ? subscribeImage(@"3") : %orig;
}

%new(v@:@)
- (void)didPressYouSubscribe:(id)arg {
    YTMainAppVideoPlayerOverlayView *mainOverlayView = (YTMainAppVideoPlayerOverlayView *)self.superview;
    YTMainAppVideoPlayerOverlayViewController *mainOverlayController = (YTMainAppVideoPlayerOverlayViewController *)mainOverlayView.delegate;
    YTPlayerViewController *playerViewController = mainOverlayController.parentViewController;
    if (playerViewController) {
        [playerViewController didPressYouSubscribe];
    }
}
%end
%end

%group Bottom
%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakKey] ? subscribeImage(@"3") : %orig;
}

%new(v@:@)
- (void)didPressYouSubscribe:(id)arg {
    YTInlinePlayerBarController *delegate = self.delegate;
    YTMainAppVideoPlayerOverlayViewController *_delegate = [delegate valueForKey:@"_delegate"];
    YTPlayerViewController *parentViewController = _delegate.parentViewController;
    if (parentViewController) {
        [parentViewController didPressYouSubscribe];
    }
}
%end
%end

%ctor {
    initYTVideoOverlay(TweakKey, @{
        AccessibilityLabelKey: @"Subscribe",
        SelectorKey: @"didPressYouSubscribe:",
    });
    %init(Main);
    %init(Top);
    %init(Bottom);
}
