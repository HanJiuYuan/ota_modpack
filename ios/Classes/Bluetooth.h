//
//  Bluetooth.h
//  OTA-2-16-OC
//
//  Created by Arvin on 2017/2/16.
//  Copyright © 2017年 Arvin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "Device.h"
#define BLE ([Bluetooth shareCentralManager])
#define UUIDDevices @"uuidDevices"
@interface Bluetooth : NSObject

@property (strong, nonatomic) CBCentralManager * _Nullable centralManager;
@property (assign, nonatomic) CBManagerState state; //!<
@property (assign, nonatomic) BOOL isCanConnect;
@property (assign, nonatomic) BOOL ARConnect;
@property (assign, nonatomic) BOOL isNeedScan;
@property (assign, nonatomic) BOOL isNeedOTAStart;
@property (strong, nonatomic) NSMutableArray *peripheralsArr; //!<
@property (strong, nonatomic) NSMutableArray *peripheralsUUIDArr; //!<

@property (strong, nonatomic) Device * _Nullable currentDevice;
@property (strong, nonatomic) CBCharacteristic * _Nullable otaFeature;



@property (copy, nonatomic) void(^ _Nullable updateCentralStateBlock)(CBManagerState state);//!<
@property (copy, nonatomic) void(^ _Nullable addPeripheralBlock)(Device * _Nullable dev);
@property (copy, nonatomic) void(^ _Nullable otaUpdataBlock)(NSData * _Nullable data);
@property (copy, nonatomic) void(^ _Nullable updatePeripheralStateBlock)(ARDeviceStateType state, Device *dev);
@property (assign, nonatomic) NSUInteger otaPackIndex;

@property (strong, nonatomic) NSMutableArray <CBPeripheral *>*hasBeenConnectedDevices;
@property (strong, nonatomic) NSMutableArray *identifyStringSources;
//@property (copy, nonatomic) void(^updatePeripheralWithStateBlock)(ARDevice *dev, ARDeviceStateType state);

@property (copy, nonatomic) void (^errorBlock)(NSString *errorMessage);

+ (instancetype _Nullable)shareCentralManager;
- (NSArray *)retryDevices;
- (void)deleteDevice:(NSString *)identify;
- (void)connectPeripheral:(CBPeripheral * _Nullable)peripheral;

- (void)startScan;
- (void)stopScan;
- (void)versionGet;
- (void)startOTA;
- (void)endOTA;
- (void)stopConnect;
- (void)resetProperties;
- (void)rescan;
- (void)readSelectPeriperal;
- (void)sendOTAPackData:(NSData *)data;
- (void)setErrorMessageBlock:(void (^)(NSString *errorMessage))block;


- (void)setActivePeripheral:(CBPeripheral * _Nonnull)peripheral;
@end
