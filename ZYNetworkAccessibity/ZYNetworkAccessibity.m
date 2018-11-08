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

#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>

// ifaddrs
#import <ifaddrs.h>

// inet
#import <arpa/inet.h>


NSString * const ZYNetworkAccessibityChangedNotification = @"ZYNetworkAccessibityChangedNotification";

typedef NS_ENUM(NSInteger, ZYNetworkType) {
    ZYNetworkTypeUnknown ,
    ZYNetworkTypeOffline ,
    ZYNetworkTypeWiFi    ,
    ZYNetworkTypeCellularData ,
};

@interface ZYNetworkAccessibity(){
    SCNetworkReachabilityRef _reachabilityRef;
    CTCellularData *_cellularData;
    NSMutableArray *_becomeActiveCallbacks;
    ZYNetworkAccessibleState _previousState;
    UIAlertController *_alertController;
    BOOL _automaticallyAlert;
    NetworkAccessibleStateNotifier _networkAccessibleStateDidUpdateNotifier;
    BOOL _checkActiveLaterWhenDidBecomeActive;
    BOOL _checkingActiveLater;
}


@end

@interface ZYNetworkAccessibity()
@end


@implementation ZYNetworkAccessibity


#pragma mark - Public

+ (void)start {
    [[self sharedInstance] setupNetworkAccessibity];
}

+ (void)stop {
    [[self sharedInstance] cleanNetworkAccessibity];
}

+ (void)setAlertEnable:(BOOL)setAlertEnable {
    [self sharedInstance]->_automaticallyAlert = setAlertEnable;
}


+ (void)setStateDidUpdateNotifier:(void (^)(ZYNetworkAccessibleState))block {
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
    });
    return instance;
}


- (void)setNetworkAccessibleStateDidUpdateNotifier:(NetworkAccessibleStateNotifier)networkAccessibleStateDidUpdateNotifier {
    _networkAccessibleStateDidUpdateNotifier = [networkAccessibleStateDidUpdateNotifier copy];
    [self startCheck];
}



- (void)monitorNetworkAccessibleStateWithCompletionBlock:(void (^)(ZYNetworkAccessibleState))block {
    _networkAccessibleStateDidUpdateNotifier = [block copy];
}

- (ZYNetworkAccessibleState)currentState {
    return _previousState;
}

#pragma mark - Life cycle

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    if (self = [super init]) {
        
    }
    return self;
}

#pragma mark - NSNotification

- (void)setupNetworkAccessibity {
    
    if (_reachabilityRef || _cellularData) {
        return;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    _reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, "223.5.5.5");
    // 此句会触发系统弹出权限询问框
    SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    

    _becomeActiveCallbacks = [NSMutableArray array];
    
    BOOL firstRun = ({
        static NSString * RUN_FLAG = @"ZYNetworkAccessibityRunFlag";
        BOOL value = [[NSUserDefaults standardUserDefaults] boolForKey:RUN_FLAG];
        if (!value) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RUN_FLAG];
        }
        !value;
    });
    
    dispatch_block_t startNotifier = ^{
        [self startReachabilityNotifier];
        
        [self startCellularDataNotifier];
    };
    
    if (firstRun) {
        // 第一次运行系统会弹框，需要延迟一下在判断，否则会拿到不准确的结果
        // 表现为：ReachabilityNotifier 有一定概率拿到的结果是可以访问, CellularDataNotifier 拿到的是拒绝
        // 这里延时 3 秒再检测是因为某些情况下，弹框存在较长的延时。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self waitActive:^{
                startNotifier();
            }];
        });
    } else {
        startNotifier();
    }
    
    
}

- (void)cleanNetworkAccessibity {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _cellularData.cellularDataRestrictionDidUpdateNotifier = nil;
    _cellularData = nil;
    
    SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    _reachabilityRef = nil;
    
    [self cancelEnsureActive];
    [self hideNetworkRestrictedAlert];
    
    [_becomeActiveCallbacks removeAllObjects];
    _becomeActiveCallbacks = nil;
    
    _previousState = ZYNetworkChecking;
    
    _checkActiveLaterWhenDidBecomeActive = NO;
    _checkingActiveLater = NO;
    
}


