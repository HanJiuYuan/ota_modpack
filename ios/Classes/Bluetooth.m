#import "Bluetooth.h"
#import <ExternalAccessory/ExternalAccessory.h>
@interface Bluetooth () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (strong, nonatomic) NSTimer *scanTimer;
@property (strong, nonatomic) NSTimer *connectTimer;

@property (assign, nonatomic) BOOL isNew;
@property (strong, nonatomic) NSTimer *rssiTimer;
@property (assign, nonatomic) int internalCounter;

@end
@implementation Bluetooth
#pragma mark- lazy load

- (NSMutableArray <CBPeripheral *>*)hasBeenConnectedDevices {
    if (!_hasBeenConnectedDevices) {
        _hasBeenConnectedDevices = [[NSMutableArray alloc] init];
        _identifyStringSources = [[NSMutableArray alloc] init];
    }
    [_hasBeenConnectedDevices removeAllObjects];
    
    
    [_hasBeenConnectedDevices addObjectsFromArray:[BLE retryDevices]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    return _hasBeenConnectedDevices;
}
- (NSMutableArray *)identifyStringSources {
    if (!_identifyStringSources) {
        _identifyStringSources = [[NSMutableArray alloc] init];
    }
    [_identifyStringSources removeAllObjects];
    for (int j=0; j<self.hasBeenConnectedDevices.count; j++) {
        [_identifyStringSources addObject:self.hasBeenConnectedDevices[j].identifier.UUIDString];
    }
    return _identifyStringSources;
}

- (NSMutableArray *)peripheralsArr {
    if (!_peripheralsArr) {
        _peripheralsArr = [NSMutableArray array];
    }
    return _peripheralsArr;
}
- (NSMutableArray *)peripheralsUUIDArr {
    if (!_peripheralsUUIDArr) {
        _peripheralsUUIDArr = [NSMutableArray array];
    }
    return _peripheralsUUIDArr;
}

#pragma mark- init
+ (instancetype)shareCentralManager {
    static Bluetooth *_centralManager = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        _centralManager = [[Bluetooth alloc] init];
    });
    return _centralManager;
}

- (instancetype)init {
    if (self = [super init]) {
        // 确保这里的初始化总是被调用，并且 centralManager 被赋值
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue() options:nil]; // 可以添加 options:nil
        NSLog(@"CBCentralManager在init中初始化：%@", _centralManager);
        _ARConnect = NO;
        _isCanConnect = NO;
        _isNeedScan = NO;
    }
    return self;
}

#pragma mark- Setter & Getter

- (BOOL)ARConnect {
    return _ARConnect;
}
- (NSArray <CBPeripheral *>*)retryDevices {
    NSArray *ar = [[NSUserDefaults standardUserDefaults] objectForKey:UUIDDevices];
    NSArray *arr = [NSArray array];
    if (ar && ar.count > 0) {
        NSMutableArray *uuids = [NSMutableArray array];
        for (NSString *uuidString in ar) {
            NSUUID *uuidst = [[NSUUID alloc] initWithUUIDString:uuidString];
            [uuids addObject:uuidst];
        }
        if (uuids) {
            arr = [self.centralManager retrievePeripheralsWithIdentifiers:uuids];
        }
    }
    return arr;
}

