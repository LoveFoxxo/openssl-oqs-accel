/*
 * Copyright 2026 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License 2.0 (the "License").  You may not use
 * this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/licence.html
 */

/* Optional liboqs ML-KEM acceleration with deterministic proof and fallback. */
#include <openssl/crypto.h>
#include <openssl/rand.h>
#include <internal/cryptlib.h>
#include <internal/thread_once.h>
#include <internal/time.h>

#include "crypto/oqs_accel.h"
#include "../ml_kem/ml_kem_local.h"

#ifdef OPENSSL_OQS_ACCEL
# include <oqs/oqs.h>
# include <oqs/kem.h>

# define OQS_ACCEL_BENCH_ROUNDS 16

typedef struct {
    int evp_type;
    const char *names[3];
    CRYPTO_ONCE once;
    int keygen;
    int encap;
    int decap;
} OQS_ACCEL_STATE;

static CRYPTO_ONCE oqs_library_once = CRYPTO_ONCE_STATIC_INIT;
static int oqs_library_disabled = 0;

static void oqs_accel_selftest(size_t index);

static OQS_ACCEL_STATE oqs_states[] = {
    { EVP_PKEY_ML_KEM_512, { "ML-KEM-512", "Kyber512", NULL },
      CRYPTO_ONCE_STATIC_INIT, 0, 0, 0 },
    { EVP_PKEY_ML_KEM_768, { "ML-KEM-768", "Kyber768", NULL },
      CRYPTO_ONCE_STATIC_INIT, 0, 0, 0 },
    { EVP_PKEY_ML_KEM_1024, { "ML-KEM-1024", "Kyber1024", NULL },
      CRYPTO_ONCE_STATIC_INIT, 0, 0, 0 }
};

static OQS_ACCEL_STATE *oqs_state_lookup(int evp_type)
{
    size_t i;

    for (i = 0; i < OSSL_NELEM(oqs_states); i++) {
        if (oqs_states[i].evp_type == evp_type)
            return &oqs_states[i];
    }
    return NULL;
}

static void oqs_library_init(void)
{
    const char *env = ossl_safe_getenv("OPENSSL_OQS_ACCEL");

    if (env != NULL && (strcmp(env, "0") == 0 || strcmp(env, "off") == 0)) {
        oqs_library_disabled = 1;
        return;
    }
    OQS_init();
}

static void oqs_selftest_512(void)
{
    oqs_accel_selftest(0);
}

static void oqs_selftest_768(void)
{
    oqs_accel_selftest(1);
}

static void oqs_selftest_1024(void)
{
    oqs_accel_selftest(2);
}

static int oqs_state_prepare(OQS_ACCEL_STATE *state)
{
    void (*init)(void);

    if (state == NULL
        || !CRYPTO_THREAD_run_once(&oqs_library_once, oqs_library_init)
        || oqs_library_disabled)
        return 0;
    if (state->evp_type == EVP_PKEY_ML_KEM_512)
        init = oqs_selftest_512;
    else if (state->evp_type == EVP_PKEY_ML_KEM_768)
        init = oqs_selftest_768;
    else if (state->evp_type == EVP_PKEY_ML_KEM_1024)
        init = oqs_selftest_1024;
    else
        return 0;
    return CRYPTO_THREAD_run_once(&state->once, init);
}

static OQS_KEM *oqs_kem_new(const OQS_ACCEL_STATE *state)
{
    size_t i;

    for (i = 0; i < OSSL_NELEM(state->names) && state->names[i] != NULL; i++) {
        OQS_KEM *kem = OQS_KEM_new(state->names[i]);

        if (kem != NULL)
            return kem;
    }
    return NULL;
}

static int oqs_kem_compatible(const OQS_KEM *kem, const ML_KEM_VINFO *vinfo)
{
    return kem != NULL
        && kem->length_public_key == vinfo->pubkey_bytes
        && kem->length_secret_key == vinfo->prvkey_bytes
        && kem->length_ciphertext == vinfo->ctext_bytes
        && kem->length_shared_secret == ML_KEM_SHARED_SECRET_BYTES
        && kem->length_keypair_seed == ML_KEM_SEED_BYTES
        && kem->length_encaps_seed == ML_KEM_RANDOM_BYTES
        && kem->keypair_derand != NULL
        && kem->encaps_derand != NULL
        && kem->decaps != NULL;
}

