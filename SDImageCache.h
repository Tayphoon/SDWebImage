/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDImageCacheDelegate.h"

#if NS_BLOCKS_AVAILABLE
typedef void(^QueryDiskCacheBlock)(UIImage * image, NSString * key, NSDictionary * info);
#endif
@interface SDImageCache : NSObject
{
    NSMutableDictionary *memCache;
    NSString *diskCachePath;
    NSOperationQueue *cacheInQueue, *cacheOutQueue;
}

+ (SDImageCache *)sharedImageCache;
- (void)storeImage:(UIImage *)image forKey:(NSString *)key;
- (void)storeImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk;
- (void)storeImage:(UIImage *)image imageData:(NSData *)data forKey:(NSString *)key toDisk:(BOOL)toDisk;
- (BOOL)hasCacheForKey:(NSString*)key;
- (UIImage *)imageFromKey:(NSString *)key;
- (UIImage *)imageFromKey:(NSString *)key fromDisk:(BOOL)fromDisk;
- (void)queryDiskCacheForKey:(NSString *)key delegate:(id <SDImageCacheDelegate>)delegate userInfo:(NSDictionary *)info;
- (void)queryDiskCacheForKey:(NSString *)key userInfo:(NSDictionary *)info block:(QueryDiskCacheBlock)block;

- (void)removeImageForKey:(NSString *)key;
- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk;
- (void)clearMemory;
- (void)clearDisk;
- (void)cleanDisk;
- (int)getSize;

@end