- (void)deleteDevice:(NSString *)identify {
    NSMutableArray <CBPeripheral *>*ar = [NSMutableArray arrayWithArray:[self retryDevices]];
    NSMutableArray <CBPeripheral *>*tempAr = ar.mutableCopy;
    for (int j=0; j<tempAr.count; j++) {
        if ([tempAr[j].identifier.UUIDString isEqualToString:identify]) {
            [ar removeObjectAtIndex:j];
            NSMutableArray *tem = [NSMutableArray array];
            for (CBPeripheral *p in ar) {
                [tem addObject:p.identifier.UUIDString];
            }
            [[NSUserDefaults standardUserDefaults] setObject:tem forKey:UUIDDevices];
            [[NSUserDefaults standardUserDefaults] synchronize];
            break;
        }
    }
}
- (void)connectPeripheral:(CBPeripheral * _Nullable)peripheral {
    if (!peripheral) {
        NSLog(@"Bluetooth: connectPeripheral 调用，外设为空。");
        return;
    }
    NSLog(@"Bluetooth: connectPeripheral 调用，外设: %@, 当前状态: %ld", peripheral.identifier.UUIDString, (long)peripheral.state);
    if ([self.currentDevice.peripheral isEqual:peripheral] &&
        (peripheral.state == CBPeripheralStateConnected || peripheral.state == CBPeripheralStateConnecting)) {
        NSLog(@"Bluetooth: 外设已经是当前设备且已连接/正在连接。");
        if (peripheral.state == CBPeripheralStateConnected) {
            NSLog(@"Bluetooth: 外设已连接。触发服务发现以确保otaFeature已设置。");
            [peripheral discoverServices:nil];
             if (!self.ARConnect) {
                 [self centralManager:self.centralManager didConnectPeripheral:peripheral];
             }
        }
        return;
    }
    if (self.currentDevice && self.currentDevice.peripheral && self.currentDevice.peripheral != peripheral) {
        NSLog(@"Bluetooth: 取消到前一个当前设备的连接: %@", self.currentDevice.peripheral.identifier.UUIDString);
        [self.centralManager cancelPeripheralConnection:self.currentDevice.peripheral];
    }
    self.currentDevice = nil; 
    self.ARConnect = NO;
    self.otaFeature = nil;
    
    NSLog(@"Bluetooth: 尝试连接到外设: %@", peripheral.identifier.UUIDString);
    
    // 简化连接选项，去掉可能不被支持的选项
    NSDictionary *connectionOptions = @{
        CBConnectPeripheralOptionNotifyOnDisconnectionKey: @YES,
        CBConnectPeripheralOptionNotifyOnConnectionKey: @YES
    };
    
    [self.centralManager connectPeripheral:peripheral options:connectionOptions];
    
    if (!self.scanTimer) { 
        kEndTimer(self.connectTimer); 
        // 连接超时时间改为15秒，更合理
        self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 
                                                            target:self 
                                                          selector:@selector(connectionAttemptTimeout:) 
                                                          userInfo:peripheral 
                                                           repeats:NO];
        NSLog(@"Bluetooth: 连接超时计时器已启动，15秒。");
    }
}

// 简化连接超时处理
- (void)connectionAttemptTimeout:(NSTimer *)timer {
    CBPeripheral *timedOutPeripheral = (CBPeripheral *)timer.userInfo;
    NSLog(@"Bluetooth: 外设连接超时: %@", timedOutPeripheral.identifier.UUIDString);
    kEndTimer(self.connectTimer);
    
    if (timedOutPeripheral.state != CBPeripheralStateConnected) {
        // 如果还未连接，则取消连接尝试
        [self.centralManager cancelPeripheralConnection:timedOutPeripheral];
        
        // 不再自动重连，让上层决定是否重试
        if (self.updatePeripheralStateBlock) {
            Device *dev = kSearchResult(timedOutPeripheral, self.peripheralsArr);
            if (!dev) dev = [[Device alloc] initWithPeripheral:timedOutPeripheral];
            self.updatePeripheralStateBlock(ARDeviceStateTypeOutLine, dev);
        }
    }
}

- (void)cancelConnect {
    [self.centralManager cancelPeripheralConnection:self.currentDevice.peripheral];
}
- (void)timerStop {
    kEndTimer(self.scanTimer);
    
    if (CBPeripheralStateConnected==_currentDevice.peripheral.state)
        return;
    [self stopConnect];
    self.updatePeripheralStateBlock(ARDeviceStateTypeOutLine, self.currentDevice);
}
- (void)stopConnect {
    self.otaPackIndex = 0;
    [_centralManager stopScan];
    if (self.currentDevice.peripheral) {
        [_centralManager cancelPeripheralConnection:self.currentDevice.peripheral];
    }
    
    if (self.updatePeripheralStateBlock)
        self.updatePeripheralStateBlock(ARDeviceStateTypeReConnect, self.currentDevice);
}
- (void)stopScan {
    kEndTimer(self.rssiTimer);
    [self.centralManager stopScan];
}
- (void)startScan {
    NSLog(@"Bluetooth: ===== startScan 开始 =====");
    NSLog(@"Bluetooth: centralManager状态: %ld, _isNeedScan: %d", (long)self.centralManager.state, _isNeedScan);
    
    // 首先停止任何正在进行的扫描
    [self.centralManager stopScan];
    NSLog(@"Bluetooth: 已停止之前的扫描");
    
    if (CBCentralManagerStatePoweredOn == self.centralManager.state) {
        NSLog(@"Bluetooth: centralManager已准备好，清理缓存后开始扫描...");
        
        // 重要：每次开始新扫描前都清理设备缓存！
        NSLog(@"Bluetooth: 开始扫描前清理设备缓存");
        [self.peripheralsArr removeAllObjects];
        [self.peripheralsUUIDArr removeAllObjects];
        
        // 开始扫描，不使用重复发现选项以节省功耗
        [self.centralManager scanForPeripheralsWithServices:nil options:nil];
        NSLog(@"Bluetooth: 开始扫描外设");
        _isNeedScan = NO; // 扫描已开始，重置标志
    } else {
        NSLog(@"Bluetooth: centralManager状态不是PoweredOn，设置_isNeedScan标志等待状态更新");
        _isNeedScan = YES; // 设置标志，当状态变为PoweredOn时自动扫描
    }
    
    NSLog(@"Bluetooth: ===== startScan 完成 =====");
}

