# ZYNetworkAccessibity

[Blog 介绍](http://ziecho.com/post/ios/ios-wang-luo-quan-xian-bei-guan-bi-jian-ce)


##背景

 iOS 10 发布之后，一直都有用户反馈无法正常联网的问题，经过定位，发现很大一部分用户是因为网络权限被系统关闭，经过资料搜集和排除发现根本原因是 iOS 10 有一个系统 BUG： 正常情况下 App 在第一次安装时，第一次联网操作会弹出一个授权框，提示“是否允许 App 访问数据？”，而在部分国行 iOS 10 候系统并不会弹出授权框，导致 App 无法联网, 这个系统级 BUG 出现时，app 无法正常联网操作。

网络上搜集的资料大多数提到了用 CTCellularData 的 cellularDataRestrictionDidUpdateNotifier 方法去判断网络权限关闭，但这样判断会有不完善的情况（下文提到），GitHub 上面有 [ZIKCellularAuthorization](https://github.com/Zuikyo/ZIKCellularAuthorization) 对其进行分析和提出一种解决方案，但是调用到了私有 API 可能会影响上架，所以在项目并没有采用，

## CTCellularData 存在的局限性

CoreTelephony 里的 CTCellularData 可以用来监测 app 的蜂窝网络权限，其定义如下：

```objc
typedef NS_ENUM(NSUInteger, CTCellularDataRestrictedState) {
	kCTCellularDataRestrictedStateUnknown, 
	kCTCellularDataRestricted,            
	kCTCellularDataNotRestricted          
};
```

通过注册 cellularDataRestrictionDidUpdateNotifier 回调可以并判断其 state 可以判断蜂窝数据的权限

```objc
CTCellularData *cellularData = [[CTCellularData alloc] init];
    cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState restrictedState) {
           ...
        }
    };
```

系统设置里 有三种选项分别对应：
| 系统选项 | CTCellularDataRestrictedState | 
| ------ | ------ |
| 关闭 | kCTCellularDataRestricted | 
| WLAN | kCTCellularDataRestricted |
| WALN 与蜂窝移动网 | kCTCellularDataNotRestricted |

实测发现：
1、若用户此时用蜂窝数据上网，但在「允许“XXX”使用的数据」，选择了「WLAN」 或 「关闭」，回调拿到的值是 
kCTCellularDataRestricted ，此时我们可以确定是因为权限问题导致用户不能访问，应该去提示用户打开网络权限。

2、若用户此时用 Wi-Fi 上网，但在「允许“XXX”使用的数据」设置中选择了 「关闭」，我们拿到的值是 kCTCellularDataRestricted ，这种个情况下同样需要提示用户打开网络权限。

2、若用户此时用 Wi-Fi 上网，但在「允许“XXX”使用的数据」设置中选择了 「WLAN」，我们拿到的值是 kCTCellularDataRestricted ，但是此时用户是有网络访问权限的，此时不应该去提示用户。

## 判断思路

所以重点就是判断出第2、3种情况，我们可以通过一些方法来区分用户当前用的是蜂窝数据还是 Wi-Fi，然后再做进一步判断：

1、当返回了 kCTCellularDataRestricted ，且用户用的是蜂窝数据，提示用户打开网络权限。
2、当返回了 kCTCellularDataRestricted ，且用户用的是 Wi-Fi， 去检测一下网络连通性，若网络不连通，用户可能选择了「关闭」，弹出提示。

## 实现细节
### 判断当前网络类型

思路是先去判断有没有开启 Wi-Fi，如果有用户一定是通过 Wi-Fi 上网，若没有再去判断是否有蜂窝数据，这个顺序不能反过来，因为在蜂窝数据和 Wi-Fi 的情况下同时开启的情况下，系统会优先用 Wi-Fi 上网。

```objc
- (ZYNetworkType)currentNetworkType {
    if ([self isWiFiEnable]) {
        return ZYNetworkTypeWiFi;
    } else if ([self isCellularDataEnable]) {
        return ZYNetworkTypeCellularData;
    } else {
        return ZYNetworkTypeOffline;
    }
}
```

### 判断是否连接到 Wi-Fi

判断 Wi-Fi 的方法比较简单，导入  <SystemConfiguration/CaptiveNetwork.h>  并使用下面方法判断即可

```objc
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

```
### 判断是否开启了蜂窝数据

由于在网络权限拒绝的情况下，我们唯一比较有效的方法是通过状态栏去判断，这个判断方法在网上可以找到，但是 在 iPhone X 会出现 crash 的情况，我针对 iPhone X 做了补充和适配。

```objc
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
```

### 检测 Wi-Fi 网络连通性

前面提到，在 Wi-Fi 下，我们需要实际去判断网络是否连通，通过测试，发现使用 SCNetworkReachability 是比较合的，注意，这里并不是检测连通性，不能拿来判断网络是否真正连接成功，但是对于我们这个判断场景是够用的。

```objc
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
```

### 整体判断代码
```objc
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
```

## ZYNetworkAccessibity

GitHub ： [ZYNetworkAccessibity](https://github.com/ziecho/ZYNetworkAccessibity)

我已经把上面的方法做了封装，将 ZYNetworkAccessibity.h 和 ZYNetworkAccessibity.m 拖项目中，监听 ZYNetworkAccessibityChangedNotification 通知即可

```objc
[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:ZYNetworkAccessibityChangedNotification object:nil];
```
然后处理通知

```objc
- (void)networkChanged:(NSNotification *)notification {
    
    ZYNetworkAccessibleState state = ZYNetworkAccessibity.currentState;

    if (state == ZYNetworkRestricted) {
        NSLog(@"网络权限被关闭");
    }
}
```

另外还实现了自动提醒用户打开权限，如果你需要，请打开

```objc
[ZYNetworkAccessibity setAlertEnable:YES];
```





