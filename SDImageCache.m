/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDImageCache.h"
#import "SDWebImageDecoder.h"
#import <CommonCrypto/CommonDigest.h>
#import "SDWebImageDecoder.h"

static NSInteger cacheMaxCacheAge = 60*60*24*7; // 1 week

static SDImageCache *instance;

@implementation SDImageCache

#pragma mark NSObject

- (id)init
{
    if ((self = [super init]))
    {
        // Init the memory cache
        memCache = [[NSMutableDictionary alloc] init];

        // Init the disk cache
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        diskCachePath = SDWIReturnRetained([[paths objectAtIndex:0] stringByAppendingPathComponent:@"ImageCache"]);

        if (![[NSFileManager defaultManager] fileExistsAtPath:diskCachePath])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:diskCachePath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:NULL];
        }

        // Init the operation queue
        cacheInQueue = [[NSOperationQueue alloc] init];
        cacheInQueue.maxConcurrentOperationCount = 1;
        cacheOutQueue = [[NSOperationQueue alloc] init];
        cacheOutQueue.maxConcurrentOperationCount = 1;

#if TARGET_OS_IPHONE
        // Subscribe to app events
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanDisk)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
        UIDevice *device = [UIDevice currentDevice];
        if ([device respondsToSelector:@selector(isMultitaskingSupported)] && device.multitaskingSupported)
        {
            // When in background, clean memory in order to have less chance to be killed
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(clearMemory)
                                                         name:UIApplicationDidEnterBackgroundNotification
                                                       object:nil];
        }
#endif
#endif
    }

    return self;
}

- (void)dealloc
{
    SDWISafeRelease(memCache);
    SDWISafeRelease(diskCachePath);
    SDWISafeRelease(cacheInQueue);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    SDWISuperDealoc;
}

#pragma mark SDImageCache (class methods)

+ (SDImageCache *)sharedImageCache
{
    if (instance == nil)
    {
        instance = [[SDImageCache alloc] init];
    }

    return instance;
}

#pragma mark SDImageCache (private)

- (NSString*)MD5FromString:(NSString*)data {
	// Create pointer to the string as UTF8
	const char* ptr = [data UTF8String];
    
	// Create byte array of unsigned chars
	unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    
	// Create 16 byte MD5 hash value, store in buffer
	CC_MD5(ptr, (CC_LONG) strlen(ptr), md5Buffer);
    
	// Convert MD5 value in the buffer to NSString of hex values
	NSMutableString* output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
		[output appendFormat:@"%02x",md5Buffer[i]];
	}
    
	return output;
}

- (NSString*)getPathComponentForKey:(NSString*)key {
    NSString * fileDir = [key stringByDeletingLastPathComponent];

    if (![fileDir hasPrefix:@"http://"] && [fileDir hasPrefix:@"http:/"])
        fileDir = [fileDir stringByReplacingOccurrencesOfString:@"http:/" withString:@"http://"];
    return fileDir;
}

- (NSString *)cachePathForKey:(NSString *)key
{
    BOOL isKeyPathToFolder = NO;
    NSString * filename = [key lastPathComponent];
    NSString * fileDir = [self getPathComponentForKey:key];
    NSString * fileExtension = [filename pathExtension];

    filename = [self MD5FromString:filename];    
    
    isKeyPathToFolder = [fileExtension length] == 0;

    fileDir = (isKeyPathToFolder) ? [self MD5FromString:key] : [self MD5FromString:fileDir];
        
    return (isKeyPathToFolder) ? [diskCachePath stringByAppendingPathComponent:fileDir] :
                                 [[diskCachePath stringByAppendingPathComponent:fileDir] stringByAppendingPathComponent:filename];
}

