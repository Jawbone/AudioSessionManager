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
NSString *kAudioSessionManagerShowBluetoothNotification           = @"AudioSessionManagerShowBluetoothNotification";
NSString *kAudioSessionManagerHideBluetoothNotification           = @"AudioSessionManagerHideBluetoothNotification";

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
	
    if ((mMode == kAudioSessionManagerMode_Record) && !audioSession.inputAvailable)
    {
		NSLogWarn(@"device does not support recording");
		return NO;
    }
    
    /*
     * Need to always use AVAudioSessionCategoryPlayAndRecord to redirect output audio per
     * the "Audio Session Programming Guide", so we only use AVAudioSessionCategoryPlayback when
     * !inputIsAvailable - which should only apply to iPod Touches without external mics.
     */
    NSString *audioCat = ((mMode == kAudioSessionManagerMode_Playback) && !audioSession.inputAvailable) ?
    AVAudioSessionCategoryPlayback : AVAudioSessionCategoryPlayAndRecord;
    
	if (![audioSession setCategory:audioCat withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:&err])
	{
		NSLogWarn(@"unable to set audioSession category: %@", err);
		return NO;
	}
	
    // Set our session to active...
	if (![audioSession setActive:YES error:&err])
	{
		NSLogWarn(@"unable to set audio session active: %@", err);
		return NO;
	}
    
	if (mAudioDevice == kAudioSessionManagerDevice_Speaker)
	{
        // replace AudiosessionSetProperty (deprecated from iOS7) with AVAudioSession overrideOutputAudioPort
		[audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];
	}
	
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
    
    // start a new audio session. Without activation, the default route will always be (inputs: null, outputs: Speaker)
    [audioSession setActive:YES error:nil];
    
	// Open a session and see what our default is...
	if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:&err]) {
		NSLogWarn(@"unable to set audioSession category: %@", err);
		return NO;
	}
	
	// Check for a wired headset...
    AVAudioSessionRouteDescription *currentRoute = [audioSession currentRoute];
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        if ([[output portType] isEqualToString:AVAudioSessionPortHeadphones]) {
            self.headsetDeviceAvailable = YES;
            [self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
        } else if ([[output portType] isEqualToString:AVAudioSessionPortBluetoothHFP] || [[output portType] isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
            self.bluetoothDeviceAvailable = YES;
            [self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
        } else {
            [self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
        }
    }
    // In case both headphones and bluetooth are connected, detect bluetooth by inputs
    // Condition: iOS7 and Bluetooth input available
    if ([[UIDevice currentDevice].systemVersion integerValue] >= 7) {
        for (AVAudioSessionPortDescription *input in [audioSession availableInputs]){
            if ([[input portType] isEqualToString:AVAudioSessionPortBluetoothHFP]){
                self.bluetoothDeviceAvailable = YES;
                break;
            }
        }
    }
    
	if (self.headsetDeviceAvailable)
		NSLogDebug(@"Found Headset");
	
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
		
		if ([newRoute isEqualToString:kAudioSessionManagerDevice_Bluetooth])
		{
			self.bluetoothDeviceAvailable = YES;
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
			[self configureAudioSession];
		}
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Headset])
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
		if ([newRoute isEqualToString:kAudioSessionManagerDevice_Bluetooth])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
			[self configureAudioSession];
		}
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Headset])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
			[self configureAudioSession];
		}
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Phone])
		{
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Phone];
			[self configureAudioSession];
		}
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Speaker])
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
		
		if ([newRoute isEqualToString:kAudioSessionManagerDevice_Bluetooth]) {
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
        }
		
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Headset]) {
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
        }
		
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Phone]) {
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Phone];
        }
		
		else if ([newRoute isEqualToString:kAudioSessionManagerDevice_Speaker]) {
			[self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
		}
        
		else {
			NSLogWarn(@"Unknown new route: %@", newRoute);
		}
	}
}

