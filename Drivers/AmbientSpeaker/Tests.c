// Tests the Ambient speaker through its plug-in interface, with a stand-in for coreaudiod, so nothing is installed.
// scripts/build-speaker.sh runs them before it builds the driver.

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void* AmbientSpeaker_Create(CFAllocatorRef allocator, CFUUIDRef requestedType);

static int failures;
#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #condition); failures++; } } while (0)
/// For what the driver does on a queue of its own: waits up to a second for it.
#define EVENTUALLY(condition) do { \
    for (int waited = 0; waited < 200 && !(condition); waited++) usleep(5000); CHECK(condition); } while (0)

#pragma mark - A stand-in for coreaudiod

/// Some come from another thread.
static _Atomic int changes, restarts;
static AudioServerPlugInDriverRef driver;

static OSStatus PropertiesChanged(AudioServerPlugInHostRef host, AudioObjectID object, UInt32 count,
                                  const AudioObjectPropertyAddress* addresses) {
    (void)host, (void)object, (void)addresses;
    changes += (int)count;
    return noErr;
}

static OSStatus CopyFromStorage(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef* outData) {
    (void)host, (void)key;
    *outData = NULL;
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus WriteToStorage(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef data) {
    (void)host, (void)key, (void)data;
    return noErr;
}

static OSStatus DeleteFromStorage(AudioServerPlugInHostRef host, CFStringRef key) {
    (void)host, (void)key;
    return noErr;
}

/// As coreaudiod does, later: stops the device's IO, has the driver change it, and starts it again.
static OSStatus RequestDeviceConfigurationChange(AudioServerPlugInHostRef host, AudioObjectID device, UInt64 action,
                                                 void* info) {
    (void)host;
    restarts++;
    return (*driver)->PerformDeviceConfigurationChange(driver, device, action, info);
}

static const AudioServerPlugInHostInterface host = {
    PropertiesChanged, CopyFromStorage, WriteToStorage, DeleteFromStorage, RequestDeviceConfigurationChange,
};

#pragma mark - Asking the driver

#define D (*driver)
static const AudioObjectPropertyScope kGlobal = kAudioObjectPropertyScopeGlobal;
static const AudioObjectPropertyScope kInput = kAudioObjectPropertyScopeInput;
static const AudioObjectPropertyScope kOutput = kAudioObjectPropertyScopeOutput;

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){ selector, scope, kAudioObjectPropertyElementMain };
}

static bool Has(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = Address(selector, scope);
    return D->HasProperty(driver, object, 0, &address);
}

static OSStatus Get(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope,
                    UInt32 qualifierSize, const void* qualifier, UInt32 size, void* data, UInt32* outSize) {
    AudioObjectPropertyAddress address = Address(selector, scope);
    UInt32 ignored;
    return D->GetPropertyData(driver, object, 0, &address, qualifierSize, qualifier, size, outSize ? outSize : &ignored,
                              data);
}

static UInt32 U32(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    UInt32 value = 0xDEADBEEF;
    CHECK(Get(object, selector, scope, 0, NULL, sizeof value, &value, NULL) == noErr);
    return value;
}

static Float32 F32(AudioObjectID object, AudioObjectPropertySelector selector) {
    Float32 value = NAN;
    CHECK(Get(object, selector, kGlobal, 0, NULL, sizeof value, &value, NULL) == noErr);
    return value;
}

static bool IsString(AudioObjectID object, AudioObjectPropertySelector selector, CFStringRef expected) {
    CFStringRef value = NULL;
    if (Get(object, selector, kGlobal, 0, NULL, sizeof value, &value, NULL) != noErr || !value) return false;
    bool same = CFEqual(value, expected);
    CFRelease(value);
    return same;
}

static UInt32 List(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope,
                   AudioObjectID* items, UInt32 capacity) {
    UInt32 size = 0;
    CHECK(Get(object, selector, scope, 0, NULL, capacity * (UInt32)sizeof *items, items, &size) == noErr);
    return size / (UInt32)sizeof *items;
}

