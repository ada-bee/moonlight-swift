#include <stddef.h>
#pragma once

#include <Limelight.h>

#ifdef __cplusplus
extern "C" {
#endif

void MoonlightBridgeSetActiveContext(void *context);
void MoonlightBridgeInstallCallbacks(CONNECTION_LISTENER_CALLBACKS *connectionCallbacks,
                                     DECODER_RENDERER_CALLBACKS *videoCallbacks,
                                     AUDIO_RENDERER_CALLBACKS *audioCallbacks);
int MoonlightBridgeHTTPSGet(const char *host,
                            int port,
                            const char *pathAndQuery,
                            const unsigned char *certificatePEM,
                            size_t certificatePEMLength,
                            const unsigned char *privateKeyPEM,
                            size_t privateKeyPEMLength,
                            const unsigned char *pinnedServerCertificatePEM,
                            size_t pinnedServerCertificatePEMLength,
                            unsigned char **outBytes,
                            size_t *outLength,
                            int *outStatusCode,
                            char **outErrorMessage);
void MoonlightBridgeFreeBytes(void *pointer);

#ifdef __cplusplus
}
#endif
