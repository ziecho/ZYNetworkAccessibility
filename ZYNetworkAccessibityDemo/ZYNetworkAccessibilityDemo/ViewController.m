//
//  ViewController.m
//  ZYNetworkAccessibilityDemo
//
//  Created by zie on 20/7/18.
//  Copyright © 2018年 zie. All rights reserved.
//

#import "ViewController.h"
#import "ZYNetworkAccessibility.h"

#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCellularData.h>
#import <SystemConfiguration/SystemConfiguration.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *label;

@end

@implementation ViewController

static NSString * NSStringFromZYNetworkAccessibleState(ZYNetworkAccessibleState state) {
    return state == ZYNetworkChecking   ? @"ZYNetworkChecking"   :
           state == ZYNetworkUnknown    ? @"ZYNetworkUnknown"    :
           state == ZYNetworkAccessible ? @"ZYNetworkAccessible" :
           state == ZYNetworkRestricted ? @"ZYNetworkRestricted" : nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.label.text = NSStringFromZYNetworkAccessibleState(ZYNetworkAccessibility.currentState);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:ZYNetworkAccessibilityChangedNotification object:nil];
}

- (void)networkChanged:(NSNotification *)notification {
    
    ZYNetworkAccessibleState state = ZYNetworkAccessibility.currentState;
    
    self.label.text = NSStringFromZYNetworkAccessibleState(state);
    
    NSLog(@"networkChanged : %@",NSStringFromZYNetworkAccessibleState(state));
}


@end