static AudioObjectID DeviceFor(CFStringRef uid) {
    AudioObjectID device = 0xDEADBEEF;
    CHECK(Get(kAudioObjectPlugInObject, kAudioPlugInPropertyTranslateUIDToDevice, kGlobal, sizeof uid, &uid,
              sizeof device, &device, NULL) == noErr);
    return device;
}

static OSStatus Set(AudioObjectID object, AudioObjectPropertySelector selector, UInt32 size, const void* data) {
    AudioObjectPropertyAddress address = Address(selector, kGlobal);
    return D->SetPropertyData(driver, object, 0, &address, 0, NULL, size, data);
}

#pragma mark - Tests

static AudioObjectID speaker, loopback, speakerStream, loopbackStream, volume, mute;

static void TestLoading(void) {
    CFUUIDRef other = CFUUIDCreate(NULL);
    CHECK(AmbientSpeaker_Create(NULL, other) == NULL);
    CFRelease(other);

    driver = AmbientSpeaker_Create(NULL, kAudioServerPlugInTypeUUID);
    CHECK(driver != NULL);
    if (!driver) exit(1);
    void* interface = NULL;
    CHECK(D->QueryInterface(driver, CFUUIDGetUUIDBytes(kAudioServerPlugInDriverInterfaceUUID), &interface) == S_OK);
    CHECK(interface == driver);
    CHECK(D->QueryInterface(driver, CFUUIDGetUUIDBytes(kAudioServerPlugInTypeUUID), &interface) == E_NOINTERFACE);
    CHECK(D->Release(driver) == 0);
    CHECK(D->Initialize(driver, &host) == noErr);
}

static void TestObjects(void) {
    AudioObjectID devices[4];
    CHECK(List(kAudioObjectPlugInObject, kAudioPlugInPropertyDeviceList, kGlobal, devices, 4) == 2);
    speaker = DeviceFor(CFSTR("com.viveky259259.Ambient.speaker"));
    loopback = DeviceFor(CFSTR("com.viveky259259.Ambient.speaker.loopback"));
    CHECK(speaker == devices[0] && loopback == devices[1]);
    CHECK(DeviceFor(CFSTR("BuiltInSpeakerDevice")) == kAudioObjectUnknown);

    // The speaker is a speaker anyone can pick. The loopback is hidden, and only records.
    CHECK(IsString(speaker, kAudioObjectPropertyName, CFSTR("Ambient")));
    CHECK(U32(speaker, kAudioDevicePropertyIsHidden, kGlobal) == 0);
    CHECK(U32(speaker, kAudioDevicePropertyDeviceCanBeDefaultDevice, kOutput) == 1);
    CHECK(U32(loopback, kAudioDevicePropertyIsHidden, kGlobal) == 1);
    CHECK(U32(loopback, kAudioDevicePropertyDeviceCanBeDefaultDevice, kInput) == 0);
    CHECK(U32(speaker, kAudioDevicePropertyTransportType, kGlobal) == kAudioDeviceTransportTypeVirtual);
    CHECK(U32(speaker, kAudioDevicePropertyClockDomain, kGlobal) == U32(loopback, kAudioDevicePropertyClockDomain, kGlobal));

    AudioObjectID streams[4];
    CHECK(List(speaker, kAudioDevicePropertyStreams, kInput, streams, 4) == 0);
    CHECK(List(speaker, kAudioDevicePropertyStreams, kOutput, streams, 4) == 1);
    speakerStream = streams[0];
    CHECK(List(loopback, kAudioDevicePropertyStreams, kOutput, streams, 4) == 0);
    CHECK(List(loopback, kAudioDevicePropertyStreams, kInput, streams, 4) == 1);
    loopbackStream = streams[0];
    CHECK(U32(speakerStream, kAudioStreamPropertyDirection, kGlobal) == 0);
    CHECK(U32(loopbackStream, kAudioStreamPropertyDirection, kGlobal) == 1);

    AudioObjectID controls[4];
    CHECK(List(speaker, kAudioObjectPropertyControlList, kGlobal, controls, 4) == 2);
    CHECK(List(loopback, kAudioObjectPropertyControlList, kGlobal, controls + 2, 2) == 0);
    for (int i = 0; i < 2; i++) {
        UInt32 class = U32(controls[i], kAudioObjectPropertyClass, kGlobal);
        if (class == kAudioVolumeControlClassID) volume = controls[i];
        if (class == kAudioMuteControlClassID) mute = controls[i];
    }
    CHECK(volume && mute);
    CHECK(U32(volume, kAudioObjectPropertyBaseClass, kGlobal) == kAudioLevelControlClassID);
    CHECK(U32(volume, kAudioControlPropertyScope, kGlobal) == kOutput);

    // Asking for only the volume controls leaves out the stream and the mute.
    AudioObjectID owned[4];
    AudioClassID wanted = kAudioVolumeControlClassID;
    UInt32 size = 0;
    CHECK(Get(speaker, kAudioObjectPropertyOwnedObjects, kGlobal, sizeof wanted, &wanted, sizeof owned, owned, &size)
          == noErr);
    CHECK(size == sizeof(AudioObjectID) && owned[0] == volume);

    // Everything says who owns it, and its owner lists it.
    AudioObjectID all[] = { speaker, loopback, speakerStream, loopbackStream, volume, mute };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) {
        AudioObjectID owner = U32(all[i], kAudioObjectPropertyOwner, kGlobal);
        UInt32 n = List(owner, kAudioObjectPropertyOwnedObjects, kGlobal, owned, 4);
        bool listed = false;
        for (UInt32 j = 0; j < n; j++) listed = listed || owned[j] == all[i];
        CHECK(listed);
    }

    CHECK(!Has(99, kAudioObjectPropertyClass, kGlobal));
    CHECK(Get(99, kAudioObjectPropertyClass, kGlobal, 0, NULL, 4, &size, NULL) == kAudioHardwareBadObjectError);
    CHECK(!Has(kAudioObjectPlugInObject, kAudioDevicePropertyDeviceUID, kGlobal));
}

