/* openamigacurl host test: a local HTTP/2 server over TLS for the
 * OpenTLS backend, on nghttp2's library (built from the same tarball as the
 * Amiga build's) and the host's OpenSSL.
 *
 *     h2_server PORT CERT KEY [tls13|tls13-notickets]
 *
 * It speaks only h2, chosen by ALPN, and only TLS 1.2, or with "tls13" only
 * TLS 1.3 (OpenSSL then sends two session tickets after each handshake);
 * "tls13-notickets" is "tls13" that sends no tickets.
 * GET /N answers N bytes; POST answers the body's SHA-256 and length, as
 * tls_server.py does. Every answer carries "x-conn: C", C counting the TLS
 * connections the server has accepted, so a test can see which transfers
 * shared a connection. A request with an x-close header ends its connection
 * (GOAWAY, sent before the answer), so the next request needs a new one.
 * One thread per connection, blocking I/O.
 * MIT, Copyright (c) 2026 AmigaChrome Team. */
#define _GNU_SOURCE
#include <nghttp2/nghttp2.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

struct conn {
    SSL *ssl;
    int fd;
    unsigned id;
    int close_after;
};

struct stream {
    char path[256];
    int post;
    int x_close;
    EVP_MD_CTX *sha;
    unsigned long got;
    char body[96];       /* a POST's answer */
    size_t body_len;
    unsigned long left;  /* bytes still to send */
    size_t sent;
};

static unsigned conn_count;
static pthread_mutex_t count_lock = PTHREAD_MUTEX_INITIALIZER;

static nghttp2_ssize send_cb(nghttp2_session *s, const uint8_t *data, size_t len, int flags, void *user)
{
    struct conn *c = user;
    int n = SSL_write(c->ssl, data, (int)len);
    (void)s; (void)flags;
    return n > 0 ? n : NGHTTP2_ERR_CALLBACK_FAILURE;
}

static int begin_headers_cb(nghttp2_session *s, const nghttp2_frame *f, void *user)
{
    struct stream *st;
    (void)user;
    if (f->hd.type != NGHTTP2_HEADERS || f->headers.cat != NGHTTP2_HCAT_REQUEST)
        return 0;
    st = calloc(1, sizeof *st);
    if (!st)
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    nghttp2_session_set_stream_user_data(s, f->hd.stream_id, st);
    return 0;
}

static int header_cb(nghttp2_session *s, const nghttp2_frame *f, const uint8_t *name, size_t namelen,
                     const uint8_t *value, size_t valuelen, uint8_t flags, void *user)
{
    struct stream *st = nghttp2_session_get_stream_user_data(s, f->hd.stream_id);
    (void)flags; (void)user;
    if (!st)
        return 0;
    if (namelen == 5 && !memcmp(name, ":path", 5) && valuelen < sizeof st->path) {
        memcpy(st->path, value, valuelen);
        st->path[valuelen] = 0;
    } else if (namelen == 7 && !memcmp(name, ":method", 7)) {
        st->post = valuelen == 4 && !memcmp(value, "POST", 4);
        if (st->post && !st->sha) {
            st->sha = EVP_MD_CTX_new();
            EVP_DigestInit_ex(st->sha, EVP_sha256(), NULL);
        }
    } else if (namelen == 7 && !memcmp(name, "x-close", 7)) {
        st->x_close = 1;
    }
    return 0;
}

static int data_chunk_cb(nghttp2_session *s, uint8_t flags, int32_t id, const uint8_t *data, size_t len, void *user)
{
    struct stream *st = nghttp2_session_get_stream_user_data(s, id);
    (void)flags; (void)user;
    if (st && st->sha) {
        EVP_DigestUpdate(st->sha, data, len);
        st->got += len;
    }
    return 0;
}

