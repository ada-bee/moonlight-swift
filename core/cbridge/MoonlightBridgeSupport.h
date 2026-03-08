#pragma once

#include <Limelight.h>

#ifdef __cplusplus
extern "C" {
#endif

void MoonlightBridgeSetActiveContext(void *context);
void MoonlightBridgeInstallCallbacks(CONNECTION_LISTENER_CALLBACKS *connectionCallbacks,
                                     DECODER_RENDERER_CALLBACKS *videoCallbacks,
                                     AUDIO_RENDERER_CALLBACKS *audioCallbacks);

#ifdef __cplusplus
}
#endif
