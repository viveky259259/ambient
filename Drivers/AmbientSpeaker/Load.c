// Loads a built AmbientSpeaker.driver the way coreaudiod does, through CFPlugIn and its Info.plist, and asks it for the
// speaker's name. scripts/build-speaker.sh runs it on what it built.
//
//   load-speaker build/AmbientSpeaker.driver

#include <CoreAudio/AudioServerPlugIn.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: load-speaker AmbientSpeaker.driver\n");
        return 64;
    }
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)argv[1], (CFIndex)strlen(argv[1]), true);
    CFPlugInRef plugIn = url ? CFPlugInCreate(NULL, url) : NULL;
    CFArrayRef factories = plugIn ? CFPlugInFindFactoriesForPlugInTypeInPlugIn(kAudioServerPlugInTypeUUID, plugIn) : NULL;
    if (!factories || CFArrayGetCount(factories) != 1) {
        fprintf(stderr, "%s: no Core Audio driver factory in its Info.plist\n", argv[1]);
        return 1;
    }
    CFUUIDRef factory = CFArrayGetValueAtIndex(factories, 0);
    IUnknownVTbl** unknown = CFPlugInInstanceCreate(NULL, factory, kAudioServerPlugInTypeUUID);
    if (!unknown) {
        fprintf(stderr, "%s: its factory didn't make a driver\n", argv[1]);
        return 1;
    }
    AudioServerPlugInDriverRef driver = NULL;
    HRESULT result = (*unknown)->QueryInterface(unknown, CFUUIDGetUUIDBytes(kAudioServerPlugInDriverInterfaceUUID),
                                                (LPVOID*)&driver);
    if (result != S_OK || !driver) {
        fprintf(stderr, "%s: no driver interface\n", argv[1]);
        return 1;
    }

    // Enough of a host to start it, then the speaker's name.
    static AudioServerPlugInHostInterface host;
    CFStringRef uid = CFSTR("com.viveky259259.Ambient.speaker"), name = NULL;
    AudioObjectID speaker = kAudioObjectUnknown;
    AudioObjectPropertyAddress translate = { kAudioPlugInPropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal,
                                             kAudioObjectPropertyElementMain };
    AudioObjectPropertyAddress named = { kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
    UInt32 size = 0;
    if ((*driver)->Initialize(driver, &host) != noErr
        || (*driver)->GetPropertyData(driver, kAudioObjectPlugInObject, 0, &translate, sizeof uid, &uid, sizeof speaker,
                                      &size, &speaker) != noErr
        || (*driver)->GetPropertyData(driver, speaker, 0, &named, 0, NULL, sizeof name, &size, &name) != noErr || !name) {
        fprintf(stderr, "%s: loaded, but couldn't find its speaker\n", argv[1]);
        return 1;
    }
    char text[64];
    CFStringGetCString(name, text, sizeof text, kCFStringEncodingUTF8);
    printf("Loaded %s: its speaker is \"%s\"\n", argv[1], text);
    (*driver)->Release(driver);
    (*unknown)->Release(unknown);
    return 0;
}