static nghttp2_ssize read_cb(nghttp2_session *s, int32_t id, uint8_t *buf, size_t len, uint32_t *flags,
                             nghttp2_data_source *src, void *user)
{
    struct stream *st = src->ptr;
    size_t n;
    (void)s; (void)id; (void)user;
    if (st->post) {
        n = st->body_len - st->sent;
        if (n > len) n = len;
        memcpy(buf, st->body + st->sent, n);
        st->sent += n;
        if (st->sent == st->body_len) *flags |= NGHTTP2_DATA_FLAG_EOF;
    } else {
        n = st->left < len ? (size_t)st->left : len;
        memset(buf, 'y', n);
        st->left -= n;
        if (!st->left) *flags |= NGHTTP2_DATA_FLAG_EOF;
    }
    return (nghttp2_ssize)n;
}

static int respond(nghttp2_session *s, struct conn *c, int32_t id, struct stream *st)
{
    char len[32], conn[16];
    nghttp2_data_provider2 dp;
    nghttp2_nv nv[3];

    if (st->post) {
        unsigned char md[32];
        unsigned i, mdlen = 0;
        EVP_DigestFinal_ex(st->sha, md, &mdlen);
        for (i = 0; i < mdlen; i++) sprintf(st->body + 2 * i, "%02x", md[i]);
        st->body_len = 64 + (size_t)sprintf(st->body + 64, " %lu\n", st->got);
        snprintf(len, sizeof len, "%zu", st->body_len);
    } else {
        st->left = strtoul(st->path + 1, NULL, 10);
        snprintf(len, sizeof len, "%lu", st->left);
    }
    snprintf(conn, sizeof conn, "%u", c->id);
#define NV(n, v) { (uint8_t *)(n), (uint8_t *)(v), sizeof(n) - 1, strlen(v), NGHTTP2_NV_FLAG_NO_COPY_NAME }
    nv[0] = (nghttp2_nv)NV(":status", "200");
    nv[1] = (nghttp2_nv)NV("content-length", len);
    nv[2] = (nghttp2_nv)NV("x-conn", conn);
    dp.source.ptr = st;
    dp.read_callback = read_cb;
    if (st->x_close) {
        /* GOAWAY goes out ahead of the answer, so the client never sends
           another request on this connection */
        c->close_after = 1;
        nghttp2_submit_goaway(s, NGHTTP2_FLAG_NONE, id, NGHTTP2_NO_ERROR, NULL, 0);
    }
    return nghttp2_submit_response2(s, id, nv, 3, &dp);
}

static int frame_recv_cb(nghttp2_session *s, const nghttp2_frame *f, void *user)
{
    struct stream *st;
    if ((f->hd.type != NGHTTP2_HEADERS && f->hd.type != NGHTTP2_DATA) || !(f->hd.flags & NGHTTP2_FLAG_END_STREAM))
        return 0;
    st = nghttp2_session_get_stream_user_data(s, f->hd.stream_id);
    if (st && respond(s, user, f->hd.stream_id, st))
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    return 0;
}

static int stream_close_cb(nghttp2_session *s, int32_t id, uint32_t err, void *user)
{
    struct stream *st = nghttp2_session_get_stream_user_data(s, id);
    struct conn *c = user;
    (void)err;
    if (st) {
        if (st->sha) EVP_MD_CTX_free(st->sha);
        free(st);
    }
    if (c->close_after)
        nghttp2_session_terminate_session(s, NGHTTP2_NO_ERROR);
    return 0;
}

static int alpn_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen, const unsigned char *in,
                   unsigned inlen, void *arg)
{
    (void)ssl; (void)arg;
    if (nghttp2_select_alpn(out, outlen, in, inlen) != 1)
        return SSL_TLSEXT_ERR_ALERT_FATAL;   /* h2 only */
    return SSL_TLSEXT_ERR_OK;
}

