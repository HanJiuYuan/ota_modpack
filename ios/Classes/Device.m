//
//  Device.m
//  OTA-2-16-OC
//
//  Created by Arvin on 2017/2/16.
//  Copyright © 2017年 Arvin. All rights reserved.
//

#import "Device.h"

@implementation Device
- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral {
    if (self = [super init]) {
        _peripheral = peripheral;
        _name = peripheral.name;
        _bleName = peripheral.name;
    }
    return self;
}
+ (instancetype)searchDeviceWith:(CBPeripheral *)per inDeviceSource:(NSArray *)source {
    for (id dev in source) {
        if ([dev isKindOfClass:[Device class]]) {
            Device *d = dev;
            if ([d.peripheral isEqual:per]) return d;
        }else if ([dev isKindOfClass:[CBPeripheral class]]) {
            CBPeripheral *p = dev;
            if ([per.identifier.UUIDString isEqualToString:p.identifier.UUIDString]) {
                Device *dev = [[Device alloc] initWithPeripheral:p];
                return dev;
            }
        }
    }
    
    return nil;
}
+ (NSMutableAttributedString *)getMutableString:(NSString *)uuidStr {
//    NSString *name = [NSString stringWithFormat:@"%@->%@",kOTABLEName,[uuidStr substringFromIndex:uuidStr.length-4]];
//    NSMutableAttributedString *mutStr = [[NSMutableAttributedString alloc] initWithString:name];
//    [mutStr addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:NSMakeRange(0, kOTABLEName.length)];
//    [mutStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:9] range:NSMakeRange(kOTABLEName.length, 2)];
//    [mutStr addAttribute:NSForegroundColorAttributeName value:[UIColor blueColor] range:NSMakeRange(name.length-4, 4)];
//    return mutStr;
    return nil;
}
@end
