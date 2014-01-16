![image](https://d3osil7svxrrgt.cloudfront.net/static/www/logos/jawbone/jawbone-logo-lowres.png)
# AudioSessionManager

## Overview

This simple module routes audio depending on device availability using the following priorities: bluetooth, wired headset, speaker.

It also notifies interested listeners of audio change events (optional).

## Requirements

The only requirement to use this module is an ARC-based iOS 6+ project.

# Documentation

## Initialization

AudioSessionManager is a singleton which can be initialized with a single statement:

    // Initialize the audio session...
    [[AudioSessionManager sharedInstance] startAndPostNotifications:YES];

## Notifications

Two notifications are posted by this library if enabled:

- kAudioSessionManagerDevicesAvailableChangedNotification - the list of devices (returned by the <code>availableAudioDevices</code> property) has changed
- kAudioSessionManagerAudioDeviceChangedNotification - the current audio device (returned by the <code>audioDevice</code> property) has changed

## Checking the current audio route

    NSLog(@"audioRoute is %@", [AudioSessionManager sharedInstance].audioRoute);

## Configuring the audio session

Configuring the device for input:

	if (![[AudioSessionManager sharedInstance] changeMode:kAudioSessionManagerMode_Record]) {
        // .... handle error ...
    }

and output:

	if (![[AudioSessionManager sharedInstance] changeMode:kAudioSessionManagerMode_Playback]) {
        // .... handle error ...
    }

