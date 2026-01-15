#import "TelinkOtaWrapper.h"
#import "Bluetooth.h"
#import "Device.h"
#import "DownloadFiles.h"

@interface TelinkOtaWrapper ()
@property (nonatomic, strong) DownloadFiles *downloadManager;
@property (nonatomic, strong, nullable) NSString *currentTargetDeviceId;
@property (nonatomic, assign) BOOL isOtaInProgress;
@end

@implementation TelinkOtaWrapper

+ (nonnull instancetype)sharedInstance {
    static TelinkOtaWrapper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _downloadManager = [[DownloadFiles alloc] init];
        _isOtaInProgress = NO;
        NSLog(@"TelinkOtaWrapper: 初始化完成");
    }
    return self;
}

- (void)setConnectedDevice:(NSString *)deviceId {
    self.currentTargetDeviceId = deviceId;
    NSLog(@"TelinkOtaWrapper: 设置目标设备: %@", deviceId);
}

- (BOOL)isDeviceConnected {
    Bluetooth *btManager = [Bluetooth shareCentralManager];
    // 简化连接检查逻辑
    BOOL connected = btManager.ARConnect && 
                    btManager.currentDevice &&
                    btManager.currentDevice.peripheral.state == CBPeripheralStateConnected;
    
    NSLog(@"TelinkOtaWrapper: 设备连接状态: %@", connected ? @"已连接" : @"未连接");
    return connected;
}

- (void)startOtaWithFilePath:(NSString *)filePath
                readInterval:(NSInteger)readInterval
                progressCallback:(void (^)(float progress))progressCallback
                completionCallback:(void (^)(BOOL success, NSString * _Nullable errorMessage))completionCallback {

    NSLog(@"TelinkOtaWrapper: 开始OTA - 文件: %@, 速度: %ld", filePath, (long)readInterval);
    
    // 检查是否已有OTA在进行
    if (self.isOtaInProgress) {
        NSLog(@"TelinkOtaWrapper: 错误 - 已有OTA在进行中");
        if (completionCallback) {
            completionCallback(NO, @"已有OTA在进行中");
        }
        return;
    }
    
    // 验证文件
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"TelinkOtaWrapper: 错误 - 文件不存在");
        if (completionCallback) {
            completionCallback(NO, @"固件文件不存在");
        }
        return;
    }
    
    // 检查蓝牙状态
    Bluetooth *btManager = [Bluetooth shareCentralManager];
    if (btManager.centralManager.state != CBManagerStatePoweredOn) {
        NSLog(@"TelinkOtaWrapper: 错误 - 蓝牙未开启");
        if (completionCallback) {
            completionCallback(NO, @"蓝牙未开启");
        }
        return;
    }
    
    self.isOtaInProgress = YES;
    
    // 设置完成回调包装器，确保状态清理
    __weak typeof(self) weakSelf = self;
    void (^wrappedCompletionCallback)(BOOL, NSString *) = ^(BOOL success, NSString *errorMessage) {
        NSLog(@"TelinkOtaWrapper: OTA完成 - 成功: %@, 错误: %@", success ? @"是" : @"否", errorMessage ?: @"无");
        weakSelf.isOtaInProgress = NO;
        if (completionCallback) {
            completionCallback(success, errorMessage);
        }
    };
    
    // 简化逻辑：直接尝试开始OTA，让底层处理连接
    [self tryStartOta:filePath 
         readInterval:readInterval 
        progressCallback:progressCallback 
        completionCallback:wrappedCompletionCallback];
}

- (void)tryStartOta:(NSString *)filePath
       readInterval:(NSInteger)readInterval
      progressCallback:(void (^)(float))progressCallback
      completionCallback:(void (^)(BOOL, NSString *))completionCallback {
    
    Bluetooth *btManager = [Bluetooth shareCentralManager];
    
    // 如果没有设置目标设备，尝试使用当前连接的设备
    if (!self.currentTargetDeviceId && btManager.currentDevice) {
        self.currentTargetDeviceId = btManager.currentDevice.peripheral.identifier.UUIDString;
        NSLog(@"TelinkOtaWrapper: 使用当前连接的设备: %@", self.currentTargetDeviceId);
    }
    
    // 检查设备是否已连接
    if ([self isDeviceConnected]) {
        NSLog(@"TelinkOtaWrapper: 设备已连接，直接开始OTA");
        [self.downloadManager startOtaWithFilePath:filePath
                                      readInterval:readInterval
                                     progressBlock:progressCallback
                                     completeBlock:completionCallback];
    } else if (self.currentTargetDeviceId) {
        // 尝试连接设备
        NSLog(@"TelinkOtaWrapper: 设备未连接，尝试连接: %@", self.currentTargetDeviceId);
        
        NSUUID *targetUUID = [[NSUUID alloc] initWithUUIDString:self.currentTargetDeviceId];
        NSArray<CBPeripheral *> *peripherals = [btManager.centralManager retrievePeripheralsWithIdentifiers:@[targetUUID]];
        
        if (peripherals.count > 0) {
            // 设置简单的连接回调
            __weak typeof(self) weakSelf = self;
            [btManager setUpdatePeripheralStateBlock:^(ARDeviceStateType state, Device *dev) {
                if (state == ARDeviceStateTypeDiscovereCharacteristic) {
                    NSLog(@"TelinkOtaWrapper: 设备特征发现完成，开始OTA");
                    [weakSelf.downloadManager startOtaWithFilePath:filePath
                                                      readInterval:readInterval
                                                     progressBlock:progressCallback
                                                     completeBlock:completionCallback];
                    // 清除回调，避免重复触发
                    [btManager setUpdatePeripheralStateBlock:nil];
                } else if (state == ARDeviceStateTypeFailure || state == ARDeviceStateTypeDisConnected) {
                    NSLog(@"TelinkOtaWrapper: 连接失败");
                    if (completionCallback) {
                        completionCallback(NO, @"设备连接失败");
                    }
                    weakSelf.isOtaInProgress = NO;
                    [btManager setUpdatePeripheralStateBlock:nil];
                }
            }];
            
            // 开始连接
            [btManager connectPeripheral:peripherals.firstObject];
        } else {
            NSLog(@"TelinkOtaWrapper: 无法找到设备");
            if (completionCallback) {
                completionCallback(NO, @"无法找到指定设备");
            }
            self.isOtaInProgress = NO;
        }
    } else {
        NSLog(@"TelinkOtaWrapper: 没有指定目标设备");
        if (completionCallback) {
            completionCallback(NO, @"未指定目标设备");
        }
        self.isOtaInProgress = NO;
    }
}

- (void)cancelOta {
    NSLog(@"TelinkOtaWrapper: 取消OTA");
    self.isOtaInProgress = NO;
    [self.downloadManager stopSendDataPack];
    
    // 清理蓝牙回调
    Bluetooth *btManager = [Bluetooth shareCentralManager];
    [btManager setUpdatePeripheralStateBlock:nil];
    [btManager setOtaUpdataBlock:nil];
}

@end
