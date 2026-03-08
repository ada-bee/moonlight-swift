#include "MoonlightBridgeSupport.h"

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *MoonlightBridgeCopySSLError(void) {
    unsigned long code = ERR_get_error();
    if (code == 0) {
        const char *fallback = "Unknown OpenSSL error";
        char *message = malloc(strlen(fallback) + 1);
        if (message != NULL) {
            strcpy(message, fallback);
        }
        return message;
    }

    char buffer[256];
    ERR_error_string_n(code, buffer, sizeof(buffer));
    char *message = malloc(strlen(buffer) + 1);
    if (message != NULL) {
        strcpy(message, buffer);
    }
    return message;
}

static int MoonlightBridgeAppendBytes(unsigned char **buffer, size_t *length, size_t *capacity, const unsigned char *bytes, size_t byteCount) {
    if (*length + byteCount + 1 > *capacity) {
        size_t newCapacity = *capacity == 0 ? 4096 : *capacity;
        while (*length + byteCount + 1 > newCapacity) {
            newCapacity *= 2;
        }

        unsigned char *newBuffer = realloc(*buffer, newCapacity);
        if (newBuffer == NULL) {
            return 0;
        }

        *buffer = newBuffer;
        *capacity = newCapacity;
    }

    memcpy(*buffer + *length, bytes, byteCount);
    *length += byteCount;
    (*buffer)[*length] = '\0';
    return 1;
}