- (void)applicationWillResignActive {
    [self hideNetworkRestrictedAlert];
    
    if (_checkingActiveLater) {
        [self cancelEnsureActive];
        _checkActiveLaterWhenDidBecomeActive = YES;
    }
}

- (void)applicationDidBecomeActive {
    
    if (_checkActiveLaterWhenDidBecomeActive) {
        [self checkActiveLater];
        _checkActiveLaterWhenDidBecomeActive = NO;
    }
}


#pragma mark - Active Checker

// 如果当前 app 是非可响应状态（一般是启动的时候），则等到 app 激活且保持一秒以上，再回调
// 因为启动完成后，2 秒内可能会再次弹出「是否允许 XXX 使用网络」，此时的 applicationState 是 UIApplicationStateInactive）

- (void)waitActive:(dispatch_block_t)block {
    [_becomeActiveCallbacks addObject:[block copy]];
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
       _checkActiveLaterWhenDidBecomeActive = YES;
    } else {
        [self checkActiveLater];
    }
}

- (void)checkActiveLater {
    _checkingActiveLater = YES;
    [self performSelector:@selector(ensureActive) withObject:nil afterDelay:2 inModes:@[NSRunLoopCommonModes]];
}

- (void)ensureActive {
    _checkingActiveLater = NO;
    for (dispatch_block_t block in _becomeActiveCallbacks) {
        block();
    }
    [_becomeActiveCallbacks removeAllObjects];
}

- (void)cancelEnsureActive {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ensureActive) object:nil];
}


#pragma mark - Reachability

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
    ZYNetworkAccessibity *networkAccessibity = (__bridge ZYNetworkAccessibity *)info;
    if (![networkAccessibity isKindOfClass: [ZYNetworkAccessibity class]]) {
        return;
    }
    [networkAccessibity startCheck];
}

// 监听用户从 Wi-Fi 切换到 蜂窝数据，或者从蜂窝数据切换到 Wi-Fi，另外当从授权到未授权，或者未授权到授权也会调用该方法
- (void)startReachabilityNotifier {
    SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    if (SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context)) {
        SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
}

- (void)startCellularDataNotifier {
    __weak __typeof(self)weakSelf = self;
    self->_cellularData = [[CTCellularData alloc] init];
    self->_cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startCheck];
        });
    };
}

- (BOOL)currentReachable {
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}


#pragma mark - Check Accessibity

- (void)startCheck {
    if ([UIDevice currentDevice].systemVersion.floatValue < 10.0 || [self currentReachable]) {
        
        /* iOS 10 以下 不够用检测默认通过 **/
        
        /* 先用 currentReachable 判断，若返回的为 YES 则说明：
         1. 用户选择了 「WALN 与蜂窝移动网」并处于其中一种网络环境下。
         2. 用户选择了 「WALN」并处于 WALN 网络环境下。
         
         此时是有网络访问权限的，直接返回 ZYNetworkAccessible
         **/
        
        [self notiWithAccessibleState:ZYNetworkAccessible];
        return;
    }
    
    CTCellularDataRestrictedState state = _cellularData.restrictedState;
    
    switch (state) {
        case kCTCellularDataRestricted: {// 系统 API 返回 无蜂窝数据访问权限
            
            [self getCurrentNetworkType:^(ZYNetworkType type) {
                /*  若用户是通过蜂窝数据 或 WLAN 上网，走到这里来 说明权限被关闭**/
                
                if (type == ZYNetworkTypeCellularData || type == ZYNetworkTypeWiFi) {
                    [self notiWithAccessibleState:ZYNetworkRestricted];
                } else {  // 可能开了飞行模式，无法判断
                    [self notiWithAccessibleState:ZYNetworkUnknown];
                }
            }];
            
            break;
        }
        case kCTCellularDataNotRestricted: // 系统 API 访问有有蜂窝数据访问权限，那就必定有 Wi-Fi 数据访问权限
            [self notiWithAccessibleState:ZYNetworkAccessible];
            break;
        case kCTCellularDataRestrictedStateUnknown: {
            // CTCellularData 刚开始初始化的时候，可能会拿到 kCTCellularDataRestrictedStateUnknown 延迟一下再试就好了
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self startCheck];
            });
            break;
        }
        default:
            break;
    };
}


