//
//  Document.m
//  MovieEdit
//
//  Created by Yosuke Suzuki on 2013/12/06.
//  Copyright (c) 2013年 Basuke. All rights reserved.
//

#import "Document.h"
#import <AVFoundation/AVFoundation.h>

static void *PlayerItemStatusContext = &PlayerItemStatusContext;
static void *PlayerRateContext = &PlayerRateContext;
static void *PlayerLayerReadyForDisplay = &PlayerLayerReadyForDisplay;

@interface Document ()

@property (strong) AVPlayer *player;
@property (strong) AVPlayerLayer *playerLayer;
@property (assign) double currentTime;
@property (readonly) double duration;
@property (assign) float volume;

@property (weak) IBOutlet NSProgressIndicator *loadingSpinner;
@property (weak) IBOutlet NSTextField *unplayableLabel;
@property (weak) IBOutlet NSTextField *noVideoLabel;
@property (weak) IBOutlet NSView *playerView;
@property (weak) IBOutlet NSButton *playPauseButton;
@property (weak) IBOutlet NSButton *fastForwardButton;
@property (weak) IBOutlet NSButton *rewindButton;
@property (weak) IBOutlet NSSlider *timeSlider;

@property (strong) id timeObserverToken;

- (IBAction)playPauseToggle:(id)sender;
- (IBAction)fastForward:(id)sender;
- (IBAction)rewind:(id)sender;

@end

@implementation Document

- (NSString *)windowNibName
{
	return @"Document";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
	[super windowControllerDidLoadNib:windowController];
	
	[[windowController window] setMovableByWindowBackground:YES];
	[[self.playerView layer] setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
	[self.loadingSpinner startAnimation:self];
	
	// Create the AVPlayer, add rate and status observers
	self.player = [[AVPlayer alloc] init];
	[self addObserver:self forKeyPath:@"player.rate" options:NSKeyValueObservingOptionNew context:PlayerRateContext];
	[self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:PlayerItemStatusContext];
	
	// Create an asset with our URL, asychronously load its tracks, its duration, and whether it's playable or protected.
	// When that loading is complete, configure a player to play the asset.
	AVURLAsset *asset = [AVAsset assetWithURL:[self fileURL]];
	NSArray *assetKeysToLoadAndTest = @[@"playable", @"hasProtectedContent", @"tracks", @"duration"];
	[asset loadValuesAsynchronouslyForKeys:assetKeysToLoadAndTest completionHandler:^(void) {
		
		// The asset invokes its completion handler on an arbitrary queue when loading is complete.
		// Because we want to access our AVPlayer in our ensuing set-up, we must dispatch our handler to the main queue.
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			
			[self setUpPlaybackOfAsset:asset withKeys:assetKeysToLoadAndTest];
			
		});
		
	}];
}

- (void)setUpPlaybackOfAsset:(AVAsset *)asset withKeys:(NSArray *)keys
{
	// This method is called when the AVAsset for our URL has completing the loading of the values of the specified array of keys.
	// We set up playback of the asset here.
	
	// First test whether the values of each of the keys we need have been successfully loaded.
	for (NSString *key in keys) {
		NSError *error = nil;
		
		if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
			[self stopLoadingAnimationAndHandleError:error];
			return;
		}
	}
	
	if (![asset isPlayable] || [asset hasProtectedContent]) {
		// We can't play this asset. Show the "Unplayable Asset" label.
		[self stopLoadingAnimationAndHandleError:nil];
		[self.unplayableLabel setHidden:NO];
		return;
	}
	
	// We can play this asset.
	// Set up an AVPlayerLayer according to whether the asset contains video.
	if ([[asset tracksWithMediaType:AVMediaTypeVideo] count] != 0)
	{
		// Create an AVPlayerLayer and add it to the player view if there is video, but hide it until it's ready for display
		AVPlayerLayer *newPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
		[newPlayerLayer setFrame:[[self.playerView layer] bounds]];
		[newPlayerLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
		[newPlayerLayer setHidden:YES];
		[[self.playerView layer] addSublayer:newPlayerLayer];
		self.playerLayer = newPlayerLayer;
		[self addObserver:self forKeyPath:@"playerLayer.readyForDisplay" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:PlayerLayerReadyForDisplay];
	}
	else
	{
		// This asset has no video tracks. Show the "No Video" label.
		[self stopLoadingAnimationAndHandleError:nil];
		[[self noVideoLabel] setHidden:NO];
	}
	
	// Create a new AVPlayerItem and make it our player's current item.
	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
	[self.player replaceCurrentItemWithPlayerItem:playerItem];
	
	[self setTimeObserverToken:[self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		[[self timeSlider] setDoubleValue:CMTimeGetSeconds(time)];
	}]];
	
}

