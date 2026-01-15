#import <Foundation/Foundation.h>


@interface TelinkOtaWrapper : NSObject

+ (nonnull instancetype)sharedInstance;
- (BOOL)isDeviceConnected;
- (void)startOtaWithFilePath:(NSString *)filePath 
                readInterval:(NSInteger)readInterval
                 progressCallback:(void (^)(float progress))progressCallback 
                 completionCallback:(void (^)(BOOL success, NSString *errorMessage))completionCallback;
- (void)cancelOta;
- (void)setConnectedDevice:(NSString *)deviceId;

@end