/// Every property any object says it has can be read at the size it says, in every scope.
static void TestEveryProperty(void) {
    static const AudioObjectPropertySelector selectors[] = {
        kAudioObjectPropertyBaseClass, kAudioObjectPropertyClass, kAudioObjectPropertyOwner, kAudioObjectPropertyName,
        kAudioObjectPropertyManufacturer, kAudioObjectPropertyOwnedObjects, kAudioPlugInPropertyDeviceList,
        kAudioPlugInPropertyResourceBundle, kAudioDevicePropertyDeviceUID, kAudioDevicePropertyModelUID,
        kAudioDevicePropertyTransportType, kAudioDevicePropertyRelatedDevices, kAudioDevicePropertyClockDomain,
        kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceIsRunning,
        kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
        kAudioDevicePropertyLatency, kAudioDevicePropertyStreams, kAudioObjectPropertyControlList,
        kAudioDevicePropertySafetyOffset, kAudioDevicePropertyNominalSampleRate,
        kAudioDevicePropertyAvailableNominalSampleRates, kAudioDevicePropertyIsHidden,
        kAudioDevicePropertyZeroTimeStampPeriod, kAudioDevicePropertyPreferredChannelsForStereo,
        kAudioDevicePropertyPreferredChannelLayout, kAudioStreamPropertyIsActive, kAudioStreamPropertyDirection,
        kAudioStreamPropertyTerminalType, kAudioStreamPropertyStartingChannel, kAudioStreamPropertyVirtualFormat,
        kAudioStreamPropertyPhysicalFormat, kAudioStreamPropertyAvailableVirtualFormats,
        kAudioStreamPropertyAvailablePhysicalFormats, kAudioControlPropertyScope, kAudioControlPropertyElement,
        kAudioLevelControlPropertyScalarValue, kAudioLevelControlPropertyDecibelValue,
        kAudioLevelControlPropertyDecibelRange, kAudioBooleanControlPropertyValue,
        kAudioObjectPropertyCustomPropertyInfoList,
    };
    static const AudioObjectPropertyScope scopes[] = { kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyScopeInput,
                                                       kAudioObjectPropertyScopeOutput };
    int answered = 0;
    for (AudioObjectID object = kAudioObjectPlugInObject; object <= 7; object++) {
        for (size_t s = 0; s < sizeof selectors / sizeof selectors[0]; s++) {
            for (size_t c = 0; c < 3; c++) {
                if (!Has(object, selectors[s], scopes[c])) continue;
                AudioObjectPropertyAddress address = Address(selectors[s], scopes[c]);
                UInt32 size = 0, got = 0;
                CHECK(D->GetPropertyDataSize(driver, object, 0, &address, 0, NULL, &size) == noErr);
                char buffer[256];
                CHECK(size <= sizeof buffer);
                if (size > sizeof buffer) continue;
                OSStatus status = D->GetPropertyData(driver, object, 0, &address, 0, NULL, size, &got, buffer);
                if (status != noErr || got != size) {
                    fprintf(stderr, "object %u '%.4s' scope %zu: status %d, size %u of %u\n", object,
                            (const char*)&(UInt32){ CFSwapInt32HostToBig(selectors[s]) }, c, (int)status, got, size);
                }
                CHECK(status == noErr && got == size);
                // Too small a buffer for one value is an error, not a short write.
                if (size == 4 || size == 8) {
                    CHECK(D->GetPropertyData(driver, object, 0, &address, 0, NULL, size - 1, &got, buffer) != noErr
                          || got < size);
                }
                answered++;
            }
        }
    }
    CHECK(answered > 100);
}

