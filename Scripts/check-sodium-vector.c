/* Compile against libsodium 1.0.22; expected output independently generated
   by the pinned PHC reference implementation, not by this library. */
#include <sodium.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
int main(void) {
    const char *password = "fictional cross-implementation phrase";
    const char *expected = "f4b6d9e2ab7ae6700a8d1478e8453f6a5297f8bb8956f16cbc5d2a0353559fdf";
    unsigned char salt[16], output[32]; char hex[65];
    for (unsigned int i = 0; i < 16; ++i) salt[i] = (unsigned char)i;
    if (sodium_init() < 0) return 1;
    clock_t start = clock();
    if (crypto_pwhash_argon2id(output, sizeof output, password, strlen(password), salt,
        3, 65536 * 1024, crypto_pwhash_argon2id_ALG_ARGON2ID13) != 0) return 2;
    sodium_bin2hex(hex, sizeof hex, output, sizeof output);
    if (strcmp(hex, expected) != 0) return 3;
    printf("PASS: libsodium %s matches PHC reference; 64 MiB / 3 passes / 1 lane; %.3f CPU seconds\n", sodium_version_string(), (double)(clock()-start)/CLOCKS_PER_SEC);
    sodium_memzero(output, sizeof output);
    return 0;
}
