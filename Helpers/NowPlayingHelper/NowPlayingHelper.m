// Streams the system-wide Now Playing state as JSON lines on stdout and takes playback
// commands on stdin. Direct-download edition only.
//
// Since macOS 15.4, MediaRemote only answers Apple-signed processes, so the app loads this
// library into /usr/bin/perl (see SystemNowPlayingSource.swift) instead of calling it directly.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

// MRMediaRemoteCommand values.
enum { kCommandPlay = 0, kCommandPause = 1, kCommandToggle = 2, kCommandNext = 4, kCommandPrevious = 5 };

static void *mediaRemote;
static GetInfoFn getInfo;
static GetIsPlayingFn getIsPlaying;
static GetPIDFn getPID;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;
static NSString *lastArtworkID;
static BOOL refreshPending;

/// MediaRemote's exported string constants; their values match their names if a symbol is missing.
static NSString *Constant(const char *name) {
    CFStringRef *symbol = dlsym(mediaRemote, name);
    return symbol ? (__bridge NSString *)*symbol : @(name);
}

static void Emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id StringOr(id value, id fallback) {
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

static id NumberOr(id value, id fallback) {
    return [value isKindOfClass:NSNumber.class] ? value : fallback;
}

static void EmitState(void) {
    dispatch_queue_t main = dispatch_get_main_queue();
    getPID(main, ^(int pid) {
        getIsPlaying(main, ^(Boolean playing) {
            getInfo(main, ^(CFDictionaryRef cfInfo) {
                NSDictionary *info = (__bridge NSDictionary *)cfInfo;
                NSMutableDictionary *out = [@{ @"type": @"state", @"pid": @(pid), @"playing": @(playing) } mutableCopy];
                out[@"title"] = StringOr(info[Constant("kMRMediaRemoteNowPlayingInfoTitle")], @"");
                out[@"artist"] = StringOr(info[Constant("kMRMediaRemoteNowPlayingInfoArtist")], @"");
                out[@"album"] = StringOr(info[Constant("kMRMediaRemoteNowPlayingInfoAlbum")], @"");
                out[@"duration"] = NumberOr(info[Constant("kMRMediaRemoteNowPlayingInfoDuration")], @0);
                out[@"elapsed"] = NumberOr(info[Constant("kMRMediaRemoteNowPlayingInfoElapsedTime")], @0);
                NSDate *timestamp = info[Constant("kMRMediaRemoteNowPlayingInfoTimestamp")];
                if (![timestamp isKindOfClass:NSDate.class]) timestamp = [NSDate date];
                out[@"timestamp"] = @(timestamp.timeIntervalSince1970);

                // Artwork is large, so send it only when it changes.
                NSData *artwork = info[Constant("kMRMediaRemoteNowPlayingInfoArtworkData")];
                if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
                    NSString *artworkID = [NSString stringWithFormat:@"%lu-%lx", (unsigned long)artwork.length,
                                                                     (unsigned long)artwork.hash];
                    out[@"artworkID"] = artworkID;
                    if (![artworkID isEqualToString:lastArtworkID]) {
                        out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                        lastArtworkID = artworkID;
                    }
                } else {
                    lastArtworkID = nil;
                }
                Emit(out);
            });
        });
    });
}

/// Notifications arrive in bursts; coalesce them into one update.
static void ScheduleRefresh(double delay) {
    if (refreshPending) return;
    refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        refreshPending = NO;
        EmitState();
    });
}

static void HandleCommand(NSString *command) {
    if ([command isEqualToString:@"toggle"]) sendCommand(kCommandToggle, NULL);
    else if ([command isEqualToString:@"play"]) sendCommand(kCommandPlay, NULL);
    else if ([command isEqualToString:@"pause"]) sendCommand(kCommandPause, NULL);
    else if ([command isEqualToString:@"next"]) sendCommand(kCommandNext, NULL);
    else if ([command isEqualToString:@"previous"]) sendCommand(kCommandPrevious, NULL);
    else if ([command hasPrefix:@"seek "]) setElapsed([command substringFromIndex:5].doubleValue);
    ScheduleRefresh(0.3);
}

static void ReadCommands(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char line[256];
        while (fgets(line, sizeof line, stdin)) {
            NSString *command = [@(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dispatch_async(dispatch_get_main_queue(), ^{ HandleCommand(command); });
        }
        // stdin closed: the app quit, so stop too.
        exit(0);
    });
}

/// Called from perl via DynaLoader, which passes interpreter arguments that are not needed here.
__attribute__((visibility("default"))) void notchisland_stream(void *interpreter, void *cv) {
    (void)interpreter;
    (void)cv;
    mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mediaRemote) {
        Emit(@{ @"type": @"error", @"message": @"MediaRemote not found" });
        exit(1);
    }

    getInfo = (GetInfoFn)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (GetIsPlayingFn)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (GetPIDFn)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = (SendCommandFn)dlsym(mediaRemote, "MRMediaRemoteSendCommand");
    setElapsed = (SetElapsedFn)dlsym(mediaRemote, "MRMediaRemoteSetElapsedTime");
    RegisterFn registerForNotifications =
        (RegisterFn)dlsym(mediaRemote, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !getPID || !sendCommand || !setElapsed || !registerForNotifications) {
        Emit(@{ @"type": @"error", @"message": @"MediaRemote functions missing" });
        exit(2);
    }

    registerForNotifications(dispatch_get_main_queue());
    const char *names[] = {
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    };
    for (size_t i = 0; i < sizeof names / sizeof *names; i++) {
        [NSNotificationCenter.defaultCenter addObserverForName:Constant(names[i])
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { ScheduleRefresh(0.05); }];
    }

    ReadCommands();
    Emit(@{ @"type": @"ready" });
    EmitState();
    CFRunLoopRun();
    exit(0);
}