static void TestSettings(void) {
    Boolean settable = true;
    AudioObjectPropertyAddress rate = Address(kAudioDevicePropertyNominalSampleRate, kGlobal);
    CHECK(D->IsPropertySettable(driver, speaker, 0, &rate, &settable) == noErr && !settable);
    AudioObjectPropertyAddress scalar = Address(kAudioLevelControlPropertyScalarValue, kGlobal);
    CHECK(D->IsPropertySettable(driver, volume, 0, &scalar, &settable) == noErr && settable);
    Float64 rate44k = 44100;
    CHECK(Set(speaker, kAudioDevicePropertyNominalSampleRate, sizeof rate44k, &rate44k)
          == kAudioHardwareUnsupportedOperationError);

    // One format only.
    AudioStreamBasicDescription format;
    CHECK(Get(speakerStream, kAudioStreamPropertyPhysicalFormat, kGlobal, 0, NULL, sizeof format, &format, NULL) == noErr);
    CHECK(format.mSampleRate == 48000 && format.mChannelsPerFrame == 2 && format.mBitsPerChannel == 32);
    CHECK(Set(speakerStream, kAudioStreamPropertyPhysicalFormat, sizeof format, &format) == noErr);
    format.mSampleRate = 44100;
    CHECK(Set(speakerStream, kAudioStreamPropertyPhysicalFormat, sizeof format, &format)
          == kAudioDeviceUnsupportedFormatError);

    // The volume reads back in decibels, says it changed, and converts both ways.
    int before = changes;
    Float32 half = 0.5f;
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof half, &half) == noErr);
    CHECK(changes > before);
    CHECK(F32(volume, kAudioLevelControlPropertyScalarValue) == 0.5f);
    CHECK(fabsf(F32(volume, kAudioLevelControlPropertyDecibelValue) - 40 * log10f(0.5f)) < 1e-4f);
    Float32 db = -20;
    CHECK(Set(volume, kAudioLevelControlPropertyDecibelValue, sizeof db, &db) == noErr);
    CHECK(fabsf(F32(volume, kAudioLevelControlPropertyDecibelValue) + 20) < 1e-3f);
    Float32 value = 0.25f;
    CHECK(Get(volume, kAudioLevelControlPropertyConvertScalarToDecibels, kGlobal, 0, NULL, sizeof value, &value, NULL)
          == noErr);
    CHECK(Get(volume, kAudioLevelControlPropertyConvertDecibelsToScalar, kGlobal, 0, NULL, sizeof value, &value, NULL)
          == noErr);
    CHECK(fabsf(value - 0.25f) < 1e-5f);
    Float32 tooLoud = 3;
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof tooLoud, &tooLoud) == noErr);
    CHECK(F32(volume, kAudioLevelControlPropertyScalarValue) == 1);
    Float32 nan = NAN;
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof nan, &nan) != noErr);

    UInt32 on = 1;
    CHECK(Set(mute, kAudioBooleanControlPropertyValue, sizeof on, &on) == noErr);
    CHECK(U32(mute, kAudioBooleanControlPropertyValue, kGlobal) == 1);
    UInt32 off = 0;
    CHECK(Set(mute, kAudioBooleanControlPropertyValue, sizeof off, &off) == noErr);
}

