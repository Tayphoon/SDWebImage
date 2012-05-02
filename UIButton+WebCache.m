/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIButton+WebCache.h"
#import "SDWebImageManager.h"

@implementation UIButton (WebCache)

- (void)setImageWithURL:(NSURL *)url
{
    [self setImageWithURL:url placeholderImage:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder
{
    [self setImageWithURL:url placeholderImage:placeholder options:0];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options
{
    SDWebImageManager *manager = [SDWebImageManager sharedManager];

    // Remove in progress downloader from queue
    [manager cancelForDelegate:self];

    [self setImage:placeholder forState:UIControlStateNormal];

    if (url)
    {
        [manager downloadWithURL:url delegate:self options:options];
    }
}

#if NS_BLOCKS_AVAILABLE
- (void)setImageWithURL:(NSURL *)url success:(SuccessBlock)success failure:(FailureBlock)failure;
{
    [self setImageWithURL:url placeholderImage:nil success:success failure:failure];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder success:(SuccessBlock)success failure:(FailureBlock)failure;
{
    [self setImageWithURL:url placeholderImage:placeholder options:0 success:success failure:failure];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options success:(SuccessBlock)success failure:(FailureBlock)failure;
{
    SDWebImageManager *manager = [SDWebImageManager sharedManager];

    // Remove in progress downloader from queue
    [manager cancelForDelegate:self];

    [self setImage:placeholder forState:UIControlStateNormal];

    if (url)
    {
        [manager downloadWithURL:url delegate:self options:options success:success failure:failure];
    }
}
#endif

- (void)cancelCurrentImageLoad
{
    [[SDWebImageManager sharedManager] cancelForDelegate:self];
}

- (void)webImageManager:(SDWebImageManager *)imageManager didFinishWithImage:(UIImage *)image
{
    [self setImage:image forState:UIControlStateNormal];
    [self setImage:image forState:UIControlStateSelected];
    [self setImage:image forState:UIControlStateHighlighted];
}

@end