- (void)stopLoadingAnimationAndHandleError:(NSError *)error
{
	[self.loadingSpinner stopAnimation:self];
	[self.loadingSpinner setHidden:YES];
	if (error)
	{
		[self presentError:error
			modalForWindow:[self windowForSheet]
				  delegate:nil
		didPresentSelector:NULL
			   contextInfo:nil];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == PlayerItemStatusContext)
	{
		AVPlayerStatus status = [change[NSKeyValueChangeNewKey] integerValue];
		BOOL enable = NO;
		switch (status)
		{
			case AVPlayerItemStatusUnknown:
				break;
			case AVPlayerItemStatusReadyToPlay:
				enable = YES;
				break;
			case AVPlayerItemStatusFailed:
				[self stopLoadingAnimationAndHandleError:[[self.player currentItem] error]];
				break;
		}
		
		[[self playPauseButton] setEnabled:enable];
		[[self fastForwardButton] setEnabled:enable];
		[[self rewindButton] setEnabled:enable];
	}
	else if (context == PlayerRateContext)
	{
		float rate = [change[NSKeyValueChangeNewKey] floatValue];
		if (rate != 1.f)
		{
			[[self playPauseButton] setTitle:@"Play"];
		}
		else
		{
			[[self playPauseButton] setTitle:@"Pause"];
		}
	}
	else if (context == PlayerLayerReadyForDisplay)
	{
		if ([change[NSKeyValueChangeNewKey] boolValue] == YES)
		{
			// The AVPlayerLayer is ready for display. Hide the loading spinner and show it.
			[self stopLoadingAnimationAndHandleError:nil];
			[self.playerLayer setHidden:NO];
		}
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)close
{
	[self.player pause];
	[self.player removeTimeObserver:[self timeObserverToken]];
	[self setTimeObserverToken:nil];
	[self removeObserver:self forKeyPath:@"player.rate"];
	[self removeObserver:self forKeyPath:@"player.currentItem.status"];
	if (self.playerLayer)
		[self removeObserver:self forKeyPath:@"playerLayer.readyForDisplay"];
	[super close];
}

+ (NSSet *)keyPathsForValuesAffectingDuration
{
	return [NSSet setWithObjects:@"player.currentItem", @"player.currentItem.status", nil];
}

- (double)duration
{
	AVPlayerItem *playerItem = [self.player currentItem];
	
	if ([playerItem status] == AVPlayerItemStatusReadyToPlay)
		return CMTimeGetSeconds([[playerItem asset] duration]);
	else
		return 0.f;
}

- (double)currentTime {
	return CMTimeGetSeconds([self.player currentTime]);
}

- (void)setCurrentTime:(double)time
{
	[self.player seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

+ (NSSet *)keyPathsForValuesAffectingVolume
{
	return [NSSet setWithObject:@"player.volume"];
}

- (float)volume
{
	return [self.player volume];
}

- (void)setVolume:(float)volume
{
	[self.player setVolume:volume];
}

- (IBAction)playPauseToggle:(id)sender
{
	if (self.player.rate != 1.f) {
		if (self.currentTime == [self duration])
			self.currentTime = 0.f;
		[self.player play];
	} else {
		[self.player pause];
	}
}

- (IBAction)fastForward:(id)sender
{
	if (self.player.rate < 2.f) {
		self.player.rate = 2.f;
	} else {
		self.player.rate = self.player.rate + 2.f;
	}
}

- (IBAction)rewind:(id)sender
{
	if (self.player.rate > -2.f) {
		self.player.rate = -2.f;
	} else {
		self.player.rate = self.player.rate - 2.f;
	}
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return YES;
}

@end