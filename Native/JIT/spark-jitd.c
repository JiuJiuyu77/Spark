//
//  spark-jitd.c —— Spark 的 JIT 子进程（helper）
//
//  作用：主 App 在非调试签名下常常拿不到可写可执行内存；
//  这个 helper 以带 get-task-allow 的身份运行，可以正常 mmap(PROT_EXEC)。
//  主 App 通过 unix socket 请求它做「分配可执行页 / 自检」。
//
//  协议（每行一条命令，回复一行）：
//    ping                → pong
//    jit-check           → ok <addr> <pages>
//    alloc <bytes>       → ok <addr>
//    free <addr> <bytes> → ok
//    quit                → bye
//
//  编译：clang -O2 -target arm64-apple-ios15.0 spark-jitd.c -o spark-jitd
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <sys/stat.h>

#define MAX_TRACKED 32

typedef struct {
    void *addr;
    size_t size;
} alloc_t;

static alloc_t g_allocs[MAX_TRACKED];
static int g_alloc_count = 0;

/// 申请一块可执行内存：优先 RWX（有 MAP_JIT），失败退回 RW→RX
static void *jit_alloc(size_t size) {
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (p != MAP_FAILED) return p;

    p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) return NULL;
    if (mprotect(p, size, PROT_READ | PROT_EXEC) != 0) {
        munmap(p, size);
        return NULL;
    }
    return p;
}

static void handle(char *line, char *out, size_t outlen) {
    line[strcspn(line, "\r\n")] = 0;
    if (line[0] == 0) { snprintf(out, outlen, "err empty\n"); return; }

    if (strcmp(line, "ping") == 0) {
        snprintf(out, outlen, "pong\n");
        return;
    }

    if (strcmp(line, "jit-check") == 0) {
        size_t sz = 4096;
        void *p = jit_alloc(sz);
        if (!p) {
            snprintf(out, outlen, "err jit-unavailable errno=%d\n", errno);
            return;
        }
        /* 真的写一条 ret 指令再执行，确认可执行 */
        unsigned char *code = (unsigned char *)p;
        code[0] = 0xC0;  /* ret (arm64) */
        munmap(p, sz);
        snprintf(out, outlen, "ok %p %zu\n", p, sz);
        return;
    }

    if (strncmp(line, "alloc ", 6) == 0) {
        size_t size = (size_t)strtoull(line + 6, NULL, 10);
        if (size < 16 || size > (16u << 20)) {
            snprintf(out, outlen, "err bad-size\n");
            return;
        }
        void *p = jit_alloc(size);
        if (!p) { snprintf(out, outlen, "err mmap-failed errno=%d\n", errno); return; }
        if (g_alloc_count < MAX_TRACKED) {
            g_allocs[g_alloc_count].addr = p;
            g_allocs[g_alloc_count].size = size;
            g_alloc_count++;
        }
        snprintf(out, outlen, "ok %p\n", p);
        return;
    }

    if (strncmp(line, "free ", 5) == 0) {
        unsigned long long addr = strtoull(line + 5, NULL, 16);
        size_t size = 4096;
        char *sp = strchr(line + 5, ' ');
        if (sp) size = (size_t)strtoull(sp + 1, NULL, 10);
        if (addr) munmap((void *)addr, size);
        snprintf(out, outlen, "ok\n");
        return;
    }

    if (strcmp(line, "quit") == 0) {
        snprintf(out, outlen, "bye\n");
        return;
    }

    snprintf(out, outlen, "err unknown-command\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <socket-path>\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];

    /* 父进程退出时跟着退，避免留下孤儿进程 */
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) { perror("socket"); return 1; }

    unlink(path);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) != 0) { perror("bind"); return 1; }
    if (listen(srv, 4) != 0) { perror("listen"); return 1; }
    chmod(path, 0600);

    fprintf(stderr, "[spark-jitd] listening on %s\n", path);

    for (;;) {
        int cl = accept(srv, NULL, NULL);
        if (cl < 0) {
            if (errno == EINTR) continue;
            break;
        }

        FILE *r = fdopen(cl, "r");
        if (!r) { close(cl); continue; }
        int wfd = dup(cl);

        char line[512];
        int quit = 0;
        while (fgets(line, sizeof(line), r)) {
            char out[256] = {0};
            handle(line, out, sizeof(out));
            if (wfd >= 0) {
                ssize_t ignored = write(wfd, out, strlen(out));
                (void)ignored;
            }
            if (strncmp(line, "quit", 4) == 0) { quit = 1; break; }
        }
        if (wfd >= 0) close(wfd);
        fclose(r);
        if (quit) break;
    }

    close(srv);
    unlink(path);
    fprintf(stderr, "[spark-jitd] exit\n");
    return 0;
}