enum { kStreamDelay = 0x61446C79, kRestartForDelay = 0x61446C52 };

static OSStatus SetDelay(CFPropertyListRef value) { return Set(speaker, kStreamDelay, sizeof value, &value); }

static OSStatus SetDelayFrames(SInt64 frames) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt64Type, &frames);
    OSStatus status = SetDelay(number);
    CFRelease(number);
    return status;
}

static SInt64 Delay(void) {
    CFPropertyListRef value = NULL;
    SInt64 frames = -1;
    CHECK(Get(speaker, kStreamDelay, kGlobal, 0, NULL, sizeof value, &value, NULL) == noErr);
    if (value) {
        CHECK(CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberSInt64Type, &frames));
        CFRelease(value);
    }
    return frames;
}

static bool Restarts(void) {
    CFPropertyListRef value = NULL;
    CHECK(Get(speaker, kRestartForDelay, kGlobal, 0, NULL, sizeof value, &value, NULL) == noErr);
    bool on = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
    if (value) CFRelease(value);
    return on;
}

static OSStatus SetRestarts(CFPropertyListRef value) { return Set(speaker, kRestartForDelay, sizeof value, &value); }

static void TestStreamDelay(void) {
    // The speaker says it has the properties, and what they hold.
    AudioServerPlugInCustomPropertyInfo info[3];
    UInt32 size = 0;
    CHECK(Get(speaker, kAudioObjectPropertyCustomPropertyInfoList, kGlobal, 0, NULL, sizeof info, info, &size) == noErr);
    CHECK(size == 2 * sizeof info[0] && info[0].mSelector == kStreamDelay && info[1].mSelector == kRestartForDelay);
    for (int i = 0; i < 2; i++) {
        CHECK(info[i].mPropertyDataType == kAudioServerPlugInCustomPropertyDataTypeCFPropertyList
              && info[i].mQualifierDataType == kAudioServerPlugInCustomPropertyDataTypeNone);
    }
    CHECK(Get(loopback, kAudioObjectPropertyCustomPropertyInfoList, kGlobal, 0, NULL, sizeof info, info, &size) == noErr);
    CHECK(size == 0);
    CHECK(!Has(loopback, kStreamDelay, kGlobal) && !Has(loopback, kRestartForDelay, kGlobal));
    Boolean settable = false;
    AudioObjectPropertyAddress delay = Address(kStreamDelay, kGlobal), restart = Address(kRestartForDelay, kGlobal);
    CHECK(D->IsPropertySettable(driver, speaker, 0, &delay, &settable) == noErr && settable);
    settable = false;
    CHECK(D->IsPropertySettable(driver, speaker, 0, &restart, &settable) == noErr && settable);

    // At first the speaker plays at once, and takes up a delay by restarting.
    CHECK(Delay() == 0);
    CHECK(U32(speaker, kAudioDevicePropertyLatency, kOutput) == 0);
    CHECK(Restarts());

    // Told the other Mac plays 170 ms late, the speaker restarts, once, and then its latency is that, and it says so.
    int before = changes, restartsBefore = restarts;
    CHECK(SetDelayFrames(8160) == noErr);
    CHECK(Delay() == 8160);
    EVENTUALLY(U32(speaker, kAudioDevicePropertyLatency, kOutput) == 8160);
    EVENTUALLY(changes > before);
    CHECK(restarts == restartsBefore + 1);
    CHECK(U32(speaker, kAudioDevicePropertyLatency, kGlobal) == 8160);
    CHECK(U32(speaker, kAudioDevicePropertyLatency, kInput) == 0);
    CHECK(U32(loopback, kAudioDevicePropertyLatency, kInput) == 0);
    CHECK(U32(speaker, kAudioDevicePropertySafetyOffset, kOutput) == 0);
    // The same again changes nothing.
    before = changes;
    CHECK(SetDelayFrames(8160) == noErr);
    usleep(50000);
    CHECK(changes == before && restarts == restartsBefore + 1);

    // Without restarting, it takes up a delay at once.
    CHECK(SetRestarts(kCFBooleanFalse) == noErr);
    CHECK(!Restarts());
    before = changes;
    CHECK(SetDelayFrames(4800) == noErr);
    CHECK(U32(speaker, kAudioDevicePropertyLatency, kOutput) == 4800);
    CHECK(changes > before && restarts == restartsBefore + 1);
    CHECK(SetRestarts(kCFBooleanTrue) == noErr);
    CHECK(Restarts());
    CHECK(SetRestarts(CFSTR("yes")) == kAudioHardwareIllegalOperationError);
    UInt32 one = 1;
    CHECK(Set(speaker, kRestartForDelay, sizeof one, &one) == kAudioHardwareBadPropertySizeError);
    CHECK(SetDelayFrames(8160) == noErr);
    EVENTUALLY(U32(speaker, kAudioDevicePropertyLatency, kOutput) == 8160);

    // Nothing but a number of frames, from none to ten seconds.
    CHECK(SetDelayFrames(-1) == kAudioHardwareIllegalOperationError);
    CHECK(SetDelayFrames(10 * 48000 + 1) == kAudioHardwareIllegalOperationError);
    CHECK(SetDelay(CFSTR("8160")) == kAudioHardwareIllegalOperationError);
    double fraction = 100.5;
    CFNumberRef notWhole = CFNumberCreate(NULL, kCFNumberDoubleType, &fraction);
    CHECK(SetDelay(notWhole) == kAudioHardwareIllegalOperationError);
    CFRelease(notWhole);
    UInt32 frames = 4800;
    CHECK(Set(speaker, kStreamDelay, sizeof frames, &frames) == kAudioHardwareBadPropertySizeError);
    CHECK(Delay() == 8160);
    CHECK(Set(loopback, kStreamDelay, sizeof(CFPropertyListRef), &(CFPropertyListRef){ CFSTR("") })
          == kAudioHardwareUnknownPropertyError);

    // Once nothing records the loopback, nothing streams the speaker: it plays at once again, and says so.
    CHECK(D->StartIO(driver, loopback, 0) == noErr);
    CHECK(D->StartIO(driver, loopback, 0) == noErr);
    CHECK(D->StopIO(driver, loopback, 0) == noErr);
    CHECK(Delay() == 8160);
    before = changes;
    CHECK(D->StopIO(driver, loopback, 0) == noErr);
    EVENTUALLY(Delay() == 0);
    EVENTUALLY(U32(speaker, kAudioDevicePropertyLatency, kOutput) == 0);
    EVENTUALLY(changes > before);
}