- (void)readSelectPeriperal {
    if (!self.ARConnect||
        !self.otaFeature||
        !self.currentDevice||
        self.currentDevice.peripheral.state!=CBPeripheralStateConnected)
        return;
    [self.currentDevice.peripheral readValueForCharacteristic:self.otaFeature];
}

- (void)scanForRSSI {
    [self.centralManager scanForPeripheralsWithServices:nil options:nil];
}

#pragma mark- CBCentralManagerDelegate  Method

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSLog(@"[%@->%@]",NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    NSLog(@"Bluetooth: centralManager状态更新为: %ld, _isNeedScan: %d", (long)central.state, _isNeedScan);
    if (CBCentralManagerStatePoweredOn == central.state) {
        if (_isNeedScan) {
            NSLog(@"Bluetooth: 蓝牙已开启且_isNeedScan为YES，开始扫描外设...");
            [central scanForPeripheralsWithServices:nil options:nil];
        } else {
            NSLog(@"Bluetooth: 蓝牙已开启但_isNeedScan为NO，不启动扫描");
        }
        _state = central.state;
    } else {
        NSLog(@"Bluetooth: 蓝牙状态不是PoweredOn: %ld", (long)central.state);
    }
    if (self.updateCentralStateBlock) self.updateCentralStateBlock(central.state);
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"Bluetooth: ===== 发现外设 =====");
    NSLog(@"Bluetooth: 外设UUID: %@", peripheral.identifier.UUIDString);
    NSLog(@"Bluetooth: 外设名称: %@", peripheral.name ?: @"无名称");
    NSLog(@"Bluetooth: RSSI: %@", RSSI);
    NSLog(@"Bluetooth: 广告数据: %@", advertisementData);
    
    NSString *localName = advertisementData[CBAdvertisementDataLocalNameKey];
    if (!localName) {
        localName = peripheral.name;
    }
    
    NSLog(@"Bluetooth: 最终使用的本地名称: %@", localName ?: @"无名称");
    
    if (!localName) {
        NSLog(@"Bluetooth: 跳过无名称设备");
        return;
    }
    
    NSLog(@"[%@->%@]",NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    NSLog(@"%@\nadvertisementData = %@",RSSI,advertisementData);
    
    Device *dev = nil;
    BOOL isNew = NO;
    
    // 检查是否是已发现的设备
    if ([self.peripheralsUUIDArr containsObject:peripheral.identifier.UUIDString]) {
        // 更新已知设备的RSSI
        NSInteger index = [self.peripheralsUUIDArr indexOfObject:peripheral.identifier.UUIDString];
        dev = self.peripheralsArr[index];
        dev.rssiV = RSSI;
        dev.state = ARDeviceStateTypeUpdataRSSI;
        NSLog(@"Bluetooth: 更新已知设备的RSSI: %@ (RSSI: %@)", localName, RSSI);
        isNew = NO;
    } else {
        // 新发现的设备
        dev = [[Device alloc] init];
        dev.rssiV = RSSI;
        dev.state = ARDeviceStateTypeDiscovered;
        dev.peripheral = peripheral;
        dev.bleName = localName;
        dev.name = peripheral.identifier.UUIDString;
        dev.dic = [NSDictionary dictionaryWithDictionary:advertisementData];
        
        [self.peripheralsArr addObject:dev];
        [self.peripheralsUUIDArr addObject:peripheral.identifier.UUIDString];
        NSLog(@"Bluetooth: 新发现设备，调用 addPeripheralBlock: %@", localName);
        isNew = YES;
        
        // 调用新设备发现回调
        if (self.addPeripheralBlock) {
            self.addPeripheralBlock(dev);
    }
    }
    
    // 调用状态更新回调
    if (self.updatePeripheralStateBlock) {
        self.updatePeripheralStateBlock(dev.state, dev);
    }
    
    NSLog(@"Bluetooth: ===== 外设处理完成 (新设备: %@) =====", isNew ? @"是" : @"否");
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Bluetooth: centralManager:didConnectPeripheral: %@", peripheral.identifier.UUIDString);
    kEndTimer(self.connectTimer); // 连接成功，停止连接超时计时器
    
    [self stopScan]; // 连接成功后通常停止扫描

    NSMutableArray *arr = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:UUIDDevices]];
    BOOL contan = NO;
    for (int j=0; j<arr.count; j++) {
        NSUUID *uuid = [[NSUUID alloc]initWithUUIDString:arr[j]];
        
        if ([uuid.UUIDString isEqual:peripheral.identifier.UUIDString]) {
            contan = YES;
            break;
        }
    }
    if (!contan) {
        [arr addObject:peripheral.identifier.UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:arr forKey:UUIDDevices];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    
    NSLog(@"Bluetooth: 为已连接外设发现服务: %@", peripheral.identifier.UUIDString);
    Device *dev = kSearchResult(peripheral, self.peripheralsArr);
    if (!dev) {
        dev = kSearchResult(peripheral, self.hasBeenConnectedDevices);
    }
    dev.state = ARDeviceStateTypeConnected;
    dev.bleName = peripheral.name;
    _currentDevice = dev;
    peripheral.delegate = self;
    self.ARConnect = YES;
    
    // 🔥 优化连接参数以提高OTA速度
    // 请求最小连接间隔，这可以显著提高传输速度
    if (@available(iOS 9.0, *)) {
        // 读取当前最大传输单元(MTU)
        NSUInteger mtu = [peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse];
        NSLog(@"Bluetooth: 当前MTU大小: %lu", (unsigned long)mtu);
        
        // 如果设备支持，可以请求更高的MTU以提高传输速度
        // 注意：这需要外设端也支持
    }
    
    [peripheral discoverServices:nil];
    
    if (self.updatePeripheralStateBlock) self.updatePeripheralStateBlock(dev.state, dev);
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"[Bluetooth->centralManager:didDisconnectPeripheral:] 外设: %@, 错误: %@", peripheral.identifier.UUIDString, error.localizedDescription ?: @"无错误信息");
    _currentDevice.state = ARDeviceStateTypeDisConnected;
    
    // 简单处理：直接调用断开处理
    [self disconnectOrFailureConnect:peripheral type:ARDeviceStateTypeDisConnected];
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"[Bluetooth->centralManager:didFailToConnectPeripheral:] 外设: %@, 错误: %@", peripheral.identifier.UUIDString, error.localizedDescription ?: @"无错误信息");
    [self disconnectOrFailureConnect:peripheral type:ARDeviceStateTypeFailure];
}
#pragma mark- CBPeripheralDelegate  Method
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    NSLog(@"Bluetooth: peripheral:didDiscoverServices 外设: %@, 错误: %@", peripheral.identifier.UUIDString, error.localizedDescription ?: @"无错误信息");
    if (error) {
        NSLog(@"发现服务错误: %@", [error localizedDescription]);
        // 可能需要处理错误，例如断开连接或通知上层
        [self.centralManager cancelPeripheralConnection:peripheral];
        return;
    }
    for (CBService *ser in peripheral.services) {
        NSLog(@"Bluetooth: 找到服务: %@", ser.UUID.UUIDString);
        [peripheral discoverCharacteristics:nil forService:ser]; // 发现此服务的所有特征
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    NSLog(@"Bluetooth: peripheral:didDiscoverCharacteristicsForService 外设: %@, 服务: %@", peripheral.identifier.UUIDString, service.UUID.UUIDString);
    if (error) {
        NSLog(@"发现特征错误 服务 %@: %@", service.UUID.UUIDString, [error localizedDescription]);
        return;
    }
    BOOL otaCharFoundThisTime = NO;
    for (CBCharacteristic *cha in service.characteristics) {
        NSLog(@"Bluetooth: 找到特征: %@ 服务: %@", cha.UUID.UUIDString, service.UUID.UUIDString);
        // kOTACharactUUID 是在 Device.h 中定义的 @"00010203-0405-0607-0809-0a0b0c0d2b12"
        if ([cha.UUID isEqual:[CBUUID UUIDWithString:kOTACharactUUID]]) {
            NSLog(@"Bluetooth: OTA 特征找到: %@", cha.UUID.UUIDString);
            [peripheral setNotifyValue:YES forCharacteristic:cha];
            self.otaFeature = cha;
            if ([self.currentDevice.peripheral isEqual:peripheral]) {
                 self.currentDevice.state = ARDeviceStateTypeDiscovereCharacteristic;
                 if (self.updatePeripheralStateBlock) {
                     self.updatePeripheralStateBlock(self.currentDevice.state, self.currentDevice);
                 }
            }
            otaCharFoundThisTime = YES;
        }
    }

    // 检查是否是最后一个服务的特征发现回调，并且 otaFeature 仍未找到
    // 这个原有逻辑可能不完全准确，因为服务和特征发现是异步的，services.lastObject 不一定代表所有都已完成
    // 更好的做法是在所有服务的特征都发现完毕后进行判断，或者只要找到 otaFeature 就认为准备好了
    if (otaCharFoundThisTime) {
         NSLog(@"Bluetooth: OTA Characteristic setup complete for peripheral: %@", peripheral.identifier.UUIDString);
    } else {
        // 如果这是最后一个服务，并且还没有找到OTA特征，则认为失败
        if ([peripheral.services.lastObject isEqual:service] && self.otaFeature == nil) {
            NSLog(@"Bluetooth: 在所有服务发现完毕后，OTA特征仍未找到 外设: %@", peripheral.identifier.UUIDString);
            if (self.errorBlock) {
                self.errorBlock(@"The OTA Characteristic is not found");
            }
            // [self.centralManager cancelPeripheralConnection:peripheral]; // 暂时不在这里断开，给其他逻辑机会
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"[Bluetooth->peripheral:didUpdateValueForCharacteristic:] 特征: %@, 值: %@", characteristic.UUID.UUIDString, characteristic.value);
    if (error) {
        NSLog(@"读取特征值错误 -> %@",[error localizedDescription]);
        return;
    }
    if ([characteristic isEqual:self.otaFeature]) {
        NSData *data = characteristic.value;
        self.otaUpdataBlock(data);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"[Bluetooth->peripheral:didWriteValueForCharacteristic:] 特征: %@, 状态: %s", characteristic.UUID.UUIDString, error ? "失败" : "成功");
    if (error) {
        NSLog(@"写入特征值错误: %@",error.localizedDescription);
        return;
    }
}
- (void)disconnectOrFailureConnect:(CBPeripheral *)peripheral type:(ARDeviceStateType)type {
    self.ARConnect = NO;
    Device *dev = kSearchResult(peripheral, self.peripheralsArr);
    if (!dev) return;
    dev.state = type;
    if (self.updatePeripheralStateBlock) self.updatePeripheralStateBlock(dev.state, dev);
    //    if (self.isCanConnect) [self connectPeripheral:peripheral];
}
- (void)rescan {
    NSLog(@"Bluetooth: ===== rescan 开始 - 完全重置扫描状态 =====");
    
    // 1. 停止所有计时器
    kEndTimer(self.rssiTimer);
    kEndTimer(self.scanTimer);
    kEndTimer(self.connectTimer);
    
    // 2. 停止当前扫描
    [self.centralManager stopScan];
    NSLog(@"Bluetooth: 已停止当前扫描");
    
    // 3. 断开当前连接的设备
    if (self.currentDevice && self.currentDevice.peripheral) {
        NSLog(@"Bluetooth: 断开当前设备连接: %@", self.currentDevice.peripheral.identifier.UUIDString);
        [self.centralManager cancelPeripheralConnection:self.currentDevice.peripheral];
        self.currentDevice = nil;
    }
    
    // 4. 清理所有缓存的设备数组 - 这是关键！
    NSLog(@"Bluetooth: 清理设备缓存数组，清理前有 %lu 个设备", (unsigned long)self.peripheralsArr.count);
    [self.peripheralsArr removeAllObjects];
    [self.peripheralsUUIDArr removeAllObjects];
    NSLog(@"Bluetooth: 设备缓存数组已清理");
    
    // 5. 重置连接状态
    self.ARConnect = NO;
    self.otaFeature = nil;
    self.otaPackIndex = 0;
    
    // 6. 重置扫描标志并立即开始新的扫描
    _isNeedScan = YES;
    NSLog(@"Bluetooth: 设置 _isNeedScan = YES，准备开始新扫描");
    
    // 7. 延迟一点时间让蓝牙系统稳定，然后开始扫描
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"Bluetooth: 延迟后开始新的扫描");
        [self startScan];
    });
    
    NSLog(@"Bluetooth: ===== rescan 完成 =====");
}
- (void)resetProperties {
    kEndTimer(self.rssiTimer);
    kEndTimer(self.scanTimer);
    kEndTimer(self.connectTimer);
    [self.centralManager stopScan];
    for (Device *dp in self.peripheralsArr) {
        [self.centralManager cancelPeripheralConnection:dp.peripheral];
    }
    self.otaFeature = nil;
    self.otaPackIndex = 0;
    self.ARConnect = NO;
    self.isNeedOTAStart = NO;
    [self.peripheralsUUIDArr removeAllObjects];
    [self.peripheralsArr removeAllObjects];
    self.currentDevice = nil;
}
- (void)versionGet {
    uint8_t buf[2] = {0x00,0xff};
    NSData *data = [NSData dataWithBytes:buf length:2];
    [self.currentDevice.peripheral writeValue:data forCharacteristic:self.otaFeature type:CBCharacteristicWriteWithoutResponse];
    
}
- (void)startOTA {
    uint8_t buf[2] = {0x01,0xff};
    NSData *data = [NSData dataWithBytes:buf length:2];
    [self.currentDevice.peripheral writeValue:data forCharacteristic:self.otaFeature type:CBCharacteristicWriteWithoutResponse];
    NSLog(@"startOTA data - > %@", data);
}
- (void)endOTA {
    uint8_t buf[6] = {0x02,0xff,0,0,0,0};
    buf[2] = (self.otaPackIndex-1)&0xff;
    buf[3] = ((self.otaPackIndex-1) >>8)& 0xff;
    buf[4] = (~(self.otaPackIndex-1))&0xff;
    buf[5] = ((~(self.otaPackIndex-1))>>8)&0xff;
    uint8_t verifyB[8];
    memset(verifyB, 0, 8);
    for (int j=0; j<6; j++) {
        verifyB[j] = buf[j];
    }
    //CRC
    unsigned short crc_t = crc16(buf, 6);
    verifyB[6] = (crc_t)&0xff;
    verifyB[7] = (crc_t >> 8) & 0xff;
    NSData *data = [NSData dataWithBytes:verifyB length:8];
    [self.currentDevice.peripheral writeValue:data forCharacteristic:self.otaFeature type:CBCharacteristicWriteWithoutResponse];
    NSLog(@"end OTA data - > %@", data);
}

