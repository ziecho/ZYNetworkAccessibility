# ZYNetworkAccessibity


[Blog 介绍](http://ziecho.com/post/ios/ios-wang-luo-quan-xian-bei-guan-bi-jian-ce)


##背景

 iOS 10 发布之后，一直都有用户反馈无法正常联网的问题，经过定位，发现很大一部分用户是因为网络权限被系统关闭，经过资料搜集和排除发现根本原因是 iOS 10 有一个系统 BUG： 正常情况下 App 在第一次安装时，第一次联网操作会弹出一个授权框，提示“是否允许 App 访问数据？”，而在部分国行 iOS 10 候系统并不会弹出授权框，导致 App 无法联网, 这个系统级 BUG 出现时，app 无法正常联网操作故此有了 ZYNetworkAccessibity

## 用法

将 ZYNetworkAccessibity.h 和 ZYNetworkAccessibity.m 拖项目中，监听 ZYNetworkAccessibityChangedNotification 通知即可

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






