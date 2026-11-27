# 兜底拉取第三方依赖（vendor），按锁定提交检出。可重复执行（幂等）。
# 用法：powershell -ExecutionPolicy Bypass -File scripts/fetch-vendors.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$vendors = @(
    # 上游登记的 submodule（branch 留空：克隆默认分支后直接检出锁定提交）
    @{ path = 'brotli';            url = 'https://github.com/google/brotli.git';                          sha = 'fbadc67bfce560b92e922f5645cc95bbffe38420'; branch = '' },
    @{ path = 'cloudflare-quiche'; url = 'https://github.com/cloudflare/quiche';                        sha = '7ab6a55cfe471267d61e4d28ba43d41defcd87e0'; branch = '' },
    @{ path = 'crypto-auditing';    url = 'https://github.com/latchset/crypto-auditing.git';               sha = 'e9004d563608b44bff8052cba0f7c76b5175570a'; branch = '' },
    @{ path = 'fuzz/corpora';      url = 'https://github.com/openssl/fuzz-corpora';                       sha = '9f780c2b4b8e96cdcf17792f3d6ade354cccb04a'; branch = 'main' },
    @{ path = 'gost-engine';       url = 'https://github.com/gost-engine/engine';                        sha = '74b1f4fddbc2d6de969815b1992ddc1ae7c643fe'; branch = '' },
    @{ path = 'krb5';              url = 'https://github.com/krb5/krb5';                                   sha = 'f5bee90a501da6c351b3db46c1ae837b033a714c'; branch = '' },
    @{ path = 'liboqs';             url = 'https://github.com/open-quantum-safe/liboqs.git';              sha = '98e0db3c28d5246076fca81e8753457c765c70d5'; branch = '' },
    @{ path = 'nasm';               url = 'https://github.com/netwide-assembler/nasm.git';                sha = 'cd37b81b320ead83ca5a6bbce5da0a6456663bc6'; branch = '' },
    @{ path = 'oqs-provider';       url = 'https://github.com/open-quantum-safe/oqs-provider.git';         sha = 'c5fb439e4ffd947f24c139232fb04fd71fe3c29e'; branch = '' },
    @{ path = 'perl5';              url = 'https://github.com/Perl/perl5.git';                             sha = 'cb9dc93c25ce2b6636d5d9194a1339439e39c535'; branch = '' },
    @{ path = 'pkcs11-provider';    url = 'https://github.com/latchset/pkcs11-provider.git';              sha = 'b55b94344af87a058fd84d6e15390760a5585b1d'; branch = '' },
    @{ path = 'pyca-cryptography';  url = 'https://github.com/pyca/cryptography.git';                      sha = 'e83bbe58e373536636baaa7c33a64a6e8f04c953'; branch = '' },
    @{ path = 'python-ecdsa';      url = 'https://github.com/tlsfuzzer/python-ecdsa';                     sha = '4096fa01715929e08b97e73f3173aee9d57f2a3f'; branch = '' },
    @{ path = 'tlsfuzzer';          url = 'https://github.com/tlsfuzzer/tlsfuzzer';                      sha = '61f45d9701294fd87ef92d2a7e3dfb076653a562'; branch = '' },
    @{ path = 'tlslite-ng';          url = 'https://github.com/tlsfuzzer/tlslite-ng';                      sha = '77ef321dde1a9e6bcf94d73c80f8789a770d8031'; branch = '' },
    @{ path = 'wycheproof';          url = 'https://github.com/google/wycheproof';                       sha = '3fa63dd0344abb611f1fb1d77e119938603ea230'; branch = '' },
    @{ path = 'zlib';               url = 'https://github.com/madler/zlib.git';                         sha = '617e19a81f38c15ff04de9f8682f42ad8a8ffd1'; branch = '' },
    @{ path = 'zstd';               url = 'https://github.com/meta/zstd.git';                             sha = '439044eeb3394184e36bba7a6b60498c3bc7f9dc'; branch = '' },
    # 手动引入的安全 / 数学加速依赖
    @{ path = 'math/bandicoot-code'; url = 'https://gitlab.com/bandicoot-lib/bandicoot-code.git';        sha = '0017b5a9796e7317bef1e55bbd4550aeed4c8825'; branch = 'unstable' },
    @{ path = 'math/carma';          url = 'https://github.com/RUrlus/carma.git';                         sha = '507bdf7dc68955d22cbfa3789d386c7d5d8d6b23'; branch = 'stable' },
    @{ path = 'math/ensmallen';      url = 'https://github.com/mlpack/ensmallen.git';                      sha = 'fb3c58303de38bf7d0aaacf31bdbe8d3ce5267ff'; branch = 'master' },
    @{ path = 'math/mlpack';          url = 'https://github.com/mlpack/mlpack.git';                        sha = 'c032dba143b76468e7551b8810a0f6bf31fc35bb'; branch = 'master' },
    @{ path = 'math/OpenBLAS';        url = 'https://github.com/OpenMathLib/OpenBLAS.git';                  sha = 'c93822ca2187f40ad7daa6a3e64c491ff22d9e50'; branch = 'develop' },
    @{ path = 'security/liboqs';       url = 'https://github.com/open-quantum-safe/liboqs.git';             sha = '3ad27a398f00c7066585aca4c5d2f210991f119b'; branch = 'main' },
    @{ path = 'security/mbedtls';      url = 'https://github.com/Mbed-TLS/mbedtls.git';                    sha = 'ae4c2b2532fee699f4b2d24011b87fc275e5f2de'; branch = 'development' },
    @{ path = 'security/openssl';     url = 'https://github.com/openssl/openssl.git';                      sha = '2c112b259312115ff6a880cf6a3cf47acc7f8b8d'; branch = 'master' },
    @{ path = 'security/wolfssl';     url = 'https://gitee.com/wellstudy0806/wolfssl.git';                sha = 'b6c5c1e084aff5625eee9ae36f66dd88299404be'; branch = 'master' }
)

foreach ($v in $vendors) {
    $target = Join-Path $root $v.path
    Write-Host "==> $($v.path)" -ForegroundColor Cyan
    if (Test-Path (Join-Path $target '.git')) {
        git -C $target fetch --tags --prune origin
        if ($LASTEXITCODE -ne 0) { Write-Warning "fetch 失败: $($v.path)"; continue }
    } else {
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        if ($v.branch) { git clone --branch $v.branch $v.url $target } else { git clone $v.url $target }
        if ($LASTEXITCODE -ne 0) { Write-Warning "clone 失败: $($v.path) ($($v.url))"; continue }
    }
    git -C $target checkout $v.sha
    if ($LASTEXITCODE -ne 0) { Write-Warning "检出锁定提交失败: $($v.path) $($v.sha)" }
}

Write-Host "`n完成。如某依赖因远端失效无法拉取，见 VENDORS.md 风险说明。" -ForegroundColor Green
