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
  通过 block 方式监控网络权限变化。
 */
+ (void)setStateDidUpdateNotifier:(void (^)(ZYNetworkAccessibleState))block;

/**
 返回的是最近一次的网络状态检查结果，若距离上一次检测结果短时间内网络授权状态发生变化，该值可能会不准确。
 */
+ (ZYNetworkAccessibleState)currentState;

@end