static int MoonlightBridgeLoadClientCredentials(SSL_CTX *context,
                                                const unsigned char *certificatePEM,
                                                size_t certificatePEMLength,
                                                const unsigned char *privateKeyPEM,
                                                size_t privateKeyPEMLength,
                                                char **outErrorMessage) {
    BIO *certificateBIO = BIO_new_mem_buf(certificatePEM, (int) certificatePEMLength);
    BIO *privateKeyBIO = BIO_new_mem_buf(privateKeyPEM, (int) privateKeyPEMLength);
    X509 *certificate = NULL;
    EVP_PKEY *privateKey = NULL;
    int result = 0;

    if (certificateBIO == NULL || privateKeyBIO == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    certificate = PEM_read_bio_X509(certificateBIO, NULL, NULL, NULL);
    privateKey = PEM_read_bio_PrivateKey(privateKeyBIO, NULL, NULL, NULL);
    if (certificate == NULL || privateKey == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    if (SSL_CTX_use_certificate(context, certificate) != 1 || SSL_CTX_use_PrivateKey(context, privateKey) != 1) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    result = 1;

cleanup:
    EVP_PKEY_free(privateKey);
    X509_free(certificate);
    BIO_free(certificateBIO);
    BIO_free(privateKeyBIO);
    return result;
}

static int MoonlightBridgeCheckPinnedCertificate(SSL *ssl,
                                                 const unsigned char *pinnedServerCertificatePEM,
                                                 size_t pinnedServerCertificatePEMLength,
                                                 char **outErrorMessage) {
    if (pinnedServerCertificatePEM == NULL || pinnedServerCertificatePEMLength == 0) {
        return 1;
    }

    BIO *pinnedBIO = BIO_new_mem_buf(pinnedServerCertificatePEM, (int) pinnedServerCertificatePEMLength);
    X509 *pinnedCertificate = NULL;
    X509 *peerCertificate = NULL;
    int result = 0;

    if (pinnedBIO == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    pinnedCertificate = PEM_read_bio_X509(pinnedBIO, NULL, NULL, NULL);
    peerCertificate = SSL_get1_peer_certificate(ssl);
    if (pinnedCertificate == NULL || peerCertificate == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    if (X509_cmp(peerCertificate, pinnedCertificate) != 0) {
        const char *message = "Pinned Sunshine certificate did not match the TLS peer certificate";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    result = 1;

cleanup:
    X509_free(peerCertificate);
    X509_free(pinnedCertificate);
    BIO_free(pinnedBIO);
    return result;
}

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
                            char **outErrorMessage) {
    SSL_CTX *context = NULL;
    BIO *connection = NULL;
    SSL *ssl = NULL;
    unsigned char *responseBuffer = NULL;
    size_t responseLength = 0;
    size_t responseCapacity = 0;
    char portString[16];
    int result = 1;

    if (outBytes == NULL || outLength == NULL || outStatusCode == NULL || outErrorMessage == NULL) {
        return 0;
    }

    *outBytes = NULL;
    *outLength = 0;
    *outStatusCode = 0;
    *outErrorMessage = NULL;

    SSL_library_init();
    SSL_load_error_strings();

    context = SSL_CTX_new(TLS_client_method());
    if (context == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    SSL_CTX_set_verify(context, SSL_VERIFY_NONE, NULL);

    if (!MoonlightBridgeLoadClientCredentials(context,
                                              certificatePEM,
                                              certificatePEMLength,
                                              privateKeyPEM,
                                              privateKeyPEMLength,
                                              outErrorMessage)) {
        goto cleanup;
    }

    connection = BIO_new_ssl_connect(context);
    if (connection == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    BIO_get_ssl(connection, &ssl);
    if (ssl == NULL) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    SSL_set_tlsext_host_name(ssl, host);
    BIO_set_conn_hostname(connection, host);
    snprintf(portString, sizeof(portString), "%d", port);
    BIO_set_conn_port(connection, portString);

    if (BIO_do_connect(connection) <= 0 || BIO_do_handshake(connection) <= 0) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    if (!MoonlightBridgeCheckPinnedCertificate(ssl,
                                               pinnedServerCertificatePEM,
                                               pinnedServerCertificatePEMLength,
                                               outErrorMessage)) {
        goto cleanup;
    }

    char requestBuffer[4096];
    int requestLength = snprintf(requestBuffer,
                                 sizeof(requestBuffer),
                                 "GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nAccept: */*\r\n\r\n",
                                 pathAndQuery,
                                 host);
    if (requestLength <= 0 || requestLength >= (int) sizeof(requestBuffer)) {
        const char *message = "Failed to build HTTPS request";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    if (BIO_write(connection, requestBuffer, requestLength) != requestLength) {
        *outErrorMessage = MoonlightBridgeCopySSLError();
        goto cleanup;
    }

    for (;;) {
        unsigned char chunk[4096];
        int bytesRead = BIO_read(connection, chunk, sizeof(chunk));
        if (bytesRead > 0) {
            if (!MoonlightBridgeAppendBytes(&responseBuffer, &responseLength, &responseCapacity, chunk, (size_t) bytesRead)) {
                const char *message = "Failed to grow HTTPS response buffer";
                *outErrorMessage = malloc(strlen(message) + 1);
                if (*outErrorMessage != NULL) {
                    strcpy(*outErrorMessage, message);
                }
                goto cleanup;
            }
            continue;
        }

        if (bytesRead == 0) {
            break;
        }

        if (!BIO_should_retry(connection)) {
            *outErrorMessage = MoonlightBridgeCopySSLError();
            goto cleanup;
        }
    }

    if (responseBuffer == NULL) {
        const char *message = "Sunshine returned an empty HTTPS response";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    char *headerEnd = strstr((char *) responseBuffer, "\r\n\r\n");
    if (headerEnd == NULL) {
        const char *message = "Invalid HTTPS response from Sunshine";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    int statusCode = 0;
    if (sscanf((char *) responseBuffer, "HTTP/%*d.%*d %d", &statusCode) != 1) {
        const char *message = "Failed to parse Sunshine HTTPS response status";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    unsigned char *bodyStart = (unsigned char *) headerEnd + 4;
    size_t bodyLength = responseLength - (size_t) (bodyStart - responseBuffer);
    unsigned char *body = malloc(bodyLength == 0 ? 1 : bodyLength);
    if (body == NULL) {
        const char *message = "Failed to allocate HTTPS response body buffer";
        *outErrorMessage = malloc(strlen(message) + 1);
        if (*outErrorMessage != NULL) {
            strcpy(*outErrorMessage, message);
        }
        goto cleanup;
    }

    if (bodyLength > 0) {
        memcpy(body, bodyStart, bodyLength);
    }

    *outBytes = body;
    *outLength = bodyLength;
    *outStatusCode = statusCode;
    result = 0;

cleanup:
    if (responseBuffer != NULL) {
        free(responseBuffer);
    }
    BIO_free_all(connection);
    SSL_CTX_free(context);
    return result;
}

void MoonlightBridgeFreeBytes(void *pointer) {
    free(pointer);
}