// Replace onAudioRouteChangedWithReason with currentRouteChanged, supports from iOS6
- (void)currentRouteChanged:(NSNotification *)notification
{
    NSInteger changeReason = [[notification.userInfo objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    AVAudioSessionRouteDescription *oldRoute = [notification.userInfo objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    NSString *oldOutput = [[oldRoute.outputs objectAtIndex:0] portType];
    AVAudioSessionRouteDescription *newRoute = [[AVAudioSession sharedInstance] currentRoute];
    NSString *newOutput = [[newRoute.outputs objectAtIndex:0] portType];
    
    switch (changeReason) {
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            if ([oldOutput isEqualToString:AVAudioSessionPortHeadphones]) {
                
                self.headsetDeviceAvailable = NO;
                // Special Scenario:
                // when headphones are plugged in before the call and plugged out during the call
                // route will change to {input: MicrophoneBuiltIn, output: Receiver}
                // manually refresh session and support all devices again.
                [[AVAudioSession sharedInstance] setActive:NO error:nil];
                [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:nil];
                [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVoiceChat error:nil];
                [[AVAudioSession sharedInstance] setActive:YES error:nil];
                
                
            } else if ([self isBluetoothDevice:oldOutput]) {
                
                self.bluetoothDeviceAvailable = NO;
                
                // Additional checking for iOS7 devices (more accurate)
                // when multiple blutooth devices connected, one is no longer available does not mean no bluetooth available
                if ([[UIDevice currentDevice].systemVersion integerValue] >= 7) {
                    BOOL showBluetooth = NO;
                    NSArray *inputs = [[AVAudioSession sharedInstance] availableInputs];
                    for (AVAudioSessionPortDescription *input in inputs){
                        if ([self isBluetoothDevice:[input portType]]){
                            showBluetooth = YES;
                            break;
                        }
                    }
                    if (!showBluetooth) {
                        [self postNotification:kAudioSessionManagerHideBluetoothNotification];
                    }
                }
            }
            // set the audioDevice based on the new route....
            if ([self isBluetoothDevice:newOutput]) {
                
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
                
            } else if ([newOutput isEqualToString:AVAudioSessionPortHeadphones]) {
                
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
                
            } else if ([newOutput isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
                
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Phone];
                
            } else if ([newOutput isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
                
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Speaker];
                
            } else {
                NSLogWarn(@"Unknown new route: %@", newRoute);
            }
            break;
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            
            if ([self isBluetoothDevice:newOutput]) {
                
                self.bluetoothDeviceAvailable = YES;
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Bluetooth];
                [self postNotification:kAudioSessionManagerShowBluetoothNotification];
                
            } else if ([newOutput isEqualToString:AVAudioSessionPortHeadphones]) {
                
                self.headsetDeviceAvailable = YES;
                [self setAudioDeviceValue:kAudioSessionManagerDevice_Headset];
            }
            break;
            
        case AVAudioSessionRouteChangeReasonOverride:
            
            if ([[UIDevice currentDevice].systemVersion integerValue] >= 7) {
                BOOL showBluetooth = NO;
                NSArray *inputs = [[AVAudioSession sharedInstance] availableInputs];
                for (AVAudioSessionPortDescription *input in inputs){
                    if ([[input portType] isEqualToString:AVAudioSessionPortBluetoothHFP]){
                        showBluetooth = YES;
                        break;
                    }
                }
                if (!showBluetooth) {
                    [self postNotification:kAudioSessionManagerHideBluetoothNotification];
                }
            } else if ([newOutput isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
                
                [self postNotification:kAudioSessionManagerHideBluetoothNotification];
            }
            break;
            
        default:
            break;
    }
}

- (BOOL)isBluetoothDevice:(NSString*)portType {
    
    return ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
            [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
            [portType isEqualToString:AVAudioSessionPortBluetoothLE]);
}

#pragma mark public methods

- (void)startAndPostNotifications:(BOOL)postNotifications
{
    mPostNotifications = postNotifications;
    
	[self detectAvailableDevices];
	
	[self configureAudioSession];
	
	NSLogDebug(@"audioDevice = %@", mAudioDevice);
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(currentRouteChanged:)
                                                 name:AVAudioSessionRouteChangeNotification object:nil];
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
	AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    NSString *output = [[currentRoute.outputs objectAtIndex:0] portType];
    
    if ([output isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
        return kAudioSessionManagerDevice_Phone;
    } else if ([output isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
        return kAudioSessionManagerDevice_Speaker;
    } else if ([output isEqualToString:AVAudioSessionPortHeadphones]) {
        return kAudioSessionManagerDevice_Headset;
    } else if ([output isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
               [output isEqualToString:AVAudioSessionPortBluetoothHFP] ||
               [output isEqualToString:AVAudioSessionPortBluetoothLE]) {
        return kAudioSessionManagerDevice_Bluetooth;
    } else {
        return @"Unknown Device";
    }
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