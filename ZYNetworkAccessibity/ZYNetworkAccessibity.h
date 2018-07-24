//
//  ZYNetworkAccessibity.h
//
//  Created by zie on 16/11/17.
//  Copyright © 2017年 zie. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const ZYNetworkAccessibityChangedNotification;

typedef NS_ENUM(NSUInteger, ZYNetworkAccessibleState) {
    ZYNetworkChecking  = 0,
    ZYNetworkUnknown     ,
    ZYNetworkAccessible  ,
    ZYNetworkRestricted  ,
};

typedef void (^NetworkAccessibleStateNotifier)(ZYNetworkAccessibleState state);

@interface ZYNetworkAccessibity : NSObject

/**
 开启 ZYNetworkAccessibity
 */
+ (void)start;

/**
 停止 ZYNetworkAccessibity
 */
+ (void)stop;

/**
 当判断网络状态为 ZYNetworkRestricted 时，提示用户开启网络权限
 */

+ (void)setAlertEnable:(BOOL)setAlertEnable;

/**
 监控网络权限变化（block 方式），等网络权限发生变化时回调。
 */

+ (void)monitor:(void (^)(ZYNetworkAccessibleState))block;

/**
 检查网络状态，若弹出系统级别的 Alert，用户未处理则会等到用户处理完毕后才回调，该方法只会回调一次。
 */

+ (void)checkState:(void (^)(ZYNetworkAccessibleState))block;

/**
 返回的是最近一次的网络状态检查结果，若距离上一次检测结果短时间内网络授权状态发生变化，该值可能会不准确，
 想获得更为准确的结果，请调用 checkState 这个异步方法。
 */
+ (ZYNetworkAccessibleState)currentState;

@end
