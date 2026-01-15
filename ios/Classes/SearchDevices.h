//
//  SearchDevices.h
//  OTA-2-16-OC
//
//  Created by Arvin on 2017/2/16.
//  Copyright © 2017年 Arvin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Device.h" // Assuming Device.h defines the 'Device' type for callbacks

@interface SearchDevices : NSObject // MODIFIED from UIViewController

// Methods for the plugin to interact with scanning logic
- (void)startDeviceScan;
- (void)stopDeviceScan;

// Callback setup for BLE events
- (void)setupBleEventBlocksWithDeviceFound:(void (^)(Device * _Nullable device))deviceFoundBlock
                           deviceConnected:(void (^)(Device * _Nullable device))deviceConnectedBlock
                        deviceDisconnected:(void (^)(Device * _Nullable device))deviceDisconnectedBlock
                                scanFailed:(void (^)(NSString * _Nullable errorMessage))scanFailedBlock
                        characteristicFound:(void (^)(Device * _Nullable device))characteristicFoundBlock
                        updateRSSI:(void (^)(Device * _Nullable device))updateRSSIBlock;

// Method to clear blocks when SearchDevices instance is no longer needed
- (void)clearBleEventBlocks;

@end

