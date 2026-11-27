/*
 * Copyright 2026 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License 2.0 (the "License").  You may not use
 * this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/licence.html
 */

#ifndef OPENSSL_HEADER_OQS_ACCEL_H
# define OPENSSL_HEADER_OQS_ACCEL_H
# pragma once

# include <openssl/e_os2.h>
# include "crypto/ml_kem.h"

/*
 * Optional liboqs ML-KEM backend. Each variant and operation is enabled only
 * after deterministic interoperability checks and a local timing comparison.
 * Random inputs always originate from OpenSSL, including seed-only key import.
 * Every function returns 0 when the caller must use the native implementation.
 * FIPS provider builds contain stubs, keeping liboqs outside the FIPS boundary.
 *
 * Set OPENSSL_OQS_ACCEL to "0" or "off" to disable the backend at runtime.
 */
int ossl_oqs_ml_kem_genkey(uint8_t *pubenc, size_t publen, ML_KEM_KEY *key);
int ossl_oqs_ml_kem_encap_seed(uint8_t *ctext, size_t clen,
                               uint8_t *shared_secret, size_t slen,
                               const uint8_t *entropy, size_t elen,
                               const ML_KEM_KEY *key);
int ossl_oqs_ml_kem_decap(uint8_t *shared_secret, size_t slen,
                          const uint8_t *ctext, size_t clen,
                          const ML_KEM_KEY *key);

#endif
