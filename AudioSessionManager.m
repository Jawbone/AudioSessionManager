//
//  AudioSessionManager.m
//
//  Copyright 2011 Jawbone Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//  http://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <AudioToolbox/AudioToolbox.h>

#import "AudioSessionManager.h"

@interface AudioSessionManager () {	// private
    BOOL         mPostNotifications;
	
	NSString	*mMode;
    
	BOOL		 mBluetoothDeviceAvailable;
	BOOL		 mHeadsetDeviceAvailable;
    
	NSArray		*mAvailableAudioDevices;

	__unsafe_unretained NSString *mAudioDevice;
}

@property (nonatomic, assign)		BOOL			 bluetoothDeviceAvailable;
@property (nonatomic, assign)		BOOL			 headsetDeviceAvailable;
@property (nonatomic, strong)		NSArray			*availableAudioDevices;

@end

NSString *kAudioSessionManagerDevicesAvailableChangedNotification = @"AudioSessionManagerDevicesAvailableChangedNotification";
NSString *kAudioSessionManagerAudioDeviceChangedNotification      = @"AudioSessionManagerAudioDeviceChangedNotification";

NSString *kAudioSessionManagerMode_Record       = @"AudioSessionManagerMode_Record";
NSString *kAudioSessionManagerMode_Playback     = @"AudioSessionManagerMode_Playback";

NSString *kAudioSessionManagerDevice_Headset    = @"AudioSessionManagerDevice_Headset";
NSString *kAudioSessionManagerDevice_Bluetooth  = @"AudioSessionManagerDevice_Bluetooth";
NSString *kAudioSessionManagerDevice_Phone      = @"AudioSessionManagerDevice_Phone";
NSString *kAudioSessionManagerDevice_Speaker    = @"AudioSessionManagerDevice_Speaker";

void AudioSessionManager_audioRouteChangedListener(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData);

// use normal logging if custom macros don't exist
#ifndef NSLogWarn
    #define NSLogWarn NSLog
#endif

#ifndef NSLogError
    #define NSLogError NSLog
#endif

@implementation AudioSessionManager

@synthesize headsetDeviceAvailable      = mHeadsetDeviceAvailable;
@synthesize bluetoothDeviceAvailable    = mBluetoothDeviceAvailable;
@synthesize audioDevice                 = mAudioDevice;
@synthesize availableAudioDevices       = mAvailableAudioDevices;

#pragma mark -
#pragma mark Singleton

#pragma mark - Singleton

#define SYNTHESIZE_SINGLETON_FOR_CLASS(classname) \
+ (classname*)sharedInstance { \
static classname* __sharedInstance; \
static dispatch_once_t onceToken; \
dispatch_once(&onceToken, ^{ \
__sharedInstance = [[classname alloc] init]; \
}); \
return __sharedInstance; \
}

SYNTHESIZE_SINGLETON_FOR_CLASS(AudioSessionManager);

- (id)init
{
	if ([super init])
	{
		mMode = kAudioSessionManagerMode_Playback;
	}
    
	return self;
}

#pragma mark private functions

- (void)postNotification:(NSString *)name
{
    if (!mPostNotifications)
        return;
    
	NSLogDebug(@"Posting Notification: %@", name);
	[[NSNotificationCenter defaultCenter] postNotificationName:name object:self];	
}