- (void)storeKeyWithDataToDisk:(NSArray *)keyAndData
{
    // Can't use defaultManager another thread
    NSFileManager *fileManager = [[NSFileManager alloc] init];

    NSString *key = [keyAndData objectAtIndex:0];
    NSData *data = [keyAndData count] > 1 ? [keyAndData objectAtIndex:1] : nil;
    
    NSString * imageCachePath = [self cachePathForKey:key];
    NSString * imageCacheDirPath = [imageCachePath stringByDeletingLastPathComponent];

    if (![fileManager fileExistsAtPath: imageCacheDirPath]) {
        [fileManager createDirectoryAtPath:imageCacheDirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }

    if (data)
    {
        [fileManager createFileAtPath:imageCachePath contents:data attributes:nil];
    }
    else
    {
        // If no data representation given, convert the UIImage in JPEG and store it
        // This trick is more CPU/memory intensive and doesn't preserve alpha channel
        UIImage *image = SDWIReturnRetained([self imageFromKey:key fromDisk:YES]); // be thread safe with no lock
        if (image)
        {
#if TARGET_OS_IPHONE
            [fileManager createFileAtPath:imageCachePath contents:UIImageJPEGRepresentation(image, (CGFloat)1.0) attributes:nil];
#else
            NSArray*  representations  = [image representations];
            NSData* jpegData = [NSBitmapImageRep representationOfImageRepsInArray: representations usingType: NSJPEGFileType properties:nil];
            [fileManager createFileAtPath:imageCachePath contents:jpegData attributes:nil];
#endif
            SDWIRelease(image);
        }
    }

    SDWIRelease(fileManager);
}

- (void)notifyDelegate:(NSDictionary *)arguments
{
    NSString *key = [arguments objectForKey:@"key"];
    id <SDImageCacheDelegate> delegate = [arguments objectForKey:@"delegate"];
    QueryDiskCacheBlock block = [arguments objectForKey:@"block"];
    NSDictionary *info = [arguments objectForKey:@"userInfo"];
    UIImage *image = [arguments objectForKey:@"image"];

    if (image)
    {
        [memCache setObject:image forKey:key];

        if ([delegate respondsToSelector:@selector(imageCache:didFindImage:forKey:userInfo:)])
        {
            [delegate imageCache:self didFindImage:image forKey:key userInfo:info];
        }
        else if(block) {
            block(image, key, info);
        }
    }
    else
    {
        if ([delegate respondsToSelector:@selector(imageCache:didNotFindImageForKey:userInfo:)])
        {
            [delegate imageCache:self didNotFindImageForKey:key userInfo:info];
        }
        else if(block) {
            block(nil, key, info);
        }
    }
}

- (void)queryDiskCacheOperation:(NSDictionary *)arguments
{
    NSString *key = [arguments objectForKey:@"key"];
    NSMutableDictionary *mutableArguments = SDWIReturnAutoreleased([arguments mutableCopy]);

    UIImage *image = SDScaledImageForPath(key, [NSData dataWithContentsOfFile:[self cachePathForKey:key]]);

    if (image)
    {
        UIImage *decodedImage = [UIImage decodedImageWithImage:image];
        if (decodedImage)
        {
            image = decodedImage;
        }

        [mutableArguments setObject:image forKey:@"image"];
    }

    [self performSelectorOnMainThread:@selector(notifyDelegate:) withObject:mutableArguments waitUntilDone:NO];
}

#pragma mark ImageCache

- (void)storeImage:(UIImage *)image imageData:(NSData *)data forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    if (!image || !key)
    {
        return;
    }

    [memCache setObject:image forKey:key];

    if (toDisk)
    {
        NSArray *keyWithData;
        if (data)
        {
            keyWithData = [NSArray arrayWithObjects:key, data, nil];
        }
        else
        {
            keyWithData = [NSArray arrayWithObjects:key, nil];
        }

        NSInvocationOperation *operation = SDWIReturnAutoreleased([[NSInvocationOperation alloc] initWithTarget:self
                                                                                                       selector:@selector(storeKeyWithDataToDisk:)
                                                                                                         object:keyWithData]);
        [cacheInQueue addOperation:operation];
    }
}

- (void)storeImage:(UIImage *)image forKey:(NSString *)key
{
    [self storeImage:image imageData:nil forKey:key toDisk:YES];
}

- (void)storeImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    [self storeImage:image imageData:nil forKey:key toDisk:toDisk];
}

- (BOOL)hasCacheForKey:(NSString*)key {
    UIImage *image = [memCache objectForKey:key];
    if(image) {
        return YES;
    }
    return [[NSFileManager defaultManager] fileExistsAtPath:[self cachePathForKey:key]];
}

- (UIImage *)imageFromKey:(NSString *)key {
    return [self imageFromKey:key fromDisk:YES];
}

