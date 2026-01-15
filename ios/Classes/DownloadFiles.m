#define kInputNull (@"input nil,and it'll select the default file")
#define kDownloadFailure (@"download the file failure,please check you network condition, and try again")
#define kDownloadFailWithContent (@"download the file failure,please check you network condition and input content, and try again")
#define kDownloadFailWithAccess (@"network isn't access to,please check you network condition, and try again")
#define kFileExist (@"the file is exist, download and update local data?")
#define kDownloadSuccess (@"download success")
#define kCreatFileError (@"creat the file failure")
#define kSelectDefaultFile (@"it'll select default file")
#define kNoFileSelected (@"no file to be selected, please download one first")
#define kUpdataLocalFileFail (@"delete local file fail")
#define kPerPackageRead (16*4)
#define kPerIndexWrite (4)
#define kPerIntervalWrite (0.02)
#import "DownloadFiles.h"
#import "Device.h"
#import "Bluetooth.h"

static NSUInteger downloadIndex = 0;
@interface DownloadFiles ()

// 私有属性
@property (assign, nonatomic) BOOL isOnePartSent;
@property (assign, nonatomic) BOOL isStartOTA;
@property (assign, nonatomic) BOOL isSingleOTAFinish;
@property (assign, nonatomic) BOOL isOtaCompleted;
@property (strong, nonatomic) NSTimer * _Nullable otaTimer;
@property (strong, nonatomic) NSTimer * _Nullable endTimer;
@property (strong, nonatomic) NSData * _Nullable localData;
@property (assign, nonatomic) NSInteger location;
@property (assign, nonatomic) NSInteger count;

@end

@implementation DownloadFiles

// 添加初始化方法设置默认值
- (instancetype)init {
    self = [super init];
    if (self) {
        // 设置默认值
        self.otaWriteInterval = 0.01;  // 默认0.01秒
        self.otaReadInterval = 8;      // 默认8个包
    }
    return self;
}

- (void)receiveDataFailure:(NSString *)tips {
    NSLog(@"DownloadFiles: 接收数据失败: %@", tips);
    if (0==downloadIndex) {
        downloadIndex++;
        [self downloadWithPath:nil];
    } else {
        downloadIndex=0;
        if (self.downloadCompleteBlock) {
            self.downloadCompleteBlock(NO, nil, tips);
        }
    }
}

// 下载文件的方法，添加回调
- (void)downloadFileWithName:(NSString *)fileName url:(NSString *)urlString completion:(void (^)(BOOL success, NSString *filePath, NSString *errorMessage))completion {
    self.downloadCompleteBlock = completion;
    
    if (!fileName || fileName.length == 0) {
        if (self.downloadCompleteBlock) {
            self.downloadCompleteBlock(NO, nil, kInputNull);
        }
        return;
    }
    
    NSString *path;
    if ([fileName containsString:@".bin"]) {
        fileName = [fileName stringByReplacingOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, fileName.length)];
        path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:fileName];
    } else {
        fileName = [fileName stringByReplacingOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, fileName.length)];
        fileName = [NSString stringWithFormat:@"%@.bin", fileName];
        path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:fileName];
    }
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:path]) {
        // 文件存在，通过回调询问是否覆盖
        if (self.fileExistsBlock) {
            __weak typeof(self) weakSelf = self;
            self.fileExistsBlock(path, ^{
                // 用户选择更新
                NSError *error = nil;
                BOOL dele = [manager removeItemAtPath:path error:&error];
                if (dele) {
                    [weakSelf downloadWithPath:path];
                } else {
                    if (weakSelf.downloadCompleteBlock) {
                        weakSelf.downloadCompleteBlock(NO, nil, kUpdataLocalFileFail);
                    }
                }
            }, ^{
                // 用户选择取消
                if (weakSelf.downloadCompleteBlock) {
                    weakSelf.downloadCompleteBlock(NO, nil, @"Download canceled");
                }
            });
        } else {
            // 如果没有设置fileExistsBlock，则默认覆盖
            NSError *error = nil;
            BOOL dele = [manager removeItemAtPath:path error:&error];
            if (dele) {
                [self downloadWithPath:path];
            } else {
                if (self.downloadCompleteBlock) {
                    self.downloadCompleteBlock(NO, nil, kUpdataLocalFileFail);
                }
            }
        }
    } else {
        [self downloadWithPath:path];
    }
}

