//
//  SearchDevices.m
//  OTA-2-16-OC
//
//  Created by Arvin on 2017/2/16.
//  Copyright © 2017年 Arvin. All rights reserved.
//

#import "SearchDevices.h"
#import "Device.h"
#import "Bluetooth.h"

@interface SearchDevices ()
@end

@implementation SearchDevices

- (void)startDeviceScan {
    NSLog(@"SearchDevices (逻辑层): 开始设备扫描。");
    [BLE startScan];
}

- (void)stopDeviceScan {
    NSLog(@"SearchDevices (逻辑层): 停止设备扫描。");
    [BLE stopScan];
    // 注释掉这行，因为 resetProperties 会取消所有连接，包括正在进行的连接
    // [BLE resetProperties];
}

- (void)setupBleEventBlocksWithDeviceFound:(void (^)(Device * _Nullable device))deviceFoundBlock
                           deviceConnected:(void (^)(Device * _Nullable device))deviceConnectedBlock
                        deviceDisconnected:(void (^)(Device * _Nullable device))deviceDisconnectedBlock
                                scanFailed:(void (^)(NSString * _Nullable errorMessage))scanFailedBlock
                        characteristicFound:(void (^)(Device * _Nullable device))characteristicFoundBlock
                        updateRSSI:(void (^)(Device * _Nullable device))updateRSSIBlock {

    [BLE setAddPeripheralBlock:^(Device * _Nullable dev) {
        NSLog(@"SearchDevices (逻辑层): 发现外设: %@", dev.bleName);
        if (deviceFoundBlock) {
            deviceFoundBlock(dev);
        }
    }];

    [BLE setUpdatePeripheralStateBlock:^(ARDeviceStateType type, Device *dev) {
        NSLog(@"SearchDevices (逻辑层): 外设状态更新: %@, 设备: %@", @(type), dev.bleName);
        switch (type) {
            case ARDeviceStateTypeConnected:
                NSLog(@"SearchDevices (逻辑层): 设备已连接: %@", dev.bleName);
                if (deviceConnectedBlock) deviceConnectedBlock(dev);
                break;
            case ARDeviceStateTypeDisConnected:
                NSLog(@"SearchDevices (逻辑层): 设备断开连接: %@", dev.bleName);
                if (deviceDisconnectedBlock) deviceDisconnectedBlock(dev);
                break;
            case ARDeviceStateTypeFailure:
                NSLog(@"SearchDevices (逻辑层): 设备连接失败: %@", dev.bleName);
                if (scanFailedBlock) scanFailedBlock(@"连接失败");
                break;
            case ARDeviceStateTypeDiscovereCharacteristic:
                NSLog(@"SearchDevices (逻辑层): 设备特征发现: %@", dev.bleName);
                if (characteristicFoundBlock) characteristicFoundBlock(dev);
                break;
            case ARDeviceStateTypeOutLine:
                 NSLog(@"SearchDevices (逻辑层): 设备连接超时: %@", dev.bleName);
                if (scanFailedBlock) scanFailedBlock(@"连接超时");
                break;
            case ARDeviceStateTypeUpdataRSSI:
                NSLog(@"SearchDevices (逻辑层): 设备RSSI更新: %@ for %@", dev.rssiV, dev.bleName);
                if (updateRSSIBlock) updateRSSIBlock(dev);
                break;
            default:
                break;
        }
    }];

    [BLE setUpdateCentralStateBlock:^(CBManagerState state){
        NSLog(@"SearchDevices (逻辑层): 中央管理器状态更新: %ld", (long)state);
        if (state==CBCentralManagerStatePoweredOn) {
            NSLog(@"SearchDevices (逻辑层): 蓝牙已开启。");
        } else if (state==CBCentralManagerStatePoweredOff){
            NSLog(@"SearchDevices (逻辑层): 蓝牙已关闭。");
            if (scanFailedBlock) scanFailedBlock(@"蓝牙已关闭");
        }
    }];
}

- (void)clearBleEventBlocks {
    NSLog(@"SearchDevices (逻辑层): 清理BLE事件回调。");
    [BLE setAddPeripheralBlock:nil];
    [BLE setUpdatePeripheralStateBlock:nil];
    [BLE setUpdateCentralStateBlock:nil];
}

@end
