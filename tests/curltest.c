/* openamigacurl smoke test: fetch an address over HTTP or HTTPS (AmiSSL). */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <curl/curl.h>
#include <utility/tagitem.h>
#include <proto/exec.h>
#include <proto/amisslmaster.h>
#include <libraries/amisslmaster.h>
#include <libraries/amissl.h>
#include <amissl/amissl.h>

/* The task's own bsdsocket and AmiSSL bases: each task opens its own. */
struct Library *SocketBase, *AmiSSLMasterBase, *AmiSSLBase, *AmiSSLExtBase;

static int openNetwork(void)
{
    if (!(SocketBase = OpenLibrary((CONST_STRPTR)"bsdsocket.library", 4))) return 0;
    if (!(AmiSSLMasterBase = OpenLibrary((CONST_STRPTR)"amisslmaster.library", AMISSLMASTER_MIN_VERSION))) return 0;
    return OpenAmiSSLTags(AMISSL_CURRENT_VERSION, AmiSSL_UsesOpenSSLStructs, TRUE, AmiSSL_GetAmiSSLBase, (ULONG)&AmiSSLBase,
        AmiSSL_GetAmiSSLExtBase, (ULONG)&AmiSSLExtBase, AmiSSL_SocketBase, (ULONG)SocketBase, AmiSSL_ErrNoPtr, (ULONG)&errno, TAG_DONE) == 0;
}

static void closeNetwork(void)
{
    if (AmiSSLBase) CloseAmiSSL();
    if (AmiSSLMasterBase) CloseLibrary(AmiSSLMasterBase);
    if (SocketBase) CloseLibrary(SocketBase);
}
static size_t got;
static char head[81];
static size_t sink(char *p, size_t s, size_t n, void *u)
{
    size_t len = s * n; (void)u;
    if (got < 80) { size_t c = len < 80 - got ? len : 80 - got; memcpy(head + got, p, c); }
    got += len; return len;
}
/* ROM mathieeesingbas.library leaves the FPU in single precision (FPCR $40)
 * in every task that opens it; doubles need FPCR 0. */
static void resetFPCR(void) { __asm__ volatile ("fmove.l %0,%%fpcr" : : "d" (0)); }

int main(int argc, char **argv)
{
    resetFPCR();
    int i;
    if (!openNetwork()) { printf("NET_FAIL bsdsocket=%p amisslmaster=%p amissl=%p\n", (void *)SocketBase, (void *)AmiSSLMasterBase, (void *)AmiSSLBase); closeNetwork(); return 20; }
    resetFPCR(); /* again: the libraries just opened may have changed it */
    curl_global_init(CURL_GLOBAL_ALL);
    printf("CURL %s\n", curl_version());
    for (i = 1; i < argc; i++) {
        CURL *c = curl_easy_init(); CURLcode rc; long code = 0; char *ct = NULL, *url = NULL;
        got = 0; memset(head, 0, sizeof head);
        curl_easy_setopt(c, CURLOPT_URL, argv[i]);
        curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, sink);
        curl_easy_setopt(c, CURLOPT_TIMEOUT, 60L);
        curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
        if (getenv("CURLTEST_VERBOSE")) { curl_easy_setopt(c, CURLOPT_VERBOSE, 1L); curl_easy_setopt(c, CURLOPT_STDERR, stdout); }
        rc = curl_easy_perform(c);
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
        curl_easy_getinfo(c, CURLINFO_CONTENT_TYPE, &ct);
        curl_easy_getinfo(c, CURLINFO_EFFECTIVE_URL, &url);
        printf("%s rc=%d (%s) http=%ld bytes=%lu type=%s final=%s\n", argv[i], rc, curl_easy_strerror(rc), code, (unsigned long)got, ct ? ct : "-", url ? url : "-");
        for (char *p = head; *p; p++) if (*p == '\n' || *p == '\r') *p = ' ';
        printf("  starts: %.60s\n", head);
        curl_easy_cleanup(c);
    }
    curl_global_cleanup();
    closeNetwork();
    printf("CURL_DONE\n");
    return 0;
}