#pragma mark - Playing and recording

enum { kFrames = 512, kRing = 16384 };

static void Play(Float64 sampleTime, const Float32* frames) {
    AudioServerPlugInIOCycleInfo cycle = { .mNominalIOBufferFrameSize = kFrames };
    cycle.mOutputTime.mSampleTime = sampleTime;
    CHECK(D->DoIOOperation(driver, speaker, speakerStream, 0, kAudioServerPlugInIOOperationWriteMix, kFrames, &cycle,
                           (void*)frames, NULL) == noErr);
}

static void Record(Float64 sampleTime, Float32* frames) {
    AudioServerPlugInIOCycleInfo cycle = { .mNominalIOBufferFrameSize = kFrames };
    cycle.mInputTime.mSampleTime = sampleTime;
    CHECK(D->DoIOOperation(driver, loopback, loopbackStream, 0, kAudioServerPlugInIOOperationReadInput, kFrames, &cycle,
                           frames, NULL) == noErr);
}

/// The largest difference between what was recorded and what was played times `gain`.
static Float32 Error(const Float32* played, const Float32* recorded, Float32 gain) {
    Float32 worst = 0;
    for (int i = 0; i < kFrames * 2; i++) worst = fmaxf(worst, fabsf(recorded[i] - played[i] * gain));
    return worst;
}