- (void)sendOTAPackData:(NSData *)data {
    if (!self.ARConnect ||
        !self.currentDevice || !self.otaFeature ||
        (self.currentDevice.peripheral.state!=CBPeripheralStateConnected))
        return;
    NSUInteger length = data.length;
    uint8_t *tempData=(uint8_t *)[data bytes];
    uint8_t pack_head[2];
    pack_head[1] = (self.otaPackIndex >>8)& 0xff;
    pack_head[0] = (self.otaPackIndex)&0xff;
    
    //data
    if (length > 0 && length < 16) {
        length = 16;
    }
    uint8_t otaBuffer[length+4];
    memset(otaBuffer, 0, length+4);
    
    
    uint8_t otaCmd[length+2];
    memset(otaCmd, 0, length+2);
    
    for (int i = 0; i < 2; i ++) {       //index指数部分
        otaBuffer[i] = pack_head[i];
    }
    for (int i = 2; i < length+2; i++) {  //bin 文件数据包
        if (i < data.length+2) {
            otaBuffer[i] = tempData[i-2];
        }else{
            otaBuffer[i] = 0xff;
        }
    }
    for (int i = 0; i < length+2; i++) {
        otaCmd[i] = otaBuffer[i];
    }
    
    //CRC
    unsigned short crc_t = crc16(otaCmd, (int)length+2);
    uint8_t crc[2];
    crc[1] = (crc_t >> 8) & 0xff;
    crc[0] = (crc_t)&0xff;
    for (int i = (int)length+3; i > (int)length+1; i--) {   //2->4
        otaBuffer[i] = crc[i-length-2];
    }

    NSData *tempdata=[NSData dataWithBytes:otaBuffer length:length+4];
    NSLog(@"data -> %@",tempdata);
    if (self.ARConnect) {
        [self.currentDevice.peripheral writeValue:tempdata forCharacteristic:self.otaFeature type:CBCharacteristicWriteWithoutResponse];
    }
    //    self.otaPackIndex++;
    if (!self.ARConnect || length == 0)
        self.otaPackIndex = NSNotFound;
}
extern unsigned short crc16 (unsigned char *pD, int len) {
    static unsigned short poly[2]={0, 0xa001};              //0x8005 <==> 0xa001
    unsigned short crc = 0xffff;
    int i,j;
    for(j=len; j>0; j--) {
        unsigned char ds = *pD++;
        for(i=0; i<8; i++) {
            crc = (crc >> 1) ^ poly[(crc ^ ds ) & 1];
            ds = ds >> 1;
        }
    }
    return crc;
}