- (BOOL)configureAudioSession
{
	NSLogDebug(@"current mode: %@", mMode);
	
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	NSError *err;
	
	// close down our current session...	
	[audioSession setActive:NO error:nil];
	
    if ((mMode == kAudioSessionManagerMode_Record) && !audioSession.inputIsAvailable)
    {
		NSLogWarn(@"device does not support recording");
		return NO;
    }
        
    /*
     * Need to always use AVAudioSessionCategoryPlayAndRecord to redirect output audio per
     * the "Audio Session Programming Guide", so we only use AVAudioSessionCategoryPlayback when
     * !inputIsAvailable - which should only apply to iPod Touches without external mics.
     */
    NSString *audioCat = ((mMode == kAudioSessionManagerMode_Playback) && !audioSession.inputIsAvailable) ? 
        AVAudioSessionCategoryPlayback : AVAudioSessionCategoryPlayAndRecord;
    
	if (![audioSession setCategory:audioCat error:&err])
	{
		NSLogWarn(@"unable to set audioSession category: %@", err);
		return NO;
	}
	
	// Set session options based on the requested mode...	
	NSString *expectedRoute = nil;
	
	if (mAudioDevice == kAudioSessionManagerDevice_Phone)
	{
		expectedRoute = @"ReceiverAndMicrophone";
		// this should be the default.
		// if they have a headset plugged in it will go to the headset, but that's probably fine.
	}	
	else if (mAudioDevice == kAudioSessionManagerDevice_Speaker)
	{
		UInt32 overrideAudioRoute = kAudioSessionOverrideAudioRoute_Speaker;
		
		AudioSessionSetProperty (
								 kAudioSessionProperty_OverrideAudioRoute,
								 sizeof (overrideAudioRoute),
								 &overrideAudioRoute
								);
		
		expectedRoute = audioSession.inputIsAvailable ? @"SpeakerAndMicrophone" : @"Speaker";
	}	
	else if (mAudioDevice == kAudioSessionManagerDevice_Headset)
	{
		// is there aything to do here?
		expectedRoute = @"HeadsetInOut";	// could also be HeadphonesAndMicrophone...
	}	
	else if (mAudioDevice == kAudioSessionManagerDevice_Bluetooth)
	{
		UInt32 allowBluetoothInput = 1;
		
		AudioSessionSetProperty (
								 kAudioSessionProperty_OverrideCategoryEnableBluetoothInput,
								 sizeof (allowBluetoothInput),
								 &allowBluetoothInput
								);
		
		expectedRoute = @"HeadsetBT";
	}	
	else 
	{
		NSLogError(@"Invalid audioDevice: %@", mAudioDevice);
		return NO;
	}
	
	// If no bluetooth device is connected, request bluetooth so we will get device changed notifications...
	// OR if the user has actually selected bluetooth...	
	if (!self.bluetoothDeviceAvailable || mAudioDevice == kAudioSessionManagerDevice_Bluetooth)
	{
		UInt32 allowBluetoothInput = 1;
		
		AudioSessionSetProperty (
								 kAudioSessionProperty_OverrideCategoryEnableBluetoothInput,
								 sizeof (allowBluetoothInput),
								 &allowBluetoothInput
								);
		
	}
	
	// Set our session to active...	
	if (![audioSession setActive:YES error:&err])
	{
		NSLogWarn(@"unable to set audio session active: %@", err);
		return NO;
	}
	
	// Set to speaker if needed...	
	if (mAudioDevice == kAudioSessionManagerDevice_Speaker)
	{
		UInt32 overrideAudioRoute = kAudioSessionOverrideAudioRoute_Speaker;
		
		AudioSessionSetProperty (
								 kAudioSessionProperty_OverrideAudioRoute,
								 sizeof (overrideAudioRoute),
								 &overrideAudioRoute
								);
	}
	
	// Validate that we ended up with the route we expected...	    
	if (![self.audioRoute isEqualToString:expectedRoute] && 
        !([expectedRoute isEqualToString:@"HeadsetInOut"] && [self.audioRoute isEqualToString:@"HeadphonesAndMicrophone"]))
	{
		NSLogError(@"Selecting %@: expected route %@, but got route %@", mAudioDevice, expectedRoute, self.audioRoute);
		
		// We may have lost a route without knowing about it, if so, make it go away...		
		if ([expectedRoute isEqualToString:@"HeadsetBT"])
		{
			self.bluetoothDeviceAvailable = NO;
			
			// technically recursive, but we shouldn't loop.
			
			self.audioDevice = kAudioSessionManagerDevice_Speaker;	// switch to the speaker...
		}
		
		if ([expectedRoute hasPrefix:@"Head"])
		{
			self.headsetDeviceAvailable = NO;

			// technically recursive, but we shouldn't loop.
	
			self.audioDevice = kAudioSessionManagerDevice_Speaker;	// switch to the speaker...
		}			
	}
	
	// now, wire up our route change check...	
	AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, &AudioSessionManager_audioRouteChangedListener, (__bridge void *)(self));
	
	// Display our current route...	
	NSLogDebug(@"current route: %@", self.audioRoute);
	
	return YES;
}