static void TestLoopback(void) {
    Boolean will = false, inPlace = false;
    CHECK(D->WillDoIOOperation(driver, speaker, 0, kAudioServerPlugInIOOperationWriteMix, &will, &inPlace) == noErr);
    CHECK(will && inPlace);
    CHECK(D->WillDoIOOperation(driver, speaker, 0, kAudioServerPlugInIOOperationReadInput, &will, &inPlace) == noErr);
    CHECK(!will);
    CHECK(D->WillDoIOOperation(driver, loopback, 0, kAudioServerPlugInIOOperationReadInput, &will, &inPlace) == noErr);
    CHECK(will);
    CHECK(D->WillDoIOOperation(driver, loopback, 0, kAudioServerPlugInIOOperationWriteMix, &will, &inPlace) == noErr);
    CHECK(!will);

    CHECK(D->StopIO(driver, speaker, 0) == kAudioHardwareIllegalOperationError);
    CHECK(D->StartIO(driver, speaker, 0) == noErr);
    CHECK(D->StartIO(driver, loopback, 0) == noErr);
    CHECK(U32(speaker, kAudioDevicePropertyDeviceIsRunning, kGlobal) == 1);

    // Both devices keep one time line, a period at a time, never ahead of now.
    Float64 speakerTime, loopbackTime;
    UInt64 speakerHost, loopbackHost, seed;
    CHECK(D->GetZeroTimeStamp(driver, speaker, 0, &speakerTime, &speakerHost, &seed) == noErr);
    CHECK(D->GetZeroTimeStamp(driver, loopback, 0, &loopbackTime, &loopbackHost, &seed) == noErr);
    CHECK(fmod(speakerTime, kRing) == 0 && speakerHost <= mach_absolute_time());
    CHECK(loopbackTime == speakerTime || loopbackTime == speakerTime + kRing);

    Float32 played[kFrames * 2], recorded[kFrames * 2];
    for (int i = 0; i < kFrames; i++) {
        played[i * 2] = 0.5f * sinf(2 * (float)M_PI * 997 * i / 48000);
        played[i * 2 + 1] = -0.5f * sinf(2 * (float)M_PI * 1499 * i / 48000);
    }
    Float32 full = 1;
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof full, &full) == noErr);

    // What's played comes back at the same sample time, across the end of the ring too.
    Float64 t = 7.0 * kRing - 100;
    Play(t, played);
    Record(t, recorded);
    CHECK(Error(played, recorded, 1) == 0);
    // Nothing has been played after it yet.
    Record(t + kFrames, recorded);
    CHECK(Error(played, recorded, 0) == 0);
    // Restarted, the speaker has played nothing yet either.
    Play(t, played);
    CHECK(D->PerformDeviceConfigurationChange(driver, speaker, 0, NULL) == noErr);
    Record(t, recorded);
    CHECK(Error(played, recorded, 0) == 0);
    CHECK(D->PerformDeviceConfigurationChange(driver, loopback, 0, NULL) == noErr);

    // At half volume it plays at a quarter of the gain; muted, not at all.
    Float32 half = 0.5f;
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof half, &half) == noErr);
    Play(t, played);
    Record(t, recorded);
    CHECK(Error(played, recorded, 0.25f) < 1e-7f);
    CHECK(Set(volume, kAudioLevelControlPropertyScalarValue, sizeof full, &full) == noErr);
    UInt32 on = 1, off = 0;
    CHECK(Set(mute, kAudioBooleanControlPropertyValue, sizeof on, &on) == noErr);
    Play(t, played);
    Record(t, recorded);
    CHECK(Error(played, recorded, 0) == 0);
    CHECK(Set(mute, kAudioBooleanControlPropertyValue, sizeof off, &off) == noErr);

    // Once the speaker stops, the loopback hears silence rather than what it last played.
    Play(t, played);
    CHECK(D->StopIO(driver, speaker, 0) == noErr);
    CHECK(U32(speaker, kAudioDevicePropertyDeviceIsRunning, kGlobal) == 0);
    Record(t, recorded);
    CHECK(Error(played, recorded, 0) == 0);
    CHECK(D->StopIO(driver, loopback, 0) == noErr);
}

int main(void) {
    TestLoading();
    TestObjects();
    TestEveryProperty();
    TestSettings();
    TestStreamDelay();
    TestLoopback();
    if (failures) {
        fprintf(stderr, "%d failed\n", failures);
        return 1;
    }
    printf("Ambient speaker: all tests passed\n");
    return 0;
}