static void *serve(void *arg)
{
    struct conn *c = arg;
    nghttp2_session_callbacks *cb;
    nghttp2_session *s = NULL;
    nghttp2_settings_entry iv = { NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100 };
    const unsigned char *alpn = NULL;
    unsigned alpnlen = 0;
    uint8_t buf[16384];

    if (SSL_accept(c->ssl) != 1)
        goto out;
    SSL_get0_alpn_selected(c->ssl, &alpn, &alpnlen);
    if (alpnlen != 2 || memcmp(alpn, "h2", 2))
        goto out;
    nghttp2_session_callbacks_new(&cb);
    nghttp2_session_callbacks_set_send_callback2(cb, send_cb);
    nghttp2_session_callbacks_set_on_begin_headers_callback(cb, begin_headers_cb);
    nghttp2_session_callbacks_set_on_header_callback(cb, header_cb);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(cb, data_chunk_cb);
    nghttp2_session_callbacks_set_on_frame_recv_callback(cb, frame_recv_cb);
    nghttp2_session_callbacks_set_on_stream_close_callback(cb, stream_close_cb);
    nghttp2_session_server_new(&s, cb, c);
    nghttp2_session_callbacks_del(cb);
    nghttp2_submit_settings(s, NGHTTP2_FLAG_NONE, &iv, 1);
    for (;;) {
        int n;
        if (nghttp2_session_send(s))
            break;
        if (!nghttp2_session_want_read(s) && !nghttp2_session_want_write(s))
            break;
        n = SSL_read(c->ssl, buf, sizeof buf);
        if (n <= 0)
            break;
        if (nghttp2_session_mem_recv2(s, buf, (size_t)n) < 0)
            break;
    }
    SSL_shutdown(c->ssl);
    {
        /* close gracefully: data the client sent that is still unread
           would make close() answer with a reset, which can reach the
           client before the end of its answer */
        struct timeval tv = { 2, 0 };
        char sink[4096];
        shutdown(c->fd, SHUT_WR);
        setsockopt(c->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        while (recv(c->fd, sink, sizeof sink, 0) > 0)
            ;
    }
out:
    if (s) nghttp2_session_del(s);
    SSL_free(c->ssl);
    close(c->fd);
    free(c);
    return NULL;
}

int main(int argc, char **argv)
{
    struct sockaddr_in sa;
    SSL_CTX *ctx;
    int one = 1, ls;

    if (argc < 4) {
        fprintf(stderr, "usage: h2_server PORT CERT KEY [tls13|tls13-notickets]\n");
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    ctx = SSL_CTX_new(TLS_server_method());
    if (argc > 4 && !strncmp(argv[4], "tls13", 5)) {
        SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION);
        SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION);
        if (!strcmp(argv[4], "tls13-notickets"))
            SSL_CTX_set_num_tickets(ctx, 0);
    } else {
        SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
        SSL_CTX_set_max_proto_version(ctx, TLS1_2_VERSION);
    }
    SSL_CTX_set_options(ctx, SSL_OP_NO_COMPRESSION | SSL_OP_NO_RENEGOTIATION);
    if (SSL_CTX_use_certificate_chain_file(ctx, argv[2]) != 1 ||
        SSL_CTX_use_PrivateKey_file(ctx, argv[3], SSL_FILETYPE_PEM) != 1) {
        ERR_print_errors_fp(stderr);
        return 1;
    }
    SSL_CTX_set_alpn_select_cb(ctx, alpn_cb, NULL);

    ls = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)atoi(argv[1]));
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(ls, (struct sockaddr *)&sa, sizeof sa) || listen(ls, 64)) {
        perror("h2_server");
        return 1;
    }
    for (;;) {
        pthread_t t;
        struct conn *c;
        int fd = accept(ls, NULL, NULL);
        if (fd < 0)
            continue;
        c = calloc(1, sizeof *c);
        c->fd = fd;
        c->ssl = SSL_new(ctx);
        SSL_set_fd(c->ssl, fd);
        pthread_mutex_lock(&count_lock);
        c->id = ++conn_count;
        pthread_mutex_unlock(&count_lock);
        if (pthread_create(&t, NULL, serve, c) == 0)
            pthread_detach(t);
    }
}
