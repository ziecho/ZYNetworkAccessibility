# ZYNetworkAccessibility


[Blog 介绍](http://ziecho.com/post/ios/ios-wang-luo-quan-xian-bei-guan-bi-jian-ce)


##背景

一直都有用户反馈无法正常联网的问题，经过定位，发现很大一部分用户是因为网络权限被系统关闭，经过资料搜集和排除发现根本原因是：

1. 第一次打开 app 不能访问网络，无任何提示
2. 第一次打开 app 直接提示「已为“XXX”关闭网络」
3. 第一次打开 app ，用户点错了选择了「不允许」或「WLAN」

对于第 1 种情况，出现在 iOS 10 比较多，一旦出现后系统设置里也找不到「无线数据」这一配置选项，随着 iOS 的更新，貌似被 Apple 修复了，GitHub 上面有 [ZIKCellularAuthorization](https://github.com/Zuikyo/ZIKCellularAuthorization) 其进行分析和提出一种解决方案，强制让系统弹出那个询问框。

但是第 2、3种情况现在 iOS 12 还经常有发生，对于这种情况，ZYNetworkAccessibility 提供了检测帮忙开发者引导用户打开网络权限。


## 用法

1、将 ZYNetworkAccessibility.h 和 ZYNetworkAccessibility.m 添加到项目中，在合适的时机，比如 didFinishLaunchingWithOptions 开启，ZYNetworkAccessibility：
```objc
[ZYNetworkAccessibility start];
```
2、监听 ZYNetworkAccessibilityChangedNotification 并处理通知

```objc
[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:ZYNetworkAccessibilityChangedNotification object:nil];
```

```objc
- (void)networkChanged:(NSNotification *)notification {
    
    ZYNetworkAccessibleState state = ZYNetworkAccessibility.currentState;

    if (state == ZYNetworkRestricted) {
        NSLog(@"网络权限被关闭");
    }
}
```

另外还实现了自动提醒用户打开权限，如果你需要，请打开

```objc
[ZYNetworkAccessibility setAlertEnable:YES];
```






