#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

typedef NS_ENUM(NSUInteger, ARDeviceStateType) {
    ARDeviceStateTypeReadyToConnect,
    ARDeviceStateTypeDiscovered,
    ARDeviceStateTypeUpdataRSSI,
    ARDeviceStateTypeDiscovereCharacteristic,
    ARDeviceStateTypeConnected,
    ARDeviceStateTypeDisConnected,
    ARDeviceStateTypeReConnect,
    ARDeviceStateTypeFailure,
    ARDeviceStateTypeOutLine
};
#if DEBUG
#define ARDebugLog(format, ...) \
NSLog((format),##__VA_ARGS__);
#else
#define ARDebugLog(format, ...) \
NSLog(@"");
#endif

#define kEndTimer(timer) \
if (timer) {    \
[timer invalidate]; \
timer = nil;    \
}
#define kMainSBInitVC(name) ([[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:name])
#define kLocalName @"kCBAdvDataLocalName"
#define kOTABLEName @"TL ZZL"

#define kOTAWriteInterval    (0.0005)
#define kOTAReadInterval    (32)

#define kOTAWriteInterval_FAST      (0.0005)
#define kOTAWriteInterval_BALANCED  (0.002)
#define kOTAWriteInterval_STABLE    (0.005)

#define kOTAReadInterval_FAST       (32)
#define kOTAReadInterval_BALANCED   (16)
#define kOTAReadInterval_STABLE     (8)

#define kOTAConnectionTimeout       (25.0)
#define kOTAMaxDataPacketSize       (244)
#define kOTARetryMaxCount           (3)
#define kOTARetryDelay              (2.0)

#define kOTAServiceUUID @"00010203-0405-0607-0809-0a0b0c0d1912"
#define kOTAServiceUUID1 @"00010203-0405-0607-0809-0a0b0c0d1911"

#define kOTACharactUUID @"00010203-0405-0607-0809-0a0b0c0d2b12"

#define kSearchResult(peripheral, source) ([Device searchDeviceWith:peripheral inDeviceSource:source])


#define kURLWithName(name) ([NSString stringWithFormat:@"https://content-hk.vips100.com/v2/delivery/data/2687fdbb0d0a404894aefcbc37b778db/OTA_TEST_BIN/OTA_TEST_BIN_Customer1_FK/%@?token=",name])

#define kOtherURLWithName(name) ([NSString stringWithFormat:@"https://contentmsa-sh.vips100.com/v2/delivery/data/2687fdbb0d0a404894aefcbc37b778db/OTA_TEST_BIN/OTA_TEST_BIN_Customer1_FK/%@?token=",name])

#define kAppendPath(str) [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:str]


@interface Device : NSObject
@property (strong, nonatomic) CBPeripheral *peripheral; //!<
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *bleName;
@property (strong, nonatomic) NSNumber *rssiV;
@property (nonatomic, assign) BOOL isUpdata;
@property (nonatomic, assign) ARDeviceStateType state;
@property (nonatomic, strong) NSDictionary *dic;
- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral;
+ (instancetype)searchDeviceWith:(CBPeripheral *)per inDeviceSource:(NSArray *)source;
+ (NSMutableAttributedString *)getMutableString:(NSString *)uuidStr;
@end
