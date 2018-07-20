//
//  ZYNetworkAccessibity.m
//  Created by zie on 16/11/17.
//  Copyright © 2017年 zie. All rights reserved.
//

#import "ZYNetworkAccessibity.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCellularData.h>
#import <SystemConfiguration/SystemConfiguration.h>

NSString * const ZYNetworkAccessibityChangedNotification = @"ZYNetworkAccessibityChangedNotification";

typedef NS_ENUM(NSInteger, ZYNetworkType) {
    ZYNetworkTypeOffline ,
    ZYNetworkTypeWiFi    ,
    ZYNetworkTypeCellularData ,
};

@interface ZYNetworkAccessibity()
@property (nonatomic, strong) CTCellularData *cellularData;
@property (nonatomic, strong) NSMutableArray *checkingCallbacks;
@property (nonatomic, assign) ZYNetworkAccessibleState previousState;
@property (nonatomic, assign, getter=isPreparingCheck) BOOL preparingCheck;
@property (nonatomic, strong) UIAlertController *alertController;
@property (nonatomic, copy) NetworkAccessibleStateNotifier networkAccessibleStateDidUpdateNotifier;
@property(nonatomic, assign) BOOL automaticallyAlert;

@end


@implementation ZYNetworkAccessibity

#pragma mark - Public

+ (void)setAlertEnable:(BOOL)setAlertEnable {
    [self sharedInstance].automaticallyAlert = setAlertEnable;
}


+ (void)checkState:(void (^)(ZYNetworkAccessibleState))block {
    
    [[self sharedInstance] checkNetworkAccessibleStateWithCompletionBlock:block];
}


+ (void)monitor:(void (^)(ZYNetworkAccessibleState))block {
    
    [[self sharedInstance] monitorNetworkAccessibleStateWithCompletionBlock:block];
}

+ (ZYNetworkAccessibleState)currentState {
    return [[self sharedInstance] currentState];
}

#pragma mark - Public entity method

+ (ZYNetworkAccessibity *)sharedInstance {
    static ZYNetworkAccessibity * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        
        instance.cellularData = [[CTCellularData alloc] init];
        
        instance.checkingCallbacks = [NSMutableArray array];
        
        [[NSNotificationCenter defaultCenter] addObserver:instance selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] addObserver:instance selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
        
        
    });
    
    return instance;
}


- (void)setNetworkAccessibleStateDidUpdateNotifier:(NetworkAccessibleStateNotifier)networkAccessibleStateDidUpdateNotifier {
    _networkAccessibleStateDidUpdateNotifier = [networkAccessibleStateDidUpdateNotifier copy];
    
    [self prepareToCheck];
}


- (void)checkNetworkAccessibleStateWithCompletionBlock:(void (^)(ZYNetworkAccessibleState))block {
    
    [self.checkingCallbacks addObject:[block copy]];
    
    [self prepareToCheck];
    
}


- (void)monitorNetworkAccessibleStateWithCompletionBlock:(void (^)(ZYNetworkAccessibleState))block {
    
    self.networkAccessibleStateDidUpdateNotifier = block;
    
}


- (ZYNetworkAccessibleState)currentState {
    return _previousState;
}

#pragma mark - NSNotification

- (void)applicationWillResignActive {
    
    [self cancelPreparingCheck];
    
    [self hideNetworkRestrictedAlert];
}

- (void)applicationDidBecomeActive {
    
    [self prepareToCheck];
}

#pragma mark - Private

- (void)prepareToCheck {
    
    if (self.preparingCheck) {
        return;
    }
    self.preparingCheck = YES;
    [self performSelector:@selector(startCheck) withObject:nil afterDelay:1 inModes:@[NSRunLoopCommonModes]];
}

- (void)cancelPreparingCheck {
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    self.preparingCheck = NO;
}



- (void)startCheck {
    
    self.preparingCheck = NO;
    
    if ([UIDevice currentDevice].systemVersion.floatValue < 10.0) {
        /* iOS 10 以下 */
        [self notiWithAccessibleState:ZYNetworkAccessible];
    }
    
    CTCellularDataRestrictedState state = _cellularData.restrictedState;
    
    switch (state) {
        case kCTCellularDataRestricted: {// 系统 API 返回 无蜂窝数据访问权限
            
            // 这里可能有两种情况:
            //情况1：用户选择了： 仅WLAN
            //情况2：用户选择了： 不允许 WLAN 和 蜂窝数据
            
            ZYNetworkType type = [self currentNetworkType];
            
            
            if (type == ZYNetworkTypeCellularData) {
                /* 当前仅启用了蜂窝数据，没有 Wi-Fi 无法继续监测是那种情况 */
                
                [self notiWithAccessibleState:ZYNetworkRestricted];
                
            } else if (type == ZYNetworkTypeWiFi){
                
                /* 当前启用了 Wi-Fi ，可以通过简单测试 Wi-Fi 的连通性来判断用户选择了那种情况（不一定准确）*/
                
                [self checkWiFiReachable:^(BOOL isReachable) {
                    if (!isReachable) { // 可能是 不允许 WLAN 和 蜂窝数据
                        [self notiWithAccessibleState:ZYNetworkRestricted];
                    } else { // 可能是 仅WLAN
                        [self notiWithAccessibleState:ZYNetworkAccessible];
                    }
                }];
                
            } else {   // 可能开了飞行模式，无法判断
                [self notiWithAccessibleState:ZYNetworkUnknown];
            }
            break;
        }
        case kCTCellularDataNotRestricted: // 系统 API 访问有有蜂窝数据访问权限，那就必定有 Wi-Fi 数据访问权限
            [self notiWithAccessibleState:ZYNetworkAccessible];
            break;
        case kCTCellularDataRestrictedStateUnknown:
            [self notiWithAccessibleState:ZYNetworkUnknown];
            break;
        default:
            break;
    };
}


