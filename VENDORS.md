# 第三方依赖清单（Vendors）

本仓库主仓**不打包**各第三方源码树；它们以 git submodule 形式锁定到下列提交。
主仓只保存 submodule 指针（commit sha），需要源码时按任一方式找回。

## 找回方式

### 方式一：原生 submodule（推荐）

```bash
git clone https://github.com/LoveFoxxo/openssl-oqs-accel.git
cd openssl-oqs-accel
git submodule update --init --recursive
```

该命令会按 `.gitmodules` 中的 URL 和本仓库锁定的提交（下表 sha）检出对应版本。

### 方式二：兜底脚本（submodule 不可用或指针异常时）

Windows PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-vendors.ps1
```

Linux / macOS：

```bash
bash scripts/fetch-vendors.sh
```

脚本内置与下表一致的 URL、锁定提交和分支，逐个 clone 并 `git checkout <sha>`；已存在的目录会校验并切到锁定提交，可重复执行。

## 上游登记的 submodule（OpenSSL 原生）

| 路径 | 来源 URL | 锁定提交 |
|---|---|---|
| `brotli` | https://github.com/google/brotli.git | `fbadc67bfce560b92e922f5645cc95bbffe38420` |
| `cloudflare-quiche` | https://github.com/cloudflare/quiche | `7ab6a55cfe471267d61e4d28ba43d41defcd87e0` |
| `crypto-auditing` | https://github.com/latchset/crypto-auditing.git | `e9004d563608b44bff8052cba0f7c76b5175570a` |
| `fuzz/corpora` | https://github.com/openssl/fuzz-corpora | `9f780c2b4b8e96cdcf17792f3d6ade354cccb04a` |
| `gost-engine` | https://github.com/gost-engine/engine | `74b1f4fddbc2d6de969815b1992ddc1ae7c643fe` |
| `krb5` | https://github.com/krb5/krb5 | `f5bee90a501da6c351b3db46c1ae837b033a714c` |
| `liboqs` | https://github.com/open-quantum-safe/liboqs.git | `98e0db3c28d5246076fca81e8753457c765c70d5` |
| `nasm` | https://github.com/netwide-assembler/nasm.git | `cd37b81b320ead83ca5a6bbce5da0a6456663bc6` |
| `oqs-provider` | https://github.com/open-quantum-safe/oqs-provider.git | `c5fb439e4ffd947f24c139232fb04fd71fe3c29e` |
| `perl5` | https://github.com/Perl/perl5.git | `cb9dc93c25ce2b6636d5d9194a1339439e39c535` |
| `pkcs11-provider` | https://github.com/latchset/pkcs11-provider.git | `b55b94344af87a058fd84d6e15390760a5585b1d` |
| `pyca-cryptography` | https://github.com/pyca/cryptography.git | `e83bbe58e373536636baaa7c33a64a6e8f04c953` |
| `python-ecdsa` | https://github.com/tlsfuzzer/python-ecdsa | `4096fa01715929e08b97e73f3173aee9d57f2a3f` |
| `tlsfuzzer` | https://github.com/tlsfuzzer/tlsfuzzer | `61f45d9701294fd87ef92d2a7e3dfb076653a562` |
| `tlslite-ng` | https://github.com/tlsfuzzer/tlslite-ng | `77ef321dde1a9e6bcf94d73c80f8789a770d8031` |
| `wycheproof` | https://github.com/google/wycheproof | `3fa63dd0344abb611f1fb1d77e119938603ea230` |
| `zlib` | https://github.com/madler/zlib.git | `617e19a81f38c15ff04de9f8682f42ad8a8ffd1` |
| `zstd` | https://github.com/meta/zstd.git | `439044eeb3394184e36bba7a6b60498c3bc7f9dc` |

## 手动引入的安全 / 数学加速依赖

| 路径 | 来源 URL | 锁定提交 | 分支 | 备注 |
|---|---|---|---|---|
| `math/bandicoot-code` | https://gitlab.com/bandicoot-lib/bandicoot-code.git | `0017b5a9796e7317bef1e55bbd4550aeed4c8825` | unstable | bandicoot 线性代数依赖 |
| `math/carma` | https://github.com/RUrlus/carma.git | `507bdf7dc68955d22cbfa3789d386c7d5d8d6b23` | stable | C++ 矩阵库 |
| `math/ensmallen` | https://github.com/mlpack/ensmallen.git | `fb3c58303de38bf7d0aaacf31bdbe8d3ce5267ff` | master | 优化库 |
| `math/mlpack` | https://github.com/mlpack/mlpack.git | `c032dba143b76468e7551b8810a0f6bf31fc35bb` | master | 机器学习库 |
| `math/OpenBLAS` | https://github.com/OpenMathLib/OpenBLAS.git | `c93822ca2187f40ad7daa6a3e64c491ff22d9e50` | develop | BLAS 实现 |
| `security/liboqs` | https://github.com/open-quantum-safe/liboqs.git | `3ad27a398f00c7066585aca4c5d2f210991f119b` | main | 后量子密码库（与根 `liboqs` 是不同检出） |
| `security/mbedtls` | https://github.com/Mbed-TLS/mbedtls.git | `ae4c2b2532fee699f4b2d24011b87fc275e5f2de` | development | TLS 库 |
| `security/openssl` | https://github.com/openssl/openssl.git | `2c112b259312115ff6a880cf6a3cf47acc7f8b8d` | master | OpenSSL |
| `security/wolfssl` | https://gitee.com/wellstudy0806/wolfssl.git | `b6c5c1e084aff5625eee9ae36f66dd88299404be` | master | ⚠️ Gitee 个人 fork，来源稳定性不可控；若该远端失效，需另行归档源码 |

## 风险说明

- submodule 指针只记录**来源 URL + 锁定提交**。若上游远端被删除、改名或改为私有，`submodule update --init` 与兜底脚本都无法从该 URL 拉取，此时需要从本地备份或镜像重新归档。
- `security/wolfssl` 指向 Gitee 个人 fork，不属于官方仓库，失效风险高于其余官方/组织远端。
- 编译产物（`build/`、`build-verify/`、`*.lib/*.a/*.o/*.exe/*.dll` 等）与上游 git 历史不纳入本仓库，见 `.gitignore`。