- (BOOL)detectAvailableDevices
{
	// called on startup to initialize the devices that are available...	
	NSLogDebug(@"detectAvailableDevices");
	
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	NSError *err;
	
	// close down our current session...	
	[audioSession setActive:NO error:nil];
	
	// Open a session and see what our default is...	
	if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&err])
	{
		NSLogWarn(@"unable to set audioSession category: %@", err);
		return NO;
	}
	
	// Check for a wired headset...	
	self.headsetDeviceAvailable = [self.audioRoute isEqualToString:@"HeadsetInOut"] || [self.audioRoute isEqualToString:@"HeadphonesAndMicrophone"];
	
	if (self.headsetDeviceAvailable)
		NSLogDebug(@"Found Headset");
	
	// Check for a bluetooth headset...	
	UInt32 allowBluetoothInput = 1;
	
	AudioSessionSetProperty (
							 kAudioSessionProperty_OverrideCategoryEnableBluetoothInput,
							 sizeof (allowBluetoothInput),
							 &allowBluetoothInput
							);
	
	self.bluetoothDeviceAvailable = [self.audioRoute isEqualToString:@"HeadsetBT"];
	
	if (self.bluetoothDeviceAvailable)
		NSLogDebug(@"Found Bluetooth");
	
	return YES;
}

- (void)setAudioDeviceValue:(NSString *)value
{
	if (mAudioDevice != value)
	{
		mAudioDevice = value;
		[self postNotification:kAudioSessionManagerAudioDeviceChangedNotification];
	}
}

- (void)onAudioRouteChangedWithReason:(int)reason oldRoute:(NSString *)oldRoute
{
	NSString *newRoute = self.audioRoute;
	
	NSLogDebug(@"onAudioRouteChangedWithReason:%d oldRoute:\"%@\" newRoute:\"%@\"", reason, oldRoute, newRoute);
	
	if (reason == kAudioSessionRouteChangeReason_NewDeviceAvailable)
	{
		NSLogDebug(@"device added: %@", newRoute);
		
		if ([newRoute isEqualToString:@"HeadsetBT"])
		{
			self.bluetoothDeviceAvailable = YES;
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
			[self configureAudioSession];
		}		
		else if ([newRoute isEqualToString:@"HeadsetInOut"] || [newRoute isEqualToString:@"HeadphonesAndMicrophone"])
		{
			self.headsetDeviceAvailable = YES;
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
			[self configureAudioSession];
		}		
		else 
		{
			NSLogWarn(@"Unknown audioDevice added: %@", newRoute);
		}		
	}	
	else if ((kAudioSessionRouteChangeReason_OldDeviceUnavailable == reason)
                || (kAudioSessionRouteChangeReason_NoSuitableRouteForCategory == reason)    // ex: iPod Touch with headset mic unplugged
				|| reason > 100)                                                            // Sometimes we get a HUGE number when disconnecting BT, wo let's roll with it.
	{
		NSLogDebug(@"device removed: %@", oldRoute);		
		
		//Need to remove the old device first, else the set of available devices is wrong later
		
		// remove the old device from our available devices...		
		if ([oldRoute isEqualToString:@"HeadsetBT"])
		{
			self.bluetoothDeviceAvailable = NO;
		}		
		else if ([oldRoute isEqualToString:@"HeadsetInOut"] || [oldRoute isEqualToString:@"HeadphonesAndMicrophone"])
		{
			self.headsetDeviceAvailable = NO;
		}
		else 
		{
			NSLogWarn(@"Unknown audioDevice removed: %@", oldRoute);
		}		
		
		// set the audioDevice based on the new route....		
		if ([newRoute isEqualToString:@"HeadsetBT"])	
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
			[self configureAudioSession];
		}		
		else if ([newRoute isEqualToString:@"HeadsetInOut"] || [newRoute isEqualToString:@"HeadphonesAndMicrophone"])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
			[self configureAudioSession];
		}		
		else if ([newRoute isEqualToString:@"ReceiverAndMicrophone"])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Phone];
			[self configureAudioSession];
		}		
		else if ([newRoute isEqualToString:@"SpeakerAndMicrophone"] || [newRoute isEqualToString:@"Speaker"])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
			[self configureAudioSession];
		}		
		else 
		{
			NSLogWarn(@"Unknown new route: %@", newRoute);
		}		
	}
	else
	{
		NSLogDebug(@"Changed route for some reason not related to adding or removing devices");
		
		if ([newRoute isEqualToString:@"HeadsetBT"])			
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
		
		else if ([newRoute isEqualToString:@"HeadsetInOut"] || [newRoute isEqualToString:@"HeadphonesAndMicrophone"])
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
		
		else if ([newRoute isEqualToString:@"ReceiverAndMicrophone"])
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Phone];
		
		else if ([newRoute isEqualToString:@"SpeakerAndMicrophone"] || [newRoute isEqualToString:@"Speaker"])
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
		
		else 
		{
			NSLogWarn(@"Unknown new route: %@", newRoute);
		}		
	}
}