- (void)printCommand:(uint8_t *)cmd len:(NSInteger)len str:(NSString *)str {
    NSMutableArray *temp = [NSMutableArray array];
    for (NSInteger i=0; i<len; i++) {
        [temp addObject:[NSString stringWithFormat:@"%x",cmd[i]]];
    }
    NSLog(@"%@ -> %@",str,[temp componentsJoinedByString:@"-"]);
}

- (void)setErrorMessageBlock:(void (^)(NSString *errorMessage))block {
    self.errorBlock = block;
}

// --- 新增 setActivePeripheral 方法实现 ---
- (void)setActivePeripheral:(CBPeripheral * _Nonnull)peripheral {
    NSLog(@"Bluetooth: setActivePeripheral 调用，外设: %@, 状态: %ld", peripheral.identifier.UUIDString, (long)peripheral.state);
    if (peripheral.state == CBPeripheralStateConnected) {
        NSLog(@"Bluetooth: 外设已连接。设置为当前设备。");
        // 这个 peripheral 是由外部（如 flutter_blue_plus）连接的
        // 我们需要让我们的 Bluetooth 单例"认领"这个连接

        // 1. 更新 currentDevice
        // 检查 peripheralsArr 中是否已有此设备对应的 Device 对象
        Device *devModel = nil;
        for (Device *dev in self.peripheralsArr) {
            if ([dev.peripheral.identifier isEqual:peripheral.identifier]) {
                devModel = dev;
                break;
            }
        }
        if (!devModel) {
            devModel = [[Device alloc] initWithPeripheral:peripheral];
            // 考虑是否要将其加入 peripheralsArr
            // [self.peripheralsArr addObject:devModel];
            // [self.peripheralsUUIDArr addObject:peripheral.identifier.UUIDString];
        }
        devModel.state = ARDeviceStateTypeConnected; // 更新我们自己模型的状态

        self.currentDevice = devModel;
        self.ARConnect = YES; // 标记我们的原生逻辑认为设备已连接

        // 2. 设置代理
        // 非常重要：确保我们的 Bluetooth 实例是这个 peripheral 的代理，
        // 这样才能收到 didDiscoverServices, didDiscoverCharacteristicsForService 等回调
        if (peripheral.delegate != self) {
            peripheral.delegate = self;
             NSLog(@"Bluetooth: 将自身设置为外设代理: %@", peripheral.identifier.UUIDString);
        }

        // 3. 触发服务和特征发现 (关键步骤)
        // 因为 Telink OTA 逻辑依赖于 otaFeature 被正确设置
        NSLog(@"Bluetooth: 为外部连接的外设触发服务发现: %@", peripheral.identifier.UUIDString);
        [peripheral discoverServices:nil]; // 传递 nil 会发现所有服务

        // 4. (可选) 调用连接成功的回调，如果外部逻辑需要知道
        if (self.updatePeripheralStateBlock) {
            self.updatePeripheralStateBlock(ARDeviceStateTypeConnected, self.currentDevice);
        }

    } else {
        NSLog(@"Bluetooth: setActivePeripheral 调用，但外设未连接 (状态: %ld)。尝试连接。", (long)peripheral.state);
        // 如果外部传递过来的 peripheral 不是连接状态，则尝试用我们的 connectPeripheral 方法连接它
        [self connectPeripheral:peripheral];
    }
}

@end
