#include <stdio.h>
#include <time.h>
#include "argon2.h"
int main(void) {
    unsigned char out[32];
    clock_t start = clock();
    int status = argon2id_hash_raw(3, 65536, 1, "fictional benchmark phrase", 26, "fictional-salt16", 16, out, sizeof out);
    if (status != ARGON2_OK) return 1;
    printf("Argon2id v1.3, 64 MiB, 3 passes, 1 lane: %.3f CPU seconds\n", (double)(clock()-start)/CLOCKS_PER_SEC);
    return 0;
}