- (void)downloadWithPath:(NSString *)path {
    NSURL *url;
    if (0==downloadIndex) {
        url = [NSURL URLWithString:[kURLWithName(self.downloadFileName) stringByReplacingOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, kURLWithName(self.downloadFileName).length)]];
    } else {
        url = [NSURL URLWithString:[kOtherURLWithName(self.downloadFileName) stringByReplacingOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, kOtherURLWithName(self.downloadFileName).length)]];
    }
    [self sendDownloadRequest:url filePath:path];
}

- (void)sendDownloadRequest:(NSURL *)url filePath:(NSString *)path{
    __weak typeof(self) weakSelf = self;
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSFileManager *manager = [NSFileManager defaultManager];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        if (!data.length) {
            [weakSelf receiveDataFailure:kDownloadFailWithAccess];
            return;
        }
        NSData *subLenData = [data subdataWithRange:NSMakeRange(24, 4)];
        uint8_t *byte = (uint8_t *)[subLenData bytes];
        NSMutableString *lenStr = [[NSMutableString alloc] init];
        for (int i=0; i<4; i++) {
            [lenStr appendString:[NSString stringWithFormat:@"%02x",byte[3-i]]];
        }
        NSScanner *scan = [NSScanner scannerWithString:lenStr];
        uint32_t lenValue;
        [scan scanHexInt:&lenValue];
        NSHTTPURLResponse *res = (NSHTTPURLResponse *)response;
        
        if (res.expectedContentLength!=data.length||lenValue!=data.length) {
            [weakSelf receiveDataFailure:kDownloadFailure];
            return;
        }
        
        BOOL ret = [manager createFileAtPath:path contents:data attributes:nil];
        if (ret) {
            if (weakSelf.downloadCompleteBlock) {
                weakSelf.downloadCompleteBlock(YES, path, nil);
            }
        } else {
            if (weakSelf.downloadCompleteBlock) {
                weakSelf.downloadCompleteBlock(NO, nil, kCreatFileError);
            }
        }
    }];
}

// 获取OTA文件列表
- (NSArray *)listOtaFiles {
    NSMutableArray *files = [NSMutableArray array];
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSString *fileLocalPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSArray *fileNames = [manager contentsOfDirectoryAtPath:fileLocalPath error:&error];
    NSArray *bins = [[NSBundle mainBundle] pathsForResourcesOfType:@"bin" inDirectory:nil];
    
    for (NSString *path in fileNames) {
        if ([path containsString:@".bin"]) {
            [files addObject:@{
                @"name": path,
                @"path": [fileLocalPath stringByAppendingPathComponent:path],
                @"type": @"download"
            }];
        }
    }
    
    for (NSString *path in bins) {
        [files addObject:@{
            @"name": [path lastPathComponent],
            @"path": path,
            @"type": @"local"
        }];
    }
    
    return files;
}

// 删除文件
- (BOOL)deleteFile:(NSString *)filePath error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    return [manager removeItemAtPath:filePath error:error];
}

