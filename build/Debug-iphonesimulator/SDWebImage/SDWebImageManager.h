/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageDownloaderDelegate.h"
#import "SDWebImageManagerDelegate.h"
#import "SDImageCacheDelegate.h"

typedef enum
{
    SDWebImageRetryFailed = 1 << 0,
    SDWebImageLowPriority = 1 << 1,
    SDWebImageCacheMemoryOnly = 1 << 2
} SDWebImageOptions;

#if NS_BLOCKS_AVAILABLE
typedef void(^SuccessBlock)(UIImage ** image);
typedef void(^FailureBlock)(NSError *error);
#endif

@interface SDWebImageManager : NSObject <SDWebImageDownloaderDelegate, SDImageCacheDelegate>
{
    NSMutableArray *downloadDelegates;
    NSMutableArray *downloaders;
    NSMutableArray *cacheDelegates;
    NSMutableArray *cacheURLs;
    NSMutableDictionary *downloaderForURL;
    NSMutableArray *failedURLs;
}

+ (id)sharedManager;
- (UIImage *)imageWithURL:(NSURL *)url;
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate;
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate options:(SDWebImageOptions)options;
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed __attribute__ ((deprecated)); // use options:SDWebImageRetryFailed instead
- (void)downloadWithURL:(NSURL *)url delegate:(id<SDWebImageManagerDelegate>)delegate retryFailed:(BOOL)retryFailed lowPriority:(BOOL)lowPriority __attribute__ ((deprecated)); // use options:SDWebImageRetryFailed|SDWebImageLowPriority instead
- (void)downloadWithURL:(NSURL *)url delegate:(id)delegate options:(SDWebImageOptions)options success:(SuccessBlock)success failure:(FailureBlock)failure;
- (void)cancelForDelegate:(id<SDWebImageManagerDelegate>)delegate;

@end
