#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/QTMIcon.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTPlayerViewController.h>

#define TweakKey @"YouSubscribe"

// ---------- HUD ----------
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

// ---------- YT internals ----------
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

@interface YTCommandResolver : NSObject
+ (instancetype)sharedInstance;
- (void)executeCommand:(id)command;
@end

@interface YTCommandExecutor : NSObject
+ (instancetype)sharedInstance;
- (void)executeCommand:(id)command;
@end

// ---------- Overlay categories ----------
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

@interface YTPlayerViewController (YouSubscribe)
- (void)didPressYouSubscribe;
@end

@interface YTInlinePlayerBarController : NSObject
@end

@interface YTInlinePlayerBarContainerView (YouSubscribe)
@property (nonatomic, strong) YTInlinePlayerBarController *delegate;
- (void)didPressYouSubscribe:(id)arg;
@end

// ---------- Subscribe icon ----------
static UIImage *subscribeImage(NSString *qualityLabel) {
    return [%c(QTMIcon) tintImage:[UIImage imageNamed:[NSString stringWithFormat:@"Subscribe@%@", qualityLabel]
                                              inBundle:nil
                         compatibleWithTraitCollection:nil]
                              color:[%c(YTColor) white1]];
}

// ---------- Channel ID helper ----------
static NSString *YSChannelIDFromPlayer(YTPlayerViewController *pvc) {
    if (!pvc) return nil;
    NSArray<NSString *> *keys = @[
        @"channelId", @"channelID", @"uploaderChannelId", @"uploaderChannelID",
        @"videoChannelId", @"watchChannelId", @"currentChannelId",
        @"playerResponse.videoDetails.channelId",
        @"currentVideo.author.channelId"
    ];
    for (NSString *key in keys) {
        @try {
            id val = [pvc valueForKeyPath:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) {
                return (NSString *)val;
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

// ---------- Subscribe state helper ----------
static BOOL YSIsSubscribed(YTPlayerViewController *pvc) {
    @try {
        id val = [pvc valueForKeyPath:@"currentVideo.owner.isSubscribed"];
        if ([val respondsToSelector:@selector(boolValue)]) {
            return [val boolValue];
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[YouSubscribe] Could not resolve isSubscribed keypath");
    }
    return NO;
}

// ---------- Command executor helper ----------
static id YSCommandExecutor(void) {
    Class cls = NSClassFromString(@"YTCommandResolver");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    }
    cls = NSClassFromString(@"YTCommandExecutor");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    }
    return nil;
}

// ---------- Main ----------
%group Main
%hook YTPlayerViewController

%new
- (void)didPressYouSubscribe {
    NSString *channelId = YSChannelIDFromPlayer(self);
    if (!channelId) {
        ShowHUD(@"Can't find channel ID");
        return;
    }

    BOOL isSubscribed = YSIsSubscribed(self);
    id cmd = [[%c(YTICommand) alloc] init];

    if (isSubscribed) {
        id endpoint = [[%c(YTIUnsubscribeEndpoint) alloc] init];
        if (endpoint && [endpoint respondsToSelector:@selector(setChannelId:)]) {
            [endpoint setChannelId:channelId];
            [cmd setUnsubscribeEndpoint:endpoint];
            ShowHUD(@"Unsubscribed");
        } else {
            ShowHUD(@"Unsubscribe endpoint unavailable");
            return;
        }
    } else {
        id endpoint = [[%c(YTISubscribeEndpoint) alloc] init];
        if (endpoint && [endpoint respondsToSelector:@selector(setChannelId:)]) {
            [endpoint setChannelId:channelId];
            [cmd setSubscribeEndpoint:endpoint];
            ShowHUD(@"Subscribed");
        } else {
            ShowHUD(@"Subscribe endpoint unavailable");
            return;
        }
    }

    id exec = YSCommandExecutor();
    if (exec && [exec respondsToSelector:@selector(executeCommand:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(exec, @selector(executeCommand:), cmd);
    } else {
        ShowHUD(@"Executor not found");
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