- (void)getCurrentNetworkType:(void(^)(ZYNetworkType))block {
    if ([self isWiFiEnable]) {
        return block(ZYNetworkTypeWiFi);
    }
    ZYNetworkType type = [self getNetworkTypeFromStatusBar];
    if (type == ZYNetworkTypeWiFi) { // 这时候从状态栏拿到的是 Wi-Fi 说明状态栏没有刷新，延迟一会再获取
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self getCurrentNetworkType:block];
        });
    } else {
        block(type);
    }
}

- (ZYNetworkType)getNetworkTypeFromStatusBar {
    NSInteger type = 0;
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        UIView *statusBar = [app valueForKeyPath:@"statusBar"];
        
        if (statusBar == nil ){
            return ZYNetworkTypeUnknown;
        }
        
        BOOL isModernStatusBar = [statusBar isKindOfClass:NSClassFromString(@"UIStatusBar_Modern")];
        
        if (isModernStatusBar) { // 在 iPhone X 上 statusBar 属于 UIStatusBar_Modern ，需要特殊处理
            id currentData = [statusBar valueForKeyPath:@"statusBar.currentData"];
            BOOL wifiEnable = [[currentData valueForKeyPath:@"_wifiEntry.isEnabled"] boolValue];
            
            // 这里不能用 _cellularEntry.isEnabled 来判断，该值即使关闭仍然有是 YES
            
            BOOL cellularEnable = [[currentData valueForKeyPath:@"_cellularEntry.type"] boolValue];
            return  wifiEnable     ? ZYNetworkTypeWiFi :
                    cellularEnable ? ZYNetworkTypeCellularData : ZYNetworkTypeOffline;
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
            return type == 0 ? ZYNetworkTypeOffline :
                   type == 5 ? ZYNetworkTypeWiFi    : ZYNetworkTypeCellularData;
        }
    } @catch (NSException *exception) {
        
    }
    return 0;
}


/**
 判断用户是否连接到 Wi-Fi
 */
- (BOOL)isWiFiEnable {
    return [self wiFiIPAddress].length > 0;
}

- (NSString *)wiFiIPAddress {
    @try {
        NSString *ipAddress;
        struct ifaddrs *interfaces;
        struct ifaddrs *temp;
        int Status = 0;
        Status = getifaddrs(&interfaces);
        if (Status == 0) {
            temp = interfaces;
            while(temp != NULL) {
                if(temp->ifa_addr->sa_family == AF_INET) {
                    if([[NSString stringWithUTF8String:temp->ifa_name] isEqualToString:@"en0"]) {
                        ipAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                    }
                }
                temp = temp->ifa_next;
            }
        }
        
        freeifaddrs(interfaces);
        
        if (ipAddress == nil || ipAddress.length <= 0) {
            return nil;
        }
        return ipAddress;
    }
    @catch (NSException *exception) {
        return nil;
    }
}

#pragma mark - Callback

- (void)notiWithAccessibleState:(ZYNetworkAccessibleState)state {
    if (_automaticallyAlert) {
        if (state == ZYNetworkRestricted) {
                [self showNetworkRestrictedAlert];
        } else {
            [self hideNetworkRestrictedAlert];
        }
    }
    
    if (state != _previousState) {
        _previousState = state;
        
        if (_networkAccessibleStateDidUpdateNotifier) {
            _networkAccessibleStateDidUpdateNotifier(state);
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:ZYNetworkAccessibityChangedNotification object:nil];
        
    }
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
