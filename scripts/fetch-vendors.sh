#!/usr/bin/env bash
# 兜底拉取第三方依赖（vendor），按锁定提交检出。可重复执行（幂等）。
# 用法：bash scripts/fetch-vendors.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# path|url|sha|branch（branch 留空表示克隆默认分支）
vendors=(
  "brotli|https://github.com/google/brotli.git|fbadc67bfce560b92e922f5645cc95bbffe38420|"
  "cloudflare-quiche|https://github.com/cloudflare/quiche|7ab6a55cfe471267d61e4d28ba43d41defcd87e0|"
  "crypto-auditing|https://github.com/latchset/crypto-auditing.git|e9004d563608b44bff8052cba0f7c76b5175570a|"
  "fuzz/corpora|https://github.com/openssl/fuzz-corpora|9f780c2b4b8e96cdcf17792f3d6ade354cccb04a|main"
  "gost-engine|https://github.com/gost-engine/engine|74b1f4fddbc2d6de969815b1992ddc1ae7c643fe|"
  "krb5|https://github.com/krb5/krb5|f5bee90a501da6c351b3db46c1ae837b033a714c|"
  "liboqs|https://github.com/open-quantum-safe/liboqs.git|98e0db3c28d5246076fca81e8753457c765c70d5|"
  "nasm|https://github.com/netwide-assembler/nasm.git|cd37b81b320ead83ca5a6bbce5da0a6456663bc6|"
  "oqs-provider|https://github.com/open-quantum-safe/oqs-provider.git|c5fb439e4ffd947f24c139232fb04fd71fe3c29e|"
  "perl5|https://github.com/Perl/perl5.git|cb9dc93c25ce2b6636d5d9194a1339439e39c535|"
  "pkcs11-provider|https://github.com/latchset/pkcs11-provider.git|b55b94344af87a058fd84d6e15390760a5585b1d|"
  "pyca-cryptography|https://github.com/pyca/cryptography.git|e83bbe58e373536636baaa7c33a64a6e8f04c953|"
  "python-ecdsa|https://github.com/tlsfuzzer/python-ecdsa|4096fa01715929e08b97e73f3173aee9d57f2a3f|"
  "tlsfuzzer|https://github.com/tlsfuzzer/tlsfuzzer|61f45d9701294fd87ef92d2a7e3dfb076653a562|"
  "tlslite-ng|https://github.com/tlsfuzzer/tlslite-ng|77ef321dde1a9e6bcf94d73c80f8789a770d8031|"
  "wycheproof|https://github.com/google/wycheproof|3fa63dd0344abb611f1fb1d77e119938603ea230|"
  "zlib|https://github.com/madler/zlib.git|617e19a81f38c15ff04de9f8682f42ad8a8ffd1|"
  "zstd|https://github.com/meta/zstd.git|439044eeb3394184e36bba7a6b60498c3bc7f9dc|"
  "math/bandicoot-code|https://gitlab.com/bandicoot-lib/bandicoot-code.git|0017b5a9796e7317bef1e55bbd4550aeed4c8825|unstable"
  "math/carma|https://github.com/RUrlus/carma.git|507bdf7dc68955d22cbfa3789d386c7d5d8d6b23|stable"
  "math/ensmallen|https://github.com/mlpack/ensmallen.git|fb3c58303de38bf7d0aaacf31bdbe8d3ce5267ff|master"
  "math/mlpack|https://github.com/mlpack/mlpack.git|c032dba143b76468e7551b8810a0f6bf31fc35bb|master"
  "math/OpenBLAS|https://github.com/OpenMathLib/OpenBLAS.git|c93822ca2187f40ad7daa6a3e64c491ff22d9e50|develop"
  "security/liboqs|https://github.com/open-quantum-safe/liboqs.git|3ad27a398f00c7066585aca4c5d2f210991f119b|main"
  "security/mbedtls|https://github.com/Mbed-TLS/mbedtls.git|ae4c2b2532fee699f4b2d24011b87fc275e5f2de|development"
  "security/openssl|https://github.com/openssl/openssl.git|2c112b259312115ff6a880cf6a3cf47acc7f8b8d|master"
  "security/wolfssl|https://gitee.com/wellstudy0806/wolfssl.git|b6c5c1e084aff5625eee9ae36f66dd88299404be|master"
)

for entry in "${vendors[@]}"; do
  IFS='|' read -r path url sha branch <<<"$entry"
  target="$root/$path"
  echo "==> $path"
  if [ -d "$target/.git" ]; then
    git -C "$target" fetch --tags --prune origin || { echo "  fetch 失败: $path"; continue; }
  else
    [ -e "$target" ] && rm -rf "$target"
    if [ -n "$branch" ]; then git clone --branch "$branch" "$url" "$target"; else git clone "$url" "$target"; fi
    [ $? -eq 0 ] || { echo "  clone 失败: $path ($url)"; continue; }
  fi
  git -C "$target" checkout "$sha" || echo "  检出锁定提交失败: $path $sha"
done

echo
echo "完成。如某依赖因远端失效无法拉取，见 VENDORS.md 风险说明。"