/* Generate from OpenSSL-supplied entropy and retain d exactly as native keygen. */
static int oqs_genkey_core(OQS_KEM *kem, uint8_t *pk, uint8_t *sk,
                           const uint8_t seed[ML_KEM_SEED_BYTES],
                           ML_KEM_KEY *key)
{
    const ML_KEM_VINFO *vinfo = key->vinfo;

    if (OQS_KEM_keypair_derand(kem, pk, sk, seed) != OQS_SUCCESS
        || !ossl_ml_kem_parse_private_key(sk, vinfo->prvkey_bytes, key))
        return 0;
    key->d = key->z + ML_KEM_RANDOM_BYTES;
    memcpy(key->d, seed, ML_KEM_RANDOM_BYTES);
    return 1;
}

static int oqs_time_keygen_native(ML_KEM_KEY *key, uint8_t *pk, uint8_t *sk,
                                  const uint8_t *seed, uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        ossl_ml_kem_key_reset(key);
        if (ossl_ml_kem_set_seed(seed, ML_KEM_SEED_BYTES, key) == NULL
            || !ossl_ml_kem_genkey_native(pk, key->vinfo->pubkey_bytes, key)
            || !ossl_ml_kem_encode_private_key(sk, key->vinfo->prvkey_bytes, key))
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static int oqs_time_keygen_oqs(OQS_KEM *kem, ML_KEM_KEY *key,
                               uint8_t *pk, uint8_t *sk,
                               const uint8_t *seed, uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        ossl_ml_kem_key_reset(key);
        if (!oqs_genkey_core(kem, pk, sk, seed, key))
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static int oqs_time_encap_native(ML_KEM_KEY *key, uint8_t *ct, uint8_t *ss,
                                 const uint8_t *entropy, uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        if (!ossl_ml_kem_encap_seed_native(ct, key->vinfo->ctext_bytes,
                                           ss, ML_KEM_SHARED_SECRET_BYTES,
                                           entropy, ML_KEM_RANDOM_BYTES, key))
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static int oqs_time_encap_oqs(OQS_KEM *kem, const uint8_t *pk,
                              uint8_t *ct, uint8_t *ss,
                              const uint8_t *entropy, uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        if (OQS_KEM_encaps_derand(kem, ct, ss, pk, entropy) != OQS_SUCCESS)
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static int oqs_time_decap_native(ML_KEM_KEY *key, const uint8_t *ct,
                                 uint8_t *ss, uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        if (!ossl_ml_kem_decap_native(ss, ML_KEM_SHARED_SECRET_BYTES,
                                      ct, key->vinfo->ctext_bytes, key))
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static int oqs_time_decap_oqs(OQS_KEM *kem, const uint8_t *sk,
                              const uint8_t *ct, uint8_t *ss,
                              uint64_t *elapsed)
{
    size_t i;
    uint64_t start = ossl_time2ticks(ossl_time_now());

    for (i = 0; i < OQS_ACCEL_BENCH_ROUNDS; i++) {
        if (OQS_KEM_decaps(kem, ss, ct, sk) != OQS_SUCCESS)
            return 0;
    }
    *elapsed = ossl_time2ticks(ossl_time_now()) - start;
    return 1;
}

static void oqs_accel_selftest(size_t index)
{
    OQS_ACCEL_STATE *state = &oqs_states[index];
    const ML_KEM_VINFO *vinfo = ossl_ml_kem_get_vinfo(state->evp_type);
    ML_KEM_KEY *native_key = NULL, *oqs_key = NULL;
    OQS_KEM *kem = NULL;
    uint8_t *pk_native = NULL, *pk_oqs = NULL;
    uint8_t *sk_native = NULL, *sk_oqs = NULL;
    uint8_t *ct_native = NULL, *ct_oqs = NULL;
    uint8_t seed[ML_KEM_SEED_BYTES], entropy[ML_KEM_RANDOM_BYTES];
    uint8_t ss_native[ML_KEM_SHARED_SECRET_BYTES];
    uint8_t ss_oqs[ML_KEM_SHARED_SECRET_BYTES];
    uint8_t scratch[ML_KEM_SHARED_SECRET_BYTES];
    uint64_t t_native = 0, t_oqs = 0;
    size_t i;
    int ok = 0;

    state->keygen = state->encap = state->decap = 0;
    if (vinfo == NULL)
        return;
    kem = oqs_kem_new(state);
    if (!oqs_kem_compatible(kem, vinfo))
        goto end;

    native_key = ossl_ml_kem_key_new(NULL, NULL, state->evp_type);
    oqs_key = ossl_ml_kem_key_new(NULL, NULL, state->evp_type);
    pk_native = OPENSSL_malloc(vinfo->pubkey_bytes);
    pk_oqs = OPENSSL_malloc(vinfo->pubkey_bytes);
    sk_native = OPENSSL_malloc(vinfo->prvkey_bytes);
    sk_oqs = OPENSSL_malloc(vinfo->prvkey_bytes);
    ct_native = OPENSSL_malloc(vinfo->ctext_bytes);
    ct_oqs = OPENSSL_malloc(vinfo->ctext_bytes);
    if (native_key == NULL || oqs_key == NULL
        || pk_native == NULL || pk_oqs == NULL
        || sk_native == NULL || sk_oqs == NULL
        || ct_native == NULL || ct_oqs == NULL)
        goto end;

    for (i = 0; i < sizeof(seed); i++)
        seed[i] = (uint8_t)i;
    for (i = 0; i < sizeof(entropy); i++)
        entropy[i] = (uint8_t)(0xa5U + i);

    /* Identical seeds must produce byte-identical standard key encodings. */
    if (ossl_ml_kem_set_seed(seed, sizeof(seed), native_key) == NULL
        || !ossl_ml_kem_genkey_native(pk_native, vinfo->pubkey_bytes, native_key)
        || !ossl_ml_kem_encode_private_key(sk_native, vinfo->prvkey_bytes,
                                           native_key)
        || !oqs_genkey_core(kem, pk_oqs, sk_oqs, seed, oqs_key)
        || memcmp(pk_native, pk_oqs, vinfo->pubkey_bytes) != 0
        || memcmp(sk_native, sk_oqs, vinfo->prvkey_bytes) != 0)
        goto end;

    /* Deterministic encapsulation checks both ciphertext and shared secret. */
    if (!ossl_ml_kem_encap_seed_native(ct_native, vinfo->ctext_bytes,
                                       ss_native, sizeof(ss_native),
                                       entropy, sizeof(entropy), native_key)
        || OQS_KEM_encaps_derand(kem, ct_oqs, ss_oqs, pk_oqs, entropy)
            != OQS_SUCCESS
        || memcmp(ct_native, ct_oqs, vinfo->ctext_bytes) != 0
        || memcmp(ss_native, ss_oqs, sizeof(ss_native)) != 0
        || OQS_KEM_decaps(kem, scratch, ct_native, sk_native) != OQS_SUCCESS
        || memcmp(scratch, ss_native, sizeof(scratch)) != 0
        || !ossl_ml_kem_decap_native(scratch, sizeof(scratch),
                                     ct_oqs, vinfo->ctext_bytes, native_key)
        || memcmp(scratch, ss_oqs, sizeof(scratch)) != 0)
        goto end;
    ok = 1;

    /* A noisy or failed race disables only that operation for this variant. */
    if (oqs_time_encap_native(native_key, ct_native, ss_native,
                              entropy, &t_native)
        && oqs_time_encap_oqs(kem, pk_native, ct_oqs, ss_oqs,
                              entropy, &t_oqs)
        && t_native != 0 && t_oqs <= t_native)
        state->encap = 1;

    t_native = t_oqs = 0;
    if (oqs_time_decap_native(native_key, ct_native, scratch, &t_native)
        && oqs_time_decap_oqs(kem, sk_native, ct_native, scratch, &t_oqs)
        && t_native != 0 && t_oqs <= t_native)
        state->decap = 1;

    /* Run keygen last: a timing failure may leave its key object reset. */
    t_native = t_oqs = 0;
    if (oqs_time_keygen_native(native_key, pk_native, sk_native, seed, &t_native)
        && oqs_time_keygen_oqs(kem, oqs_key, pk_oqs, sk_oqs, seed, &t_oqs)
        && t_native != 0 && t_oqs <= t_native)
        state->keygen = 1;

end:
    if (!ok)
        state->keygen = state->encap = state->decap = 0;
    OPENSSL_cleanse(seed, sizeof(seed));
    OPENSSL_cleanse(entropy, sizeof(entropy));
    OPENSSL_cleanse(ss_native, sizeof(ss_native));
    OPENSSL_cleanse(ss_oqs, sizeof(ss_oqs));
    OPENSSL_cleanse(scratch, sizeof(scratch));
    if (sk_native != NULL)
        OPENSSL_clear_free(sk_native, vinfo->prvkey_bytes);
    if (sk_oqs != NULL)
        OPENSSL_clear_free(sk_oqs, vinfo->prvkey_bytes);
    OPENSSL_free(pk_native);
    OPENSSL_free(pk_oqs);
    OPENSSL_free(ct_native);
    OPENSSL_free(ct_oqs);
    ossl_ml_kem_key_free(native_key);
    ossl_ml_kem_key_free(oqs_key);
    OQS_KEM_free(kem);
}

int ossl_oqs_ml_kem_genkey(uint8_t *pubenc, size_t publen, ML_KEM_KEY *key)
{
    OQS_ACCEL_STATE *state;
    const ML_KEM_VINFO *vinfo;
    OQS_KEM *kem = NULL;
    uint8_t *pk = NULL, *sk = NULL;
    uint8_t seed[ML_KEM_SEED_BYTES];
    int had_seed = 0, ret = 0;

    if (key == NULL)
        return 0;
    state = oqs_state_lookup(key->vinfo->evp_type);
    if (!oqs_state_prepare(state) || !state->keygen)
        return 0;
    if (ossl_ml_kem_have_pubkey(key) || ossl_ml_kem_have_dkenc(key))
        return 0;
    vinfo = key->vinfo;
    if (pubenc != NULL && publen != vinfo->pubkey_bytes)
        return 0;
    kem = oqs_kem_new(state);
    if (!oqs_kem_compatible(kem, vinfo))
        goto end;

    had_seed = key->seedbuf != NULL;
    if (had_seed) {
        if (!ossl_ml_kem_encode_seed(seed, sizeof(seed), key))
            goto end;
    } else if (RAND_priv_bytes_ex(key->libctx, seed, sizeof(seed),
                                  vinfo->secbits) <= 0) {
        goto end;
    }
    pk = OPENSSL_malloc(vinfo->pubkey_bytes);
    sk = OPENSSL_malloc(vinfo->prvkey_bytes);
    if (pk == NULL || sk == NULL)
        goto end;
    if (!oqs_genkey_core(kem, pk, sk, seed, key))
        goto end;
    if (pubenc != NULL)
        memcpy(pubenc, pk, vinfo->pubkey_bytes);
    ret = 1;

end:
    if (!ret && key != NULL) {
        /* parse_private_key resets on failure; preserve deterministic fallback. */
        if (had_seed && key->seedbuf == NULL && !ossl_ml_kem_have_pubkey(key))
            (void)ossl_ml_kem_set_seed(seed, sizeof(seed), key);
        if (pubenc != NULL && publen == key->vinfo->pubkey_bytes)
            OPENSSL_cleanse(pubenc, publen);
    }
    OPENSSL_cleanse(seed, sizeof(seed));
    if (sk != NULL)
        OPENSSL_clear_free(sk, key->vinfo->prvkey_bytes);
    OPENSSL_free(pk);
    OQS_KEM_free(kem);
    return ret;
}

int ossl_oqs_ml_kem_encap_seed(uint8_t *ctext, size_t clen,
                               uint8_t *shared_secret, size_t slen,
                               const uint8_t *entropy, size_t elen,
                               const ML_KEM_KEY *key)
{
    OQS_ACCEL_STATE *state;
    const ML_KEM_VINFO *vinfo;
    OQS_KEM *kem = NULL;
    uint8_t *pk = NULL;
    int ret = 0;

    if (key == NULL || !ossl_ml_kem_have_pubkey(key))
        return 0;
    state = oqs_state_lookup(key->vinfo->evp_type);
    if (!oqs_state_prepare(state) || !state->encap)
        return 0;
    vinfo = key->vinfo;
    if (ctext == NULL || clen != vinfo->ctext_bytes
        || shared_secret == NULL || slen != ML_KEM_SHARED_SECRET_BYTES
        || entropy == NULL || elen != ML_KEM_RANDOM_BYTES)
        return 0;
    kem = oqs_kem_new(state);
    if (!oqs_kem_compatible(kem, vinfo))
        goto end;
    pk = OPENSSL_malloc(vinfo->pubkey_bytes);
    if (pk == NULL || !ossl_ml_kem_encode_public_key(pk, vinfo->pubkey_bytes, key))
        goto end;
    if (OQS_KEM_encaps_derand(kem, ctext, shared_secret, pk, entropy)
        != OQS_SUCCESS)
        goto end;
    ret = 1;

end:
    if (!ret) {
        if (ctext != NULL && clen == vinfo->ctext_bytes)
            OPENSSL_cleanse(ctext, clen);
        if (shared_secret != NULL && slen == ML_KEM_SHARED_SECRET_BYTES)
            OPENSSL_cleanse(shared_secret, slen);
    }
    OPENSSL_free(pk);
    OQS_KEM_free(kem);
    return ret;
}

int ossl_oqs_ml_kem_decap(uint8_t *shared_secret, size_t slen,
                          const uint8_t *ctext, size_t clen,
                          const ML_KEM_KEY *key)
{
    OQS_ACCEL_STATE *state;
    const ML_KEM_VINFO *vinfo;
    OQS_KEM *kem = NULL;
    uint8_t *sk = NULL;
    int ret = 0;

    if (key == NULL || !ossl_ml_kem_have_prvkey(key))
        return 0;
    state = oqs_state_lookup(key->vinfo->evp_type);
    if (!oqs_state_prepare(state) || !state->decap)
        return 0;
    vinfo = key->vinfo;
    if (shared_secret == NULL || slen != ML_KEM_SHARED_SECRET_BYTES
        || ctext == NULL || clen != vinfo->ctext_bytes)
        return 0;
    kem = oqs_kem_new(state);
    if (!oqs_kem_compatible(kem, vinfo))
        goto end;
    sk = OPENSSL_malloc(vinfo->prvkey_bytes);
    if (sk == NULL || !ossl_ml_kem_encode_private_key(sk, vinfo->prvkey_bytes, key))
        goto end;
    if (OQS_KEM_decaps(kem, shared_secret, ctext, sk) != OQS_SUCCESS)
        goto end;
    ret = 1;

end:
    if (!ret && shared_secret != NULL && slen == ML_KEM_SHARED_SECRET_BYTES)
        OPENSSL_cleanse(shared_secret, slen);
    if (sk != NULL)
        OPENSSL_clear_free(sk, vinfo->prvkey_bytes);
    OQS_KEM_free(kem);
    return ret;
}

#else

int ossl_oqs_ml_kem_genkey(uint8_t *pubenc, size_t publen, ML_KEM_KEY *key)
{
    (void)pubenc;
    (void)publen;
    (void)key;
    return 0;
}

int ossl_oqs_ml_kem_encap_seed(uint8_t *ctext, size_t clen,
                               uint8_t *shared_secret, size_t slen,
                               const uint8_t *entropy, size_t elen,
                               const ML_KEM_KEY *key)
{
    (void)ctext;
    (void)clen;
    (void)shared_secret;
    (void)slen;
    (void)entropy;
    (void)elen;
    (void)key;
    return 0;
}

int ossl_oqs_ml_kem_decap(uint8_t *shared_secret, size_t slen,
                          const uint8_t *ctext, size_t clen,
                          const ML_KEM_KEY *key)
{
    (void)shared_secret;
    (void)slen;
    (void)ctext;
    (void)clen;
    (void)key;
    return 0;
}

#endif