// 开始OTA方法，添加回调
- (void)startOtaWithFilePath:(NSString *)filePath 
                readInterval:(NSInteger)readInterval
              progressBlock:(void (^)(float progress))progressBlock 
              completeBlock:(void (^)(BOOL success, NSString *errorMessage))completeBlock {
    
    NSLog(@"DownloadFiles: ===== 开始新的OTA流程 =====");
    
    // 🔥 完整重置所有OTA状态，确保不受上次OTA影响
    [self resetOtaState];
    
    // 根据readInterval设置速度参数
    if (readInterval <= 0) {
        // 极速模式 - 合理的参数，避免设备缓冲区溢出
        self.otaWriteInterval = 0.001;   // 1毫秒，平衡速度和稳定性
        self.otaReadInterval = 0;        // 0表示完全不等待读取响应
        NSLog(@"DownloadFiles: 🚀 极速模式启用 - 最快传输");
    } else if (readInterval <= 12) {
        // 快速模式 - 参考Nordic DFU默认值
        self.otaWriteInterval = 0.005;   // 5毫秒
        self.otaReadInterval = readInterval;
        NSLog(@"DownloadFiles: ⚡ 快速模式 - 平衡传输");
    } else {
        // 稳定模式
        self.otaWriteInterval = 0.010;   // 10毫秒
        self.otaReadInterval = readInterval;
        NSLog(@"DownloadFiles: 🛡️ 稳定模式 - 可靠传输");
    }
    
    NSLog(@"DownloadFiles: 设置OTA速度参数 - writeInterval: %f秒, readInterval: %ld个包", 
          self.otaWriteInterval, (long)self.otaReadInterval);
    
    self.otaProgressBlock = progressBlock;
    self.otaCompleteBlock = completeBlock;
    
    // 设置蓝牙事件处理器（仅在需要时设置一次）
    [self setupBluetoothEventHandlers];
    
    if (!BLE.ARConnect) {
        if (self.otaCompleteBlock) {
            self.otaCompleteBlock(NO, @"No device connected");
        }
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    
    if (data.length) {
        //Begin OTA
        [BLE versionGet];
        [BLE startOTA];
        
        BLE.otaPackIndex = 0;
        
        self.localData = [[NSFileHandle fileHandleForReadingAtPath:filePath] readDataToEndOfFile];
        self.count = (self.localData.length % 16)?(self.localData.length/16 + 1):(self.localData.length/16);
        _isStartOTA = YES;
        
        NSLog(@"DownloadFiles: OTA文件大小: %ld字节, 数据包总数: %ld", (long)self.localData.length, (long)self.count);
        
        [self performSelector:@selector(sendDataPack) withObject:nil afterDelay:0.3];
    }
    else{
        if (self.otaCompleteBlock) {
            self.otaCompleteBlock(NO, @"No binary file be selected for OTA");
        }
    }
}

// 🔥 新增：完整重置OTA状态的方法
- (void)resetOtaState {
    NSLog(@"DownloadFiles: 重置所有OTA状态");
    
    // 停止并清理定时器
    if (self.otaTimer) {
        [self.otaTimer invalidate];
        self.otaTimer = nil;
    }
    
    // 重置所有状态标志
    self.isStartOTA = NO;
    self.isSingleOTAFinish = NO;
    self.isOnePartSent = NO;
    self.isOtaCompleted = NO;
    
    // 清理数据
    self.localData = nil;
    self.count = 0;
    self.location = 0;
    
    // 重置BLE的OTA相关状态
    BLE.otaPackIndex = 0;
    
    // 清理回调
    self.otaProgressBlock = nil;
    self.otaCompleteBlock = nil;
    
    NSLog(@"DownloadFiles: OTA状态重置完成");
}

- (void)stopSendDataPack {
    self.isSingleOTAFinish = NO;
    self.isStartOTA = NO;
    self.localData = nil;
    
    if (self.otaTimer) {
        [self.otaTimer invalidate];
        self.otaTimer = nil;
    }
    
    [BLE stopConnect];
}

- (void)sendDataPack {
    if (self.otaTimer) {
        [self.otaTimer invalidate];
        self.otaTimer = nil;
    }
    
    self.isStartOTA = YES;
    NSUInteger packLoction;
    NSUInteger packLength;
    NSUInteger length;
    if (BLE.otaPackIndex>self.count) return;
    if (BLE.currentDevice.state!=ARDeviceStateTypeDiscovereCharacteristic){
        [self stopSendDataPack];
        return;
    }
    
    if (BLE.otaPackIndex<self.count) {
        if(BLE.otaPackIndex == self.count-1){
            packLength = self.localData.length-BLE.otaPackIndex*16;
            length = self.localData.length;
        }else{
            packLength = 16;
            length = BLE.otaPackIndex*16;
        }
        packLoction = BLE.otaPackIndex*16;
        NSRange range = NSMakeRange(packLoction, packLength);
        NSData *sendData = [self.localData subdataWithRange:range];
        
        [BLE sendOTAPackData:sendData];
        CGFloat progress = (BLE.otaPackIndex+1) * 1.0 / self.count * 1.0;
        
        // 通过回调更新进度
        if (self.otaProgressBlock) {
            self.otaProgressBlock(progress);
        }
    } else if (BLE.otaPackIndex==self.count) {
        packLength = 0;
        length = self.localData.length;
        
        [BLE endOTA];
        
        self.isSingleOTAFinish = YES;
        // 🔥 不要立即重置count，保持值用于后续判断
        NSLog(@"DownloadFiles: OTA数据发送完成，设置isSingleOTAFinish=YES，保持count=%ld", (long)self.count);
        // self.count = 0;  // 注释掉这行，保持count值
        // self.location = 0; // 注释掉这行，保持location值
    }
    
    // 🔥 极速模式(readInterval=0)时跳过读取等待，直接发送下一包
    BOOL isUltraFastMode = (self.otaReadInterval == 0);
    
    // 🔥 流控机制：每发送一定数量的包后，增加小延迟，避免缓冲区溢出
    static NSInteger continuousSentCount = 0;
    
    // 🔥 优化读取间隔检查，减少不必要的读取
    if (!isUltraFastMode && length%(16*self.otaReadInterval)==0 && length) {
        self.isOnePartSent = YES;
        [BLE readSelectPeriperal];
        continuousSentCount = 0; // 重置连续发送计数
        BLE.otaPackIndex++;
        return;
    }
    
    BLE.otaPackIndex++;
    continuousSentCount++;
    
    // 🔥 流控：每连续发送64个包后，增加5ms延迟，让设备有时间处理
    NSTimeInterval nextInterval = self.otaWriteInterval;
    if (continuousSentCount >= 64) {
        nextInterval += 0.0005; // 额外增加5ms延迟
        continuousSentCount = 0;
        NSLog(@"DownloadFiles: 流控 - 已连续发送64个包，增加延迟");
    }
    
    // 🔥 使用更精确的定时器调度，避免累积延迟
    self.otaTimer = [NSTimer scheduledTimerWithTimeInterval:nextInterval 
                                                    target:self 
                                                  selector:@selector(sendDataPack) 
                                                  userInfo:nil 
                                                   repeats:NO];
}

- (void)setupBluetoothEventHandlers {
    NSLog(@"DownloadFiles: setupBluetoothEventHandlers - 设置蓝牙事件回调。");
    __weak typeof(BLE) weakBLE = BLE;
    __weak typeof(self) weakSelf = self;
    
    // 状态更新回调
    [weakBLE setUpdatePeripheralStateBlock:^(ARDeviceStateType type, Device *dev) {
        if (!weakSelf || !weakSelf.isStartOTA) return;
        
        NSLog(@"DownloadFiles: 外设状态更新: %@", @(type));
        
        if (type == ARDeviceStateTypeDisConnected) {
            // 如果OTA已完成，断开是正常的
            if (weakSelf.isSingleOTAFinish) {
                NSLog(@"DownloadFiles: OTA已完成，设备断开连接是正常现象");
                if (!weakSelf.isOtaCompleted && weakSelf.otaCompleteBlock) {
                    weakSelf.isOtaCompleted = YES;
                    weakSelf.otaCompleteBlock(YES, nil);
                    [weakSelf resetOtaState];
                }
                return;
            }
            
            // OTA未完成的断开
            NSLog(@"DownloadFiles: OTA未完成就断开连接");
            if (weakSelf.otaCompleteBlock && !weakSelf.isOtaCompleted) {
                NSString *errorMsg = [NSString stringWithFormat:@"OTA失败：连接断开 (进度: %ld/%ld)", 
                                    (long)BLE.otaPackIndex, (long)weakSelf.count];
                weakSelf.isOtaCompleted = YES;
                weakSelf.otaCompleteBlock(NO, errorMsg);
            }
            [weakSelf resetOtaState];
            
        } else if (type == ARDeviceStateTypeFailure) {
            NSLog(@"DownloadFiles: 连接失败");
            if (weakSelf.otaCompleteBlock && !weakSelf.isOtaCompleted) {
                weakSelf.isOtaCompleted = YES;
                weakSelf.otaCompleteBlock(NO, @"OTA失败：连接失败");
            }
            [weakSelf resetOtaState];
        }
    }];
    
    // OTA数据回调
    [weakBLE setOtaUpdataBlock:^(NSData *data) {
        if (!weakSelf) return;
        
        NSLog(@"DownloadFiles: 收到OTA数据: %@", data);
        
        // OTA完成判断
        if (weakSelf.isSingleOTAFinish) {
            NSLog(@"DownloadFiles: OTA已完成，报告成功");
            if (!weakSelf.isOtaCompleted && weakSelf.otaCompleteBlock) {
                weakSelf.isOtaCompleted = YES;
                weakSelf.otaCompleteBlock(YES, nil);
                [weakSelf resetOtaState];
            }
            return;
        }
        
        // 检查错误响应
        if ([weakSelf isOtaErrorResponse:data]) {
            NSString *errorMsg = [weakSelf parseOtaErrorMessage:data];
            NSLog(@"DownloadFiles: OTA错误: %@", errorMsg);
            if (weakSelf.otaCompleteBlock && !weakSelf.isOtaCompleted) {
                weakSelf.isOtaCompleted = YES;
                weakSelf.otaCompleteBlock(NO, errorMsg);
            }
            [weakSelf resetOtaState];
            return;
        }
        
        // 继续发送数据
        if (weakSelf.isStartOTA && !weakSelf.isSingleOTAFinish) {
            if (weakSelf.isOnePartSent) {
                weakSelf.isOnePartSent = NO;
            }
            [weakSelf sendDataPack];
        }
    }];
    
    // 蓝牙状态回调
    [weakBLE setUpdateCentralStateBlock:^(CBManagerState state){
        if (!weakSelf) return;
        NSLog(@"DownloadFiles: 蓝牙状态更新: %ld", (long)state);
        if (state != CBCentralManagerStatePoweredOn && weakSelf.isStartOTA && !weakSelf.isSingleOTAFinish) {
            if (weakSelf.otaTimer) { 
                [weakSelf.otaTimer invalidate]; 
                weakSelf.otaTimer = nil; 
            }
            if (weakSelf.otaCompleteBlock && !weakSelf.isOtaCompleted) {
                weakSelf.isOtaCompleted = YES;
                weakSelf.otaCompleteBlock(NO, @"蓝牙已关闭，OTA失败");
            }
            weakSelf.isStartOTA = NO;
        }
    }];
}

- (void)clearBluetoothEventHandlers {
    NSLog(@"DownloadFiles: 清理蓝牙事件回调");
    [BLE setUpdatePeripheralStateBlock:nil];
    [BLE setOtaUpdataBlock:nil];
    [BLE setUpdateCentralStateBlock:nil];
}

// 🔥 新增：检查是否是OTA错误响应
- (BOOL)isOtaErrorResponse:(NSData *)data {
    if (!data || data.length == 0) {
        return NO;
    }
    
    // 🔥 关键修复：如果OTA已经标记完成，不再判断为错误响应
    // 进度100%后的所有数据都应该视为正常的完成确认
    if (self.isSingleOTAFinish) {
        NSLog(@"DownloadFiles: OTA已完成，收到的数据视为完成确认: %@", data);
        return NO;
    }
    
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    
    // 检查明确的错误响应模式（仅在OTA进行中时）
    if (data.length >= 4) {
        // 只有特定的错误模式才认为是错误
        if (bytes[0] == 0x06 && bytes[1] == 0xff && bytes[2] == 0x0c && bytes[3] == 0x00) {
            NSLog(@"DownloadFiles: 检测到明确的错误模式: 0x06ff0c00");
            return YES;
        }
        // 0x06ff0000 不再视为错误，可能是完成确认
    }
    
    // 单字节错误检测也要更谨慎
    if (data.length == 1) {
        switch (bytes[0]) {
            case 0xff: // 只有0xff明确是错误
                NSLog(@"DownloadFiles: 检测到错误响应: 0xFF");
                return YES;
            default:
                break;
        }
    }
    
    return NO;
}

// 🔥 新增：解析OTA错误消息
- (NSString *)parseOtaErrorMessage:(NSData *)data {
    if (!data || data.length == 0) {
        return @"未知OTA错误";
    }
    
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    
    // 只有明确的错误模式才报告错误
    if (data.length >= 4 && bytes[0] == 0x06 && bytes[1] == 0xff && bytes[2] == 0x0c && bytes[3] == 0x00) {
        return @"OTA错误: 设备拒绝升级 (可能版本冲突或设备状态异常)";
    }
    
    if (data.length == 1) {
        switch (bytes[0]) {
            case 0xff:
                return @"OTA错误: 设备返回错误状态码 0xFF";
            default:
                break;
        }
    }
    
    // 转换为十六进制字符串显示
    NSMutableString *hexString = [NSMutableString string];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    
    return [NSString stringWithFormat:@"OTA错误: 设备返回未知错误代码 %@", hexString];
}

@end

