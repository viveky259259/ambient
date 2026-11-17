// The Ambient speaker: a Core Audio driver that adds "Ambient" to the Mac's speakers. What's played to it comes back
// out of a hidden input, "Ambient Loopback", where the app can pick it up and send it to another Mac. The driver can't
// do that itself: coreaudiod runs it in a sandbox, with no network and no way to reach the app.
//
// It also adds "Ambient Microphone", the other way round: what the app plays to a hidden output, "Ambient Microphone
// Feed", comes out of it, so apps here can record another Mac's microphone.
//
// A prototype: one format (48 kHz stereo float) and a volume that isn't saved. Whatever streams the loopback tells the
// speaker how late the other Mac plays, and the speaker reports that as its latency, so video here waits for its sound.

#include <CoreAudio/AudioServerPlugIn.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#pragma mark - Objects

enum {
    kPlugIn = kAudioObjectPlugInObject,
    kSpeaker,           // "Ambient", in Sound settings
    kSpeakerStream,
    kSpeakerVolume,
    kSpeakerMute,
    kLoopback,          // hidden: carries what's played to the speaker back out
    kLoopbackStream,
    kMic,               // "Ambient Microphone", in Sound settings: another Mac's microphone
    kMicStream,
    kMicFeed,           // hidden: what's played to it comes out of the microphone
    kMicFeedStream,
};

#define kSpeakerUID  "com.viveky259259.Ambient.speaker"
#define kLoopbackUID "com.viveky259259.Ambient.speaker.loopback"
#define kMicUID      "com.viveky259259.Ambient.microphone"
#define kMicFeedUID  "com.viveky259259.Ambient.microphone.feed"
#define kModelUID    "com.viveky259259.Ambient.speaker.model"

static const Float64 kSampleRate = 48000;
enum { kChannels = 2 };
/// Frames an output can be ahead of its input, and the zero time stamp period: about a third of a second.
enum { kRingFrames = 16384 };
/// Every device runs off one clock, which this names so an aggregate device knows not to correct between them.
static const UInt32 kClockDomain = 0x616D6269;
static const Float32 kMinDB = -64, kMaxDB = 0;
/// The speaker's own property: how late the other Mac plays what the speaker plays, in frames, as a CFNumber.
enum { kAmbientPropertyStreamDelay = 0x61446C79 }; // 'aDly'
/// Ten seconds, far more than any stream holds.
enum { kMaxStreamDelay = 10 * 48000 };

#pragma mark - State

static AudioServerPlugInDriverRef Driver(void);

/// Guards everything here but the ring and the gain, which the IO threads use without locking.
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static UInt32 gRefCount;
static AudioServerPlugInHostRef gHost;
static Float64 gTicksPerFrame;
/// Where every device's time line starts, so the frame an output plays at sample time t is the one its input records
/// at t.
static UInt64 gAnchor;
/// How many clients run each device's IO, by its object ID.
static UInt32 gIO[kMicFeedStream + 1];
static Float32 gVolume = 1;
static bool gMuted;
static bool gStreamActive[kMicFeedStream + 1] = {
    [kSpeakerStream] = true, [kLoopbackStream] = true, [kMicStream] = true, [kMicFeedStream] = true,
};
/// Frames: the speaker's latency, as what streams it last said, once the speaker has taken it up.
static UInt32 gStreamDelay;
/// Frames: what it last said, which the speaker may not have taken up yet.
static UInt32 gAskedDelay;
/// Takes up new delays one at a time, away from the host's calls.
static dispatch_queue_t gQueue;
/// The volume and mute together, as the factor each sample is played at.
static _Atomic float gGain = 1;
/// The speaker's, which the loopback records, and the feed's, which the microphone records.
static Float32 gRing[kRingFrames * kChannels], gMicRing[kRingFrames * kChannels];

static Float32 Clamp(Float32 v, Float32 lo, Float32 hi) { return v < lo ? lo : v > hi ? hi : v; }

/// The volume slider's position is the square root of the gain, which sounds more even than the gain itself.
static Float32 ScalarToDB(Float32 scalar) {
    scalar = Clamp(scalar, 0, 1);
    return scalar <= 0 ? kMinDB : fmaxf(kMinDB, 40 * log10f(scalar));
}

static Float32 DBToScalar(Float32 db) {
    db = Clamp(db, kMinDB, kMaxDB);
    return db <= kMinDB ? 0 : powf(10, db / 40);
}

/// Call with the lock held.
static void UpdateGain(void) {
    atomic_store_explicit(&gGain, gMuted ? 0 : gVolume * gVolume, memory_order_relaxed);
}

static void Notify(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress* addresses) {
    if (gHost) gHost->PropertiesChanged(gHost, object, count, addresses);
}

