//
//  AudioSessionManager.h
//
//  This module routes audio output depending on device availability using the 
//  following priorities: bluetooth, wired headset, speaker.
//
//  It also notifies interested listeners of audio change events (optional).
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

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern NSString *kAudioSessionManagerDevicesAvailableChangedNotification;
extern NSString *kAudioSessionManagerAudioDeviceChangedNotification;
extern NSString *kAudioSessionManagerShowBluetoothNotification;
extern NSString *kAudioSessionManagerHideBluetoothNotification;

extern NSString *kAudioSessionManagerMode_Record;
extern NSString *kAudioSessionManagerMode_Playback;

extern NSString *kAudioSessionManagerDevice_Headset;
extern NSString *kAudioSessionManagerDevice_Bluetooth;
extern NSString *kAudioSessionManagerDevice_Phone;
extern NSString *kAudioSessionManagerDevice_Speaker;

@interface AudioSessionManager : NSObject

/**
 The current audio route as reported by AudioSessionGetProperty(kAudioSessionProperty_AudioRoute).
 Valid values at this time are: 
    - ReceiverAndMicrophone
    - SpeakerAndMicrophone
    - Speaker
    - HeadsetInOut
    - HeadsetBT
    - HeadphonesAndMicrophone
 */
@property (nonatomic, readonly)     NSString        *audioRoute;

/**
 Returns YES if a wired headset is available.
 */
@property (nonatomic, readonly)     BOOL             headsetDeviceAvailable;

/**
 Returns YES if a bluetooth device is available.
 */
@property (nonatomic, readonly)     BOOL             bluetoothDeviceAvailable;

/**
 Returns YES if the device's earpiece is available (always true for now).
 */
@property (nonatomic, readonly)     BOOL             phoneDeviceAvailable;

/**
 Returns YES if the device's speakerphone is available (always true for now).
 */
@property (nonatomic, readonly)     BOOL             speakerDeviceAvailable;

/**
 Returns or sets the current audio device. Valid values at this time are:
    - kAudioSessionManagerDevice_Bluetooth
    - kAudioSessionManagerDevice_Headset
    - kAudioSessionManagerDevice_Phone
    - kAudioSessionManagerDevice_Speaker
 */
@property (nonatomic, assign)       NSString        *audioDevice;

/**
 Returns a list of the available audio devices. Valid values at this time are: 
    - kAudioSessionManagerDevice_Bluetooth
    - kAudioSessionManagerDevice_Headset
    - kAudioSessionManagerDevice_Phone
    - kAudioSessionManagerDevice_Speaker
 */
@property (nonatomic, readonly)     NSArray         *availableAudioDevices;

/**
 Returns the AudioSessionManager singleton, creating it if it does not already exist.
 */
+ (AudioSessionManager *)sharedInstance;

/**
 Switch between recording and playback modes. Returns NO if the mode change failed.

 @param value must be kAudioSessionManagerMode_Record or kAudioSessionManagerMode_Playback
*/
- (BOOL)changeMode:(NSString *)value;

/**
 Initialize by detecting all available devices and selecting one based on the following priority:
    - bluetooth
    - headset
    - speaker
 
 @param postNotifications if DevicesAvailableChanged and AudioDeviceChanged notifications should be posted.
 */
- (void)startAndPostNotifications:(BOOL)postNotifications;

@end
