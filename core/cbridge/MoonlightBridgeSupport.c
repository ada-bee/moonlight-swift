#include "MoonlightBridgeSupport.h"

static void *g_activeContext = 0;

extern void MoonlightSwiftConnectionStageStarting(void *context, int stage);
extern void MoonlightSwiftConnectionStageComplete(void *context, int stage);
extern void MoonlightSwiftConnectionStageFailed(void *context, int stage, int errorCode);
extern void MoonlightSwiftConnectionStarted(void *context);
extern void MoonlightSwiftConnectionTerminated(void *context, int errorCode);
extern int MoonlightSwiftVideoSetup(void *context, int videoFormat, int width, int height, int redrawRate, int drFlags);
extern void MoonlightSwiftVideoStart(void *context);
extern void MoonlightSwiftVideoStop(void *context);
extern void MoonlightSwiftVideoCleanup(void *context);
extern int MoonlightSwiftVideoSubmitDecodeUnit(void *context, PDECODE_UNIT decodeUnit);
extern int MoonlightSwiftAudioInit(void *context, int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, int arFlags);
extern void MoonlightSwiftAudioStart(void *context);
extern void MoonlightSwiftAudioStop(void *context);
extern void MoonlightSwiftAudioCleanup(void *context);
extern void MoonlightSwiftAudioDecodeAndPlaySample(void *context, char *sampleData, int sampleLength);

static void connectionStageStarting(int stage) {
    MoonlightSwiftConnectionStageStarting(g_activeContext, stage);
}

static void connectionStageComplete(int stage) {
    MoonlightSwiftConnectionStageComplete(g_activeContext, stage);
}

static void connectionStageFailed(int stage, int errorCode) {
    MoonlightSwiftConnectionStageFailed(g_activeContext, stage, errorCode);
}

static void connectionStarted(void) {
    MoonlightSwiftConnectionStarted(g_activeContext);
}

static void connectionTerminated(int errorCode) {
    MoonlightSwiftConnectionTerminated(g_activeContext, errorCode);
}

static int videoSetup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags) {
    return MoonlightSwiftVideoSetup(context, videoFormat, width, height, redrawRate, drFlags);
}

static void videoStart(void) {
    MoonlightSwiftVideoStart(g_activeContext);
}

static void videoStop(void) {
    MoonlightSwiftVideoStop(g_activeContext);
}

static void videoCleanup(void) {
    MoonlightSwiftVideoCleanup(g_activeContext);
}

static int videoSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
    return MoonlightSwiftVideoSubmitDecodeUnit(g_activeContext, decodeUnit);
}

static int audioInit(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void *context, int arFlags) {
    return MoonlightSwiftAudioInit(context, audioConfiguration, opusConfig, arFlags);
}

static void audioStart(void) {
    MoonlightSwiftAudioStart(g_activeContext);
}

static void audioStop(void) {
    MoonlightSwiftAudioStop(g_activeContext);
}

static void audioCleanup(void) {
    MoonlightSwiftAudioCleanup(g_activeContext);
}

static void audioDecodeAndPlaySample(char *sampleData, int sampleLength) {
    MoonlightSwiftAudioDecodeAndPlaySample(g_activeContext, sampleData, sampleLength);
}

void MoonlightBridgeSetActiveContext(void *context) {
    g_activeContext = context;
}

void MoonlightBridgeInstallCallbacks(CONNECTION_LISTENER_CALLBACKS *connectionCallbacks,
                                     DECODER_RENDERER_CALLBACKS *videoCallbacks,
                                     AUDIO_RENDERER_CALLBACKS *audioCallbacks) {
    LiInitializeConnectionCallbacks(connectionCallbacks);
    LiInitializeVideoCallbacks(videoCallbacks);
    LiInitializeAudioCallbacks(audioCallbacks);

    connectionCallbacks->stageStarting = connectionStageStarting;
    connectionCallbacks->stageComplete = connectionStageComplete;
    connectionCallbacks->stageFailed = connectionStageFailed;
    connectionCallbacks->connectionStarted = connectionStarted;
    connectionCallbacks->connectionTerminated = connectionTerminated;

    videoCallbacks->setup = videoSetup;
    videoCallbacks->start = videoStart;
    videoCallbacks->stop = videoStop;
    videoCallbacks->cleanup = videoCleanup;
    videoCallbacks->submitDecodeUnit = videoSubmitDecodeUnit;

    audioCallbacks->init = audioInit;
    audioCallbacks->start = audioStart;
    audioCallbacks->stop = audioStop;
    audioCallbacks->cleanup = audioCleanup;
    audioCallbacks->decodeAndPlaySample = audioDecodeAndPlaySample;
}