static void SetVolume(Float32 scalar) {
    pthread_mutex_lock(&gLock);
    bool changed = gVolume != scalar;
    gVolume = scalar;
    UpdateGain();
    pthread_mutex_unlock(&gLock);
    if (!changed) return;
    AudioObjectPropertyAddress changes[] = {
        { kAudioLevelControlPropertyScalarValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
        { kAudioLevelControlPropertyDecibelValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
    };
    Notify(kSpeakerVolume, 2, changes);
}

/// Whatever has the speaker's latency asks again.
static void NotifyStreamDelay(void* context) {
    (void)context;
    AudioObjectPropertyAddress changes[] = {
        { kAudioDevicePropertyLatency, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
        { kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain },
        { kAmbientPropertyStreamDelay, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
    };
    Notify(kSpeaker, 3, changes);
}

/// Call with the lock held. Says whether it changed.
static bool TakeUpStreamDelay(void) {
    bool changed = gStreamDelay != gAskedDelay;
    gStreamDelay = gAskedDelay;
    return changed;
}

/// On the queue: the host stops the speaker's IO, calls PerformDeviceConfigurationChange, which takes up the delay
/// asked for last, and starts it again. Without a host to do that, it's taken up at once.
static void RestartForDelay(void* context) {
    (void)context;
    if (gHost && gHost->RequestDeviceConfigurationChange(gHost, kSpeaker, 0, NULL) == noErr) return;
    pthread_mutex_lock(&gLock);
    bool changed = TakeUpStreamDelay();
    pthread_mutex_unlock(&gLock);
    if (changed) NotifyStreamDelay(NULL);
}

/// A player reads the latency when its sound starts, pauses or seeks, and not when it changes. So a new delay
/// restarts the speaker for a moment: the sound of everything playing to it restarts, and they all read it again.
static void SetStreamDelay(UInt32 frames) {
    pthread_mutex_lock(&gLock);
    bool changed = gAskedDelay != frames;
    gAskedDelay = frames;
    pthread_mutex_unlock(&gLock);
    if (changed) dispatch_async_f(gQueue, NULL, RestartForDelay);
}

/// On the queue, once nothing records the loopback: nothing streams the speaker, even if what did has crashed.
static void ClearStreamDelay(void* context) {
    (void)context;
    pthread_mutex_lock(&gLock);
    bool idle = gIO[kLoopback] == 0;
    pthread_mutex_unlock(&gLock);
    if (idle) SetStreamDelay(0);
}

static void SetMuted(bool muted) {
    pthread_mutex_lock(&gLock);
    bool changed = gMuted != muted;
    gMuted = muted;
    UpdateGain();
    pthread_mutex_unlock(&gLock);
    if (!changed) return;
    AudioObjectPropertyAddress change = {
        kAudioBooleanControlPropertyValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    Notify(kSpeakerMute, 1, &change);
}

#pragma mark - Properties

/// One property asked about. Without `data`, only its size is wanted, which is also how HasProperty asks.
typedef struct {
    const AudioObjectPropertyAddress* address;
    UInt32 qualifierSize;
    const void* qualifier;
    UInt32 capacity;
    UInt32* size;
    void* data;
} Request;

static OSStatus Reply(Request* r, const void* value, UInt32 size) {
    if (r->data) {
        if (r->capacity < size) return kAudioHardwareBadPropertySizeError;
        memcpy(r->data, value, size);
    }
    *r->size = size;
    return noErr;
}

static OSStatus ReplyU32(Request* r, UInt32 value) { return Reply(r, &value, sizeof value); }
static OSStatus ReplyF32(Request* r, Float32 value) { return Reply(r, &value, sizeof value); }
static OSStatus ReplyF64(Request* r, Float64 value) { return Reply(r, &value, sizeof value); }
/// The caller releases what it's given, which a constant string ignores.
static OSStatus ReplyString(Request* r, CFStringRef value) { return Reply(r, &value, sizeof value); }

/// A list: as many items as fit, as the HAL expects.
static OSStatus ReplyList(Request* r, const void* items, UInt32 count, UInt32 itemSize) {
    if (r->data) {
        if (r->capacity / itemSize < count) count = r->capacity / itemSize;
        if (count) memcpy(r->data, items, (size_t)count * itemSize);
    }
    *r->size = count * itemSize;
    return noErr;
}

static AudioClassID ClassOf(AudioObjectID object) {
    switch (object) {
    case kPlugIn: return kAudioPlugInClassID;
    case kSpeaker: case kLoopback: case kMic: case kMicFeed: return kAudioDeviceClassID;
    case kSpeakerStream: case kLoopbackStream: case kMicStream: case kMicFeedStream: return kAudioStreamClassID;
    case kSpeakerVolume: return kAudioVolumeControlClassID;
    case kSpeakerMute: return kAudioMuteControlClassID;
    default: return 0;
    }
}

static AudioClassID BaseClassOf(AudioObjectID object) {
    switch (object) {
    case kSpeakerVolume: return kAudioLevelControlClassID;
    case kSpeakerMute: return kAudioBooleanControlClassID;
    default: return kAudioObjectClassID;
    }
}

/// Owned objects, keeping only the classes in the qualifier when it names any.
static OSStatus ReplyOwned(Request* r, const AudioObjectID* owned, UInt32 count) {
    AudioObjectID kept[4];
    UInt32 classes = r->qualifier ? r->qualifierSize / sizeof(AudioClassID) : 0, n = 0;
    for (UInt32 i = 0; i < count && n < 4; i++) {
        bool keep = classes == 0;
        for (UInt32 c = 0; c < classes && !keep; c++) {
            AudioClassID wanted = ((const AudioClassID*)r->qualifier)[c];
            keep = wanted == ClassOf(owned[i]) || wanted == BaseClassOf(owned[i]);
        }
        if (keep) kept[n++] = owned[i];
    }
    return ReplyList(r, kept, n, sizeof kept[0]);
}

static bool IsDevice(AudioObjectID object) {
    return object == kSpeaker || object == kLoopback || object == kMic || object == kMicFeed;
}

/// The speaker and the feed play; the loopback and the microphone record.
static bool IsOutput(AudioObjectID device) { return device == kSpeaker || device == kMicFeed; }

/// Each device has one stream, the object after it.
static AudioObjectID StreamOf(AudioObjectID device) { return device + 1; }

static CFStringRef UIDOf(AudioObjectID device) {
    switch (device) {
    case kSpeaker: return CFSTR(kSpeakerUID);
    case kLoopback: return CFSTR(kLoopbackUID);
    case kMic: return CFSTR(kMicUID);
    default: return CFSTR(kMicFeedUID);
    }
}

static OSStatus PlugInProperty(Request* r) {
    static const AudioObjectID devices[] = { kSpeaker, kLoopback, kMic, kMicFeed };
    switch (r->address->mSelector) {
    case kAudioObjectPropertyBaseClass: return ReplyU32(r, kAudioObjectClassID);
    case kAudioObjectPropertyClass: return ReplyU32(r, kAudioPlugInClassID);
    case kAudioObjectPropertyOwner: return ReplyU32(r, kAudioObjectUnknown);
    case kAudioObjectPropertyManufacturer: return ReplyString(r, CFSTR("Ambient"));
    case kAudioObjectPropertyOwnedObjects: return ReplyOwned(r, devices, 4);
    case kAudioPlugInPropertyDeviceList: return ReplyList(r, devices, 4, sizeof devices[0]);
    case kAudioPlugInPropertyTranslateUIDToDevice: {
        AudioObjectID found = kAudioObjectUnknown;
        if (r->data) {
            if (r->qualifierSize != sizeof(CFStringRef) || !r->qualifier) return kAudioHardwareBadPropertySizeError;
            CFStringRef uid = *(const CFStringRef*)r->qualifier;
            for (UInt32 i = 0; uid && i < 4 && found == kAudioObjectUnknown; i++) {
                if (CFEqual(uid, UIDOf(devices[i]))) found = devices[i];
            }
        }
        return ReplyU32(r, found);
    }
    case kAudioPlugInPropertyResourceBundle: return ReplyString(r, CFSTR(""));
    default: return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus DeviceProperty(AudioObjectID device, Request* r) {
    bool speaker = device == kSpeaker, output = IsOutput(device);
    // The visible ones: Sound settings lists them, and they can be the Mac's output or input.
    bool shown = speaker || device == kMic;
    // Each device only plays or only records, so it has nothing in the other scope.
    AudioObjectPropertyScope scope = r->address->mScope;
    bool inScope = scope == kAudioObjectPropertyScopeGlobal
        || scope == (output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput);
    switch (r->address->mSelector) {
    case kAudioObjectPropertyBaseClass: return ReplyU32(r, kAudioObjectClassID);
    case kAudioObjectPropertyClass: return ReplyU32(r, kAudioDeviceClassID);
    case kAudioObjectPropertyOwner: return ReplyU32(r, kPlugIn);
    case kAudioObjectPropertyName:
        return ReplyString(r, speaker ? CFSTR("Ambient") : device == kLoopback ? CFSTR("Ambient Loopback")
                              : device == kMic ? CFSTR("Ambient Microphone") : CFSTR("Ambient Microphone Feed"));
    case kAudioObjectPropertyManufacturer: return ReplyString(r, CFSTR("Ambient"));
    case kAudioObjectPropertyOwnedObjects: {
        static const AudioObjectID speakerOwned[] = { kSpeakerStream, kSpeakerVolume, kSpeakerMute };
        AudioObjectID stream = StreamOf(device);
        if (!inScope) return ReplyOwned(r, NULL, 0);
        return speaker ? ReplyOwned(r, speakerOwned, 3) : ReplyOwned(r, &stream, 1);
    }
    case kAudioDevicePropertyStreams: {
        AudioObjectID stream = StreamOf(device);
        return ReplyList(r, &stream, inScope ? 1 : 0, sizeof stream);
    }
    case kAudioObjectPropertyControlList: {
        static const AudioObjectID controls[] = { kSpeakerVolume, kSpeakerMute };
        return ReplyList(r, controls, speaker ? 2 : 0, sizeof controls[0]);
    }
    case kAudioDevicePropertyDeviceUID: return ReplyString(r, UIDOf(device));
    case kAudioDevicePropertyModelUID: return ReplyString(r, CFSTR(kModelUID));
    case kAudioDevicePropertyTransportType: return ReplyU32(r, kAudioDeviceTransportTypeVirtual);
    case kAudioDevicePropertyRelatedDevices: return ReplyList(r, &device, 1, sizeof device);
    case kAudioDevicePropertyClockDomain: return ReplyU32(r, kClockDomain);
    case kAudioDevicePropertyDeviceIsAlive: return ReplyU32(r, 1);
    case kAudioDevicePropertyDeviceIsRunning: {
        pthread_mutex_lock(&gLock);
        UInt32 running = gIO[device] > 0;
        pthread_mutex_unlock(&gLock);
        return ReplyU32(r, running);
    }
    case kAudioDevicePropertyDeviceCanBeDefaultDevice: return ReplyU32(r, shown && inScope);
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: return ReplyU32(r, speaker);
    case kAudioDevicePropertyLatency: {
        // The speaker plays as late as the other Mac does. The rest play or record at once.
        pthread_mutex_lock(&gLock);
        UInt32 latency = speaker && inScope ? gStreamDelay : 0;
        pthread_mutex_unlock(&gLock);
        return ReplyU32(r, latency);
    }
    case kAudioDevicePropertySafetyOffset: return ReplyU32(r, 0);
    case kAudioObjectPropertyCustomPropertyInfoList: {
        AudioServerPlugInCustomPropertyInfo delay = {
            kAmbientPropertyStreamDelay, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList,
            kAudioServerPlugInCustomPropertyDataTypeNone
        };
        return ReplyList(r, &delay, speaker ? 1 : 0, sizeof delay);
    }
    case kAmbientPropertyStreamDelay: {
        if (!speaker) return kAudioHardwareUnknownPropertyError;
        if (!r->data) return Reply(r, NULL, sizeof(CFPropertyListRef));
        if (r->capacity < sizeof(CFPropertyListRef)) return kAudioHardwareBadPropertySizeError;
        pthread_mutex_lock(&gLock);
        SInt32 frames = (SInt32)gAskedDelay;
        pthread_mutex_unlock(&gLock);
        // The caller releases it.
        CFPropertyListRef value = CFNumberCreate(NULL, kCFNumberSInt32Type, &frames);
        return Reply(r, &value, sizeof value);
    }
    case kAudioDevicePropertyNominalSampleRate: return ReplyF64(r, kSampleRate);
    case kAudioDevicePropertyAvailableNominalSampleRates: {
        AudioValueRange rate = { kSampleRate, kSampleRate };
        return ReplyList(r, &rate, 1, sizeof rate);
    }
    case kAudioDevicePropertyIsHidden: return ReplyU32(r, !shown);
    case kAudioDevicePropertyZeroTimeStampPeriod: return ReplyU32(r, kRingFrames);
    case kAudioDevicePropertyPreferredChannelsForStereo: {
        UInt32 pair[2] = { 1, 2 };
        return Reply(r, pair, sizeof pair);
    }
    case kAudioDevicePropertyPreferredChannelLayout: {
        UInt32 size = (UInt32)(offsetof(AudioChannelLayout, mChannelDescriptions) + kChannels * sizeof(AudioChannelDescription));
        if (r->data) {
            if (r->capacity < size) return kAudioHardwareBadPropertySizeError;
            memset(r->data, 0, size);
            AudioChannelLayout* layout = r->data;
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
            layout->mNumberChannelDescriptions = kChannels;
            AudioChannelDescription* channels = layout->mChannelDescriptions;
            channels[0].mChannelLabel = kAudioChannelLabel_Left;
            channels[1].mChannelLabel = kAudioChannelLabel_Right;
        }
        *r->size = size;
        return noErr;
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

static AudioStreamBasicDescription Format(void) {
    return (AudioStreamBasicDescription){
        .mSampleRate = kSampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mBytesPerPacket = kChannels * sizeof(Float32),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = kChannels * sizeof(Float32),
        .mChannelsPerFrame = kChannels,
        .mBitsPerChannel = 32,
    };
}

static bool IsOurFormat(const AudioStreamBasicDescription* f) {
    AudioStreamBasicDescription ours = Format();
    return f->mSampleRate == ours.mSampleRate && f->mFormatID == ours.mFormatID && f->mFormatFlags == ours.mFormatFlags
        && f->mBytesPerFrame == ours.mBytesPerFrame && f->mChannelsPerFrame == ours.mChannelsPerFrame
        && f->mBitsPerChannel == ours.mBitsPerChannel;
}

static OSStatus StreamProperty(AudioObjectID stream, Request* r) {
    AudioObjectID device = stream - 1;
    bool output = IsOutput(device);
    switch (r->address->mSelector) {
    case kAudioObjectPropertyBaseClass: return ReplyU32(r, kAudioObjectClassID);
    case kAudioObjectPropertyClass: return ReplyU32(r, kAudioStreamClassID);
    case kAudioObjectPropertyOwner: return ReplyU32(r, device);
    case kAudioObjectPropertyOwnedObjects: return ReplyOwned(r, NULL, 0);
    case kAudioStreamPropertyIsActive: {
        pthread_mutex_lock(&gLock);
        UInt32 active = gStreamActive[stream];
        pthread_mutex_unlock(&gLock);
        return ReplyU32(r, active);
    }
    case kAudioStreamPropertyDirection: return ReplyU32(r, output ? 0 : 1);
    case kAudioStreamPropertyTerminalType:
        return ReplyU32(r, stream == kSpeakerStream ? kAudioStreamTerminalTypeSpeaker
                           : stream == kMicStream ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeLine);
    case kAudioStreamPropertyStartingChannel: return ReplyU32(r, 1);
    case kAudioStreamPropertyLatency: return ReplyU32(r, 0);
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat: {
        AudioStreamBasicDescription format = Format();
        return Reply(r, &format, sizeof format);
    }
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats: {
        AudioStreamRangedDescription format = { Format(), { kSampleRate, kSampleRate } };
        return ReplyList(r, &format, 1, sizeof format);
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus ControlProperty(AudioObjectID control, Request* r) {
    switch (r->address->mSelector) {
    case kAudioObjectPropertyBaseClass: return ReplyU32(r, BaseClassOf(control));
    case kAudioObjectPropertyClass: return ReplyU32(r, ClassOf(control));
    case kAudioObjectPropertyOwner: return ReplyU32(r, kSpeaker);
    case kAudioObjectPropertyOwnedObjects: return ReplyOwned(r, NULL, 0);
    case kAudioControlPropertyScope: return ReplyU32(r, kAudioObjectPropertyScopeOutput);
    case kAudioControlPropertyElement: return ReplyU32(r, kAudioObjectPropertyElementMain);
    default: break;
    }
    if (control == kSpeakerMute) {
        if (r->address->mSelector != kAudioBooleanControlPropertyValue) return kAudioHardwareUnknownPropertyError;
        pthread_mutex_lock(&gLock);
        UInt32 muted = gMuted;
        pthread_mutex_unlock(&gLock);
        return ReplyU32(r, muted);
    }
    switch (r->address->mSelector) {
    case kAudioLevelControlPropertyScalarValue:
    case kAudioLevelControlPropertyDecibelValue: {
        pthread_mutex_lock(&gLock);
        Float32 volume = gVolume;
        pthread_mutex_unlock(&gLock);
        bool db = r->address->mSelector == kAudioLevelControlPropertyDecibelValue;
        return ReplyF32(r, db ? ScalarToDB(volume) : volume);
    }
    case kAudioLevelControlPropertyDecibelRange: {
        AudioValueRange range = { kMinDB, kMaxDB };
        return Reply(r, &range, sizeof range);
    }
    case kAudioLevelControlPropertyConvertScalarToDecibels:
    case kAudioLevelControlPropertyConvertDecibelsToScalar: {
        // The value to convert comes in the buffer the answer goes out in.
        if (!r->data) return ReplyF32(r, 0);
        if (r->capacity < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
        Float32 value = *(const Float32*)r->data;
        bool toDB = r->address->mSelector == kAudioLevelControlPropertyConvertScalarToDecibels;
        return ReplyF32(r, toDB ? ScalarToDB(value) : DBToScalar(value));
    }
    default: return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus Property(AudioObjectID object, Request* r) {
    switch (object) {
    case kPlugIn: return PlugInProperty(r);
    case kSpeaker: case kLoopback: case kMic: case kMicFeed: return DeviceProperty(object, r);
    case kSpeakerStream: case kLoopbackStream: case kMicStream: case kMicFeedStream: return StreamProperty(object, r);
    case kSpeakerVolume: case kSpeakerMute: return ControlProperty(object, r);
    default: return kAudioHardwareBadObjectError;
    }
}

static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client,
                           const AudioObjectPropertyAddress* address) {
    (void)client;
    if (driver != Driver() || !address) return false;
    UInt32 size = 0;
    Request r = { .address = address, .size = &size };
    return Property(object, &r) == noErr;
}

static bool IsSettable(AudioObjectID object, AudioObjectPropertySelector selector) {
    switch (object) {
    case kSpeaker: return selector == kAmbientPropertyStreamDelay;
    case kSpeakerVolume:
        return selector == kAudioLevelControlPropertyScalarValue || selector == kAudioLevelControlPropertyDecibelValue;
    case kSpeakerMute: return selector == kAudioBooleanControlPropertyValue;
    case kSpeakerStream: case kLoopbackStream: case kMicStream: case kMicFeedStream:
        return selector == kAudioStreamPropertyIsActive || selector == kAudioStreamPropertyVirtualFormat
            || selector == kAudioStreamPropertyPhysicalFormat;
    default: return false;
    }
}

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client,
                                   const AudioObjectPropertyAddress* address, Boolean* outIsSettable) {
    if (driver != Driver()) return kAudioHardwareBadObjectError;
    if (!address || !outIsSettable) return kAudioHardwareIllegalOperationError;
    if (ClassOf(object) == 0) return kAudioHardwareBadObjectError;
    if (!HasProperty(driver, object, client, address)) return kAudioHardwareUnknownPropertyError;
    *outIsSettable = IsSettable(object, address->mSelector);
    return noErr;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client,
                                    const AudioObjectPropertyAddress* address, UInt32 qualifierSize,
                                    const void* qualifier, UInt32* outDataSize) {
    (void)client;
    if (driver != Driver()) return kAudioHardwareBadObjectError;
    if (!address || !outDataSize) return kAudioHardwareIllegalOperationError;
    Request r = { address, qualifierSize, qualifier, 0, outDataSize, NULL };
    return Property(object, &r);
}

static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client,
                                const AudioObjectPropertyAddress* address, UInt32 qualifierSize, const void* qualifier,
                                UInt32 dataSize, UInt32* outDataSize, void* outData) {
    (void)client;
    if (driver != Driver()) return kAudioHardwareBadObjectError;
    if (!address || !outDataSize || !outData) return kAudioHardwareIllegalOperationError;
    Request r = { address, qualifierSize, qualifier, dataSize, outDataSize, outData };
    return Property(object, &r);
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client,
                                const AudioObjectPropertyAddress* address, UInt32 qualifierSize, const void* qualifier,
                                UInt32 dataSize, const void* data) {
    (void)qualifierSize, (void)qualifier;
    if (driver != Driver()) return kAudioHardwareBadObjectError;
    if (!address || !data) return kAudioHardwareIllegalOperationError;
    if (ClassOf(object) == 0) return kAudioHardwareBadObjectError;
    AudioObjectPropertySelector selector = address->mSelector;
    if (!IsSettable(object, selector)) {
        return HasProperty(driver, object, client, address) ? kAudioHardwareUnsupportedOperationError
                                                             : kAudioHardwareUnknownPropertyError;
    }
    switch (selector) {
    case kAudioLevelControlPropertyScalarValue:
    case kAudioLevelControlPropertyDecibelValue: {
        if (dataSize != sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
        Float32 value = *(const Float32*)data;
        if (isnan(value)) return kAudioHardwareIllegalOperationError;
        SetVolume(selector == kAudioLevelControlPropertyScalarValue ? Clamp(value, 0, 1) : DBToScalar(value));
        return noErr;
    }
    case kAudioBooleanControlPropertyValue:
        if (dataSize != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        SetMuted(*(const UInt32*)data != 0);
        return noErr;
    case kAudioStreamPropertyIsActive: {
        if (dataSize != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        bool active = *(const UInt32*)data != 0;
        pthread_mutex_lock(&gLock);
        bool* flag = &gStreamActive[object];
        bool changed = *flag != active;
        *flag = active;
        pthread_mutex_unlock(&gLock);
        if (changed) {
            AudioObjectPropertyAddress change = {
                kAudioStreamPropertyIsActive, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
            };
            Notify(object, 1, &change);
        }
        return noErr;
    }
    case kAmbientPropertyStreamDelay: {
        if (dataSize != sizeof(CFPropertyListRef)) return kAudioHardwareBadPropertySizeError;
        CFPropertyListRef value = *(const CFPropertyListRef*)data;
        SInt64 frames = -1;
        if (!value || CFGetTypeID(value) != CFNumberGetTypeID() || !CFNumberGetValue(value, kCFNumberSInt64Type, &frames)
            || frames < 0 || frames > kMaxStreamDelay) {
            return kAudioHardwareIllegalOperationError;
        }
        SetStreamDelay((UInt32)frames);
        return noErr;
    }
    default:
        // A format: there's only the one.
        if (dataSize != sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        return IsOurFormat(data) ? noErr : kAudioDeviceUnsupportedFormatError;
    }
}

#pragma mark - IO

/// The ring a device plays into or records from: the speaker's and loopback's, or the feed's and microphone's.
static Float32* RingOf(AudioObjectID device) { return device == kSpeaker || device == kLoopback ? gRing : gMicRing; }

static void ClearRing(Float32* ring) { memset(ring, 0, sizeof gRing); }

static UInt64 Frame(Float64 sampleTime) { return sampleTime > 0 ? (UInt64)sampleTime : 0; }

static void WriteRing(Float32* ring, Float64 sampleTime, UInt32 frames, const Float32* in, Float32 gain) {
    UInt64 start = Frame(sampleTime);
    for (UInt32 i = 0; i < frames; i++) {
        Float32* out = &ring[((start + i) % kRingFrames) * kChannels];
        for (int c = 0; c < kChannels; c++) out[c] = in[(size_t)i * kChannels + c] * gain;
    }
}

static void ReadRing(const Float32* ring, Float64 sampleTime, UInt32 frames, Float32* out) {
    UInt64 start = Frame(sampleTime);
    for (UInt32 i = 0; i < frames; i++) {
        const Float32* in = &ring[((start + i) % kRingFrames) * kChannels];
        for (int c = 0; c < kChannels; c++) out[(size_t)i * kChannels + c] = in[c];
    }
}

static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client) {
    (void)client;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gLock);
    UInt32* count = &gIO[device];
    if (*count == UINT32_MAX) {
        pthread_mutex_unlock(&gLock);
        return kAudioHardwareIllegalOperationError;
    }
    // What was left from the last time it played isn't playing now.
    if (IsOutput(device) && *count == 0) ClearRing(RingOf(device));
    ++*count;
    pthread_mutex_unlock(&gLock);
    return noErr;
}

static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client) {
    (void)client;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gLock);
    UInt32* count = &gIO[device];
    if (*count == 0) {
        pthread_mutex_unlock(&gLock);
        return kAudioHardwareIllegalOperationError;
    }
    bool idle = --*count == 0, delayed = gAskedDelay != 0;
    // Stopped, it's silent: its input mustn't keep hearing the last third of a second over and over.
    if (idle && IsOutput(device)) ClearRing(RingOf(device));
    pthread_mutex_unlock(&gLock);
    // Not from here, where the host may be busy with the device.
    if (idle && device == kLoopback && delayed) dispatch_async_f(gQueue, NULL, ClearStreamDelay);
    return noErr;
}

static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client,
                                 Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    (void)client;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    // The last time a period began, counted from the anchor both devices share. Nothing drifts: the host clock is
    // the device's clock.
    Float64 ticksPerPeriod = gTicksPerFrame * kRingFrames;
    UInt64 periods = (UInt64)((Float64)(mach_absolute_time() - gAnchor) / ticksPerPeriod);
    *outSampleTime = (Float64)periods * kRingFrames;
    *outHostTime = gAnchor + (UInt64)((Float64)periods * ticksPerPeriod);
    *outSeed = 1;
    return noErr;
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client,
                                  UInt32 operation, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    (void)client;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    bool will = operation == (IsOutput(device) ? kAudioServerPlugInIOOperationWriteMix
                                               : kAudioServerPlugInIOOperationReadInput);
    if (outWillDo) *outWillDo = will;
    if (outWillDoInPlace) *outWillDoInPlace = true;
    return noErr;
}

static OSStatus BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client,
                                 UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo* cycle) {
    (void)client, (void)operation, (void)frames, (void)cycle;
    return driver == Driver() && IsDevice(device) ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, AudioObjectID stream,
                              UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo* cycle,
                              void* main, void* secondary) {
    (void)client, (void)secondary;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    if (!main || !cycle) return noErr;
    if (stream != StreamOf(device)) return noErr;
    if (IsOutput(device) && operation == kAudioServerPlugInIOOperationWriteMix) {
        // Only the speaker has a volume: what plays to the feed is the other Mac's microphone as it is.
        Float32 gain = device == kSpeaker ? atomic_load_explicit(&gGain, memory_order_relaxed) : 1;
        WriteRing(RingOf(device), cycle->mOutputTime.mSampleTime, frames, main, gain);
    } else if (!IsOutput(device) && operation == kAudioServerPlugInIOOperationReadInput) {
        ReadRing(RingOf(device), cycle->mInputTime.mSampleTime, frames, main);
    }
    return noErr;
}

static OSStatus EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client,
                               UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo* cycle) {
    (void)client, (void)operation, (void)frames, (void)cycle;
    return driver == Driver() && IsDevice(device) ? noErr : kAudioHardwareBadObjectError;
}

#pragma mark - Plug-in

static ULONG AddRef(void* driver) {
    if (driver != Driver()) return 0;
    pthread_mutex_lock(&gLock);
    if (gRefCount < UINT32_MAX) ++gRefCount;
    ULONG count = gRefCount;
    pthread_mutex_unlock(&gLock);
    return count;
}

static ULONG Release(void* driver) {
    if (driver != Driver()) return 0;
    pthread_mutex_lock(&gLock);
    if (gRefCount > 0) --gRefCount;
    ULONG count = gRefCount;
    pthread_mutex_unlock(&gLock);
    return count;
}

static HRESULT QueryInterface(void* driver, REFIID uuid, LPVOID* outInterface) {
    if (driver != Driver() || !outInterface) return kAudioHardwareBadObjectError;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    if (!requested) return kAudioHardwareIllegalOperationError;
    bool known = CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID);
    CFRelease(requested);
    if (!known) {
        *outInterface = NULL;
        return E_NOINTERFACE;
    }
    AddRef(driver);
    *outInterface = Driver();
    return S_OK;
}

static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (driver != Driver()) return kAudioHardwareBadObjectError;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    pthread_mutex_lock(&gLock);
    gHost = host;
    gTicksPerFrame = (1e9 * timebase.denom / timebase.numer) / kSampleRate;
    gAnchor = mach_absolute_time();
    if (!gQueue) gQueue = dispatch_queue_create("com.viveky259259.Ambient.speaker", DISPATCH_QUEUE_SERIAL);
    UpdateGain();
    pthread_mutex_unlock(&gLock);
    return noErr;
}

static OSStatus CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef description,
                             const AudioServerPlugInClientInfo* clientInfo, AudioObjectID* outDevice) {
    (void)description, (void)clientInfo, (void)outDevice;
    return driver == Driver() ? kAudioHardwareUnsupportedOperationError : kAudioHardwareBadObjectError;
}

static OSStatus DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID device) {
    (void)device;
    return driver == Driver() ? kAudioHardwareUnsupportedOperationError : kAudioHardwareBadObjectError;
}

static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device,
                                const AudioServerPlugInClientInfo* clientInfo) {
    (void)clientInfo;
    return driver == Driver() && IsDevice(device) ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device,
                                   const AudioServerPlugInClientInfo* clientInfo) {
    (void)clientInfo;
    return driver == Driver() && IsDevice(device) ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device,
                                                 UInt64 action, void* info) {
    (void)action, (void)info;
    if (driver != Driver() || !IsDevice(device)) return kAudioHardwareBadObjectError;
    if (device != kSpeaker) return noErr;
    // The speaker's IO has stopped. What it last wrote would come round again in the loopback, so it goes.
    pthread_mutex_lock(&gLock);
    bool changed = TakeUpStreamDelay();
    ClearRing(gRing);
    pthread_mutex_unlock(&gLock);
    if (changed) dispatch_async_f(gQueue, NULL, NotifyStreamDelay);
    return noErr;
}

static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device,
                                               UInt64 action, void* info) {
    (void)action, (void)info;
    return driver == Driver() && IsDevice(device) ? noErr : kAudioHardwareBadObjectError;
}

static AudioServerPlugInDriverInterface gInterface = {
    NULL,
    QueryInterface, AddRef, Release,
    Initialize, CreateDevice, DestroyDevice, AddDeviceClient, RemoveDeviceClient,
    PerformDeviceConfigurationChange, AbortDeviceConfigurationChange,
    HasProperty, IsPropertySettable, GetPropertyDataSize, GetPropertyData, SetPropertyData,
    StartIO, StopIO, GetZeroTimeStamp, WillDoIOOperation, BeginIOOperation, DoIOOperation, EndIOOperation,
};
static AudioServerPlugInDriverInterface* gInterfacePointer = &gInterface;

static AudioServerPlugInDriverRef Driver(void) { return &gInterfacePointer; }

/// The factory Info.plist names: coreaudiod calls it to load the driver.
__attribute__((visibility("default")))
void* AmbientSpeaker_Create(CFAllocatorRef allocator, CFUUIDRef requestedType);
void* AmbientSpeaker_Create(CFAllocatorRef allocator, CFUUIDRef requestedType) {
    (void)allocator;
    return CFEqual(requestedType, kAudioServerPlugInTypeUUID) ? Driver() : NULL;
}