/**
 判断当前网络类型

 @return
 ZYNetworkTypeWiFi => 可能仅有 Wi-Fi，或者同时开启了 Wi-Fi 和 蜂窝数据
 ZYNetworkTypeCellularData => 只有蜂窝数据
 ZYNetworkTypeWiFi         => 飞行模式或关闭了 Wi-Fi 和 蜂窝数据
 */
- (ZYNetworkType)currentNetworkType {
    if ([self isWiFiEnable]) {
        return ZYNetworkTypeWiFi;
    } else if ([self isCellularDataEnable]) {
        return ZYNetworkTypeCellularData;
    } else {
        return ZYNetworkTypeOffline;
    }
}

/**
 判断用户是否连接到 Wi-Fi
 */
- (BOOL)isWiFiEnable {
    NSArray *interfaces = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
    if (!interfaces) {
        return NO;
    }
    NSDictionary *info = nil;
    for (NSString *ifnam in interfaces) {
        info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info && [info count]) { break; }
    }
    return (info != nil);
}

/**
 判断用户是否有蜂窝数据
 */
- (BOOL)isCellularDataEnable {
    NSInteger type = 0;
    
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        UIView *statusBar = [app valueForKeyPath:@"statusBar"];
        
        BOOL isModernStatusBar = [statusBar isKindOfClass:NSClassFromString(@"UIStatusBar_Modern")];
        
        if (isModernStatusBar) { // 在 iPhone X 上 statusBar 属于 UIStatusBar_Modern ，需要特殊处理
            type = [[statusBar valueForKeyPath:@"statusBar.currentData.cellularEntry.type"] integerValue];
            
            // type == 0  => 没有开启蜂窝数据
            // type == 3  => 2G
            // type == 3  => 4G
        } else { // 传统的 statusBar
            NSArray *children = [[statusBar valueForKeyPath:@"foregroundView"] subviews];
            for (id child in children) {
                if ([child isKindOfClass:[NSClassFromString(@"UIStatusBarDataNetworkItemView") class]]) {
                    type = [[child valueForKeyPath:@"dataNetworkType"] intValue];
                    
                    // type == 1  => 2G
                    // type == 2  => 3G
                    // type == 3  => 4G
                    // type == 4  => LTE
                    // type == 5  => Wi-Fi
                }
            }
        }
    } @catch (NSException *exception) {
        
    }
    
    return type != 0;
}



- (void)notiWithAccessibleState:(ZYNetworkAccessibleState)state {
    
    
    
    if (state == ZYNetworkRestricted) {
        [self showNetworkRestrictedAlert];
    } else {
         [self hideNetworkRestrictedAlert];
    }
    
    if (state != self.previousState) {
        self.previousState = state;
        
    }
    
    if (self.networkAccessibleStateDidUpdateNotifier) {
        self.networkAccessibleStateDidUpdateNotifier(state);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ZYNetworkAccessibityChangedNotification object:nil];
    
    for (NetworkAccessibleStateNotifier block in self.checkingCallbacks) {
        block(state);
    }
    
    [self.checkingCallbacks removeAllObjects];
}



/**
 检测是能能通过 Wi-Fi 访问数据（这里并不是检测连通性，不能拿来判断网络是否真正连接成功）
 */
- (void)checkWiFiReachable:(void(^)(BOOL isReachable))block {
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "223.5.5.5");
        SCNetworkReachabilityFlags flags;
        BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
        CFRelease(reachability);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                return block(NO);
            }
            BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
            BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
            BOOL isNetworkReachable = (isReachable && !needsConnection);
            
            if (!isNetworkReachable) {
                return block(NO);
            }  else {
                return block(YES);
            }
        });

    });

}

- (void)showNetworkRestrictedAlert {
    if (self.alertController.presentingViewController == nil && ![self.alertController isBeingPresented]) {
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:self.alertController animated:YES completion:nil];
    }

}

- (void)hideNetworkRestrictedAlert {
    [_alertController dismissViewControllerAnimated:YES completion:nil];
}

- (UIAlertController *)alertController {
    if (!_alertController) {
        
        _alertController = [UIAlertController alertControllerWithTitle:@"网络连接失败" message:@"检测到网络权限可能未开启，您可以在“设置”中检查蜂窝移动网络" preferredStyle:UIAlertControllerStyleAlert];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self hideNetworkRestrictedAlert];
        }]];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
                [[UIApplication sharedApplication] openURL:settingsURL];
            }
        }]];
        
        

        
    }
    return _alertController;
}



@end