#pragma mark public methods

- (void)startAndPostNotifications:(BOOL)postNotifications
{
    mPostNotifications = postNotifications;
    
	[self detectAvailableDevices];
	
	// Assign a default output device...	
	if (self.bluetoothDeviceAvailable)
		[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
	
	else if (self.headsetDeviceAvailable)
		[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
	
	else
		[self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
	
	[self configureAudioSession];
	
	NSLogDebug(@"audioDevice = %@", mAudioDevice);
}

#pragma mark public methods/properties

- (BOOL)changeMode:(NSString *)value
{
	if (mMode == value)
		return YES;
	
	mMode = value;
	
	return [self configureAudioSession];
}

- (NSString *)audioRoute
{
	CFStringRef data = NULL;
	UInt32 dataSize = sizeof(data);
	
	AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &dataSize, &data);
	
	return (data != NULL && CFStringGetLength(data) > 0) ? (NSString *)CFBridgingRelease(data) : @"Unknown";
}

- (void)setBluetoothDeviceAvailable:(BOOL)value
{
	if (mBluetoothDeviceAvailable == value)
		return;
	
	mBluetoothDeviceAvailable = value;
	
	self.availableAudioDevices = nil;
		
	[self postNotification:kAudioSessionManagerDevicesAvailableChangedNotification];
}

- (void)setHeadsetDeviceAvailable:(BOOL)value
{
	if (mHeadsetDeviceAvailable == value)
		return;
	
	mHeadsetDeviceAvailable = value;
	
	self.availableAudioDevices = nil;
	
	[self postNotification:kAudioSessionManagerDevicesAvailableChangedNotification];
}

- (void)setAudioDevice:(NSString *)value
{
	if (mAudioDevice == value)
		return;
	
	mAudioDevice = value;
	
	[self configureAudioSession];
	
	[self postNotification:kAudioSessionManagerAudioDeviceChangedNotification];
}

- (BOOL)phoneDeviceAvailable
{
	return YES;
}

- (BOOL)speakerDeviceAvailable
{
	return YES;
}

- (NSArray *)availableAudioDevices
{
	if (!mAvailableAudioDevices)
	{
		NSMutableArray *devices = [[NSMutableArray alloc] initWithCapacity:4];
		
		if (self.bluetoothDeviceAvailable)
			[devices addObject:kAudioSessionManagerDevice_Bluetooth];

		if (self.headsetDeviceAvailable)
			[devices addObject:kAudioSessionManagerDevice_Headset];

		if (self.speakerDeviceAvailable)
			[devices addObject:kAudioSessionManagerDevice_Speaker];

		if (self.phoneDeviceAvailable)
			[devices addObject:kAudioSessionManagerDevice_Phone];
		
		self.availableAudioDevices = devices;
	}
	
	return mAvailableAudioDevices;
}

@end

#pragma mark Listener Thunks (C)

void AudioSessionManager_audioRouteChangedListener(void *inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void *inData)
{
	AudioSessionManager *instance = (__bridge AudioSessionManager *)inClientData;
	
	CFDictionaryRef routeChangeDictionary = inData;
	
	// extract the route change reason...
	
	CFNumberRef routeChangeReasonRef = CFDictionaryGetValue (routeChangeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
	
	SInt32 routeChangeReason = kAudioSessionRouteChangeReason_Unknown;
	
	if (routeChangeReasonRef)
		CFNumberGetValue (routeChangeReasonRef, kCFNumberSInt32Type, &routeChangeReason);
	
	// extract the old route..
	
	CFStringRef oldRoute = CFDictionaryGetValue(routeChangeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_OldRoute));
	
	// pass it off to our Objective-C handler...
	
	[instance onAudioRouteChangedWithReason:routeChangeReason oldRoute:(__bridge NSString *)oldRoute];
}