- (UIImage *)imageFromKey:(NSString *)key fromDisk:(BOOL)fromDisk
{
    if (key == nil)
    {
        return nil;
    }

    UIImage *image = [memCache objectForKey:key];

    if (!image && fromDisk)
    {
        image = SDScaledImageForPath(key, [NSData dataWithContentsOfFile:[self cachePathForKey:key]]);
        if (image)
        {
            [memCache setObject:image forKey:key];
        }
    }

    return image;
}

- (void)queryDiskCacheForKey:(NSString *)key delegate:(id <SDImageCacheDelegate>)delegate userInfo:(NSDictionary *)info
{
    if (!delegate)
    {
        return;
    }

    if (!key)
    {
        if ([delegate respondsToSelector:@selector(imageCache:didNotFindImageForKey:userInfo:)])
        {
            [delegate imageCache:self didNotFindImageForKey:key userInfo:info];
        }
        return;
    }

    // First check the in-memory cache...
    UIImage *image = [memCache objectForKey:key];
    if (image)
    {
        // ...notify delegate immediately, no need to go async
        if ([delegate respondsToSelector:@selector(imageCache:didFindImage:forKey:userInfo:)])
        {
            [delegate imageCache:self didFindImage:image forKey:key userInfo:info];
        }
        return;
    }

    NSMutableDictionary *arguments = [NSMutableDictionary dictionaryWithCapacity:3];
    [arguments setObject:key forKey:@"key"];
    [arguments setObject:delegate forKey:@"delegate"];
    if (info)
    {
        [arguments setObject:info forKey:@"userInfo"];
    }
    NSInvocationOperation *operation = SDWIReturnAutoreleased([[NSInvocationOperation alloc] initWithTarget:self
                                                                                                   selector:@selector(queryDiskCacheOperation:)
                                                                                                     object:arguments]);
    [cacheOutQueue addOperation:operation];
}

- (void)queryDiskCacheForKey:(NSString *)key userInfo:(NSDictionary *)info block:(QueryDiskCacheBlock)block {
    if (!block)
    {
        return;
    }
    
    if (!key)
    {
        block(nil, key, info);
        return;
    }
    
    // First check the in-memory cache...
    UIImage *image = [memCache objectForKey:key];
    if (image)
    {
        block(image, key, info);
        return;
    }
    
    NSMutableDictionary *arguments = [NSMutableDictionary dictionaryWithCapacity:3];
    [arguments setObject:key forKey:@"key"];
    [arguments setObject:[block copy] forKey:@"block"];
    if (info)
    {
        [arguments setObject:info forKey:@"userInfo"];
    }
    NSInvocationOperation *operation = SDWIReturnAutoreleased([[NSInvocationOperation alloc] initWithTarget:self
                                                                                                   selector:@selector(queryDiskCacheOperation:)
                                                                                                     object:arguments]);
    [cacheOutQueue addOperation:operation];
}

- (void)removeImageForKey:(NSString *)key
{
    [self removeImageForKey:key fromDisk:YES];
}

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk
{
    if (key == nil)
    {
        return;
    }

    [memCache removeObjectForKey:key];

    if (fromDisk)
    {
        NSError * error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[self cachePathForKey:key] error:&error];
        if(error) {
            NSLog(@"Error delete cached files: %@", error);
        }
    }
}

- (void)clearMemory
{
    [cacheInQueue cancelAllOperations]; // won't be able to complete
    [memCache removeAllObjects];
}

- (void)clearDisk
{
    [cacheInQueue cancelAllOperations];
    [[NSFileManager defaultManager] removeItemAtPath:diskCachePath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:diskCachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
}

- (void)cleanDisk
{
    NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-cacheMaxCacheAge];
    NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:diskCachePath];
    for (NSString *fileName in fileEnumerator)
    {
        NSString *filePath = [diskCachePath stringByAppendingPathComponent:fileName];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        if ([[[attrs fileModificationDate] laterDate:expirationDate] isEqualToDate:expirationDate])
        {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    }
}

-(int)getSize
{
    int size = 0;
    NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:diskCachePath];
    for (NSString *fileName in fileEnumerator)
    {
        NSString *filePath = [diskCachePath stringByAppendingPathComponent:fileName];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        size += [attrs fileSize];
    }
    return size;
}

@end
