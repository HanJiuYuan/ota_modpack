#import <Foundation/Foundation.h>


@interface DownloadFiles : NSObject

@property (copy, nonatomic) void (^downloadCompleteBlock)(BOOL success, NSString * _Nullable filePath, NSString * _Nullable errorMessage);
@property (copy, nonatomic) void (^fileExistsBlock)(NSString * _Nonnull filePath, void(^ _Nonnull updateAction)(void), void(^ _Nonnull cancelAction)(void));
@property (copy, nonatomic) void (^otaProgressBlock)(float progress);
@property (copy, nonatomic) void (^otaCompleteBlock)(BOOL success, NSString * _Nullable errorMessage);


@property (strong, nonatomic) NSString * _Nullable downloadFileName;

// 添加可配置的OTA速度参数
@property (nonatomic, assign) NSTimeInterval otaWriteInterval;  // 写入间隔，默认0.01秒
@property (nonatomic, assign) NSInteger otaReadInterval;        // 读取间隔，默认8个包

// MTU相关
@property (nonatomic, assign) NSUInteger currentMTU;

- (void)downloadFileWithName:(NSString * _Nullable)fileName 
                         url:(NSString * _Nullable)urlString 
                  completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable filePath, NSString * _Nullable errorMessage))completion;

- (NSArray * _Nullable)listOtaFiles; 

- (BOOL)deleteFile:(NSString * _Nonnull)filePath error:(NSError * _Nullable * _Nullable)error;

- (void)startOtaWithFilePath:(NSString * _Nonnull)filePath 
                readInterval:(NSInteger)readInterval
              progressBlock:(void (^ _Nullable)(float progress))progressBlock 
              completeBlock:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completeBlock;

- (void)stopSendDataPack;

- (void)setupBluetoothEventHandlers;


- (void)clearBluetoothEventHandlers;


@end

