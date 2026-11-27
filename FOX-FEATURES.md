# OpenSSL · 后量子（ML-KEM）加速与构建加固分支（Foxxo）

> 基于官方 OpenSSL 源码的魔改分支。自研内容集中在 **可选 liboqs ML-KEM 加速后端** 与一套 **Windows/跨平台 CMake 构建体系**；保持原生实现为兜底，随机源始终来自 OpenSSL 自身，liboqs 不进入 FIPS 边界。

## 一、基线与状态

- 上游远端：`https://github.com/openssl/openssl`（`origin`）。
- 本地为未提交的工作区改动：`git status` 显示已修改文件、删除的 `cmake/OsslProbe.cmake`，以及未跟踪的 `build-verify/`、`math/`、`security/`、`cmake/OsslPerlBuild.cmake`。
- 改动规模：`git diff --stat` 约 26 个跟踪文件，`+905 / -1113`。

## 二、自研核心：OQS ML-KEM 加速后端（`crypto/oqs_accel/`）

头文件 `include/crypto/oqs_accel.h` 定义可选 liboqs 后端接口：

- `ossl_oqs_ml_kem_genkey` / `ossl_oqs_ml_kem_encap_seed` / `ossl_oqs_ml_kem_decap`。
- 启用条件：每个变体与操作都要先通过**确定性互操作检查**与**本地时序对比**，通过后才走 liboqs；否则函数返回 `0`，调用方回退到原生实现。
- 随机源：随机输入始终来自 OpenSSL，即使是“仅种子导入”的密钥场景也不例外。
- FIPS 边界：FIPS provider 构建中只编入桩（stub），把 liboqs 留在 FIPS 边界之外。
- 运行时开关：环境变量 `OPENSSL_OQS_ACCEL=0` 或 `off` 可关闭该后端。

配套改动：

- `crypto/ml_kem/ml_kem.c`、`crypto/ml_kem/ml_kem_local.h`：ML-KEM 原生路径与后端门控衔接。
- `crypto/oqs_accel/oqs_accel.c`（约 657 行重写）、`crypto/oqs_accel/build.info`：后端实现、架构探测与构建信息。
- 近期提交要点：oqs_accel 按自身竞态门控密钥生成、修正 liboqs 架构探测；桩变体编入 FIPS provider。

## 三、自研 CMake 构建体系

重写/新增 `cmake/Ossl*.cmake` 模块，替代旧的探测逻辑：

| 模块 | 职责 |
|---|---|
| `OsslOpenSSL.cmake` | OpenSSL 主构建编排 |
| `OsslBuild.cmake` | 编译目标与构件组织 |
| `OsslConfigure.cmake` | configure 阶段参数注入 |
| `OsslDeps.cmake` | 依赖库解析 |
| `OsslFetchNasm.cmake` | NASM 获取/探测 |
| `OsslInstall.cmake` | 安装规则（含 FIPS module 叠加到 `install_sw`） |
| `OsslPlatform.cmake` | 平台/编译器判定（MSVC 等） |
| `OsslTools.cmake` | 工具链封装 |
| `OsslPerlBuild.cmake`（新增） | Perl 构建链路 |
| ~~`OsslProbe.cmake`~~（已删除） | 旧探针，被上述模块取代 |

构建脚本与文档：`build-cmake.ps1`（Windows）、`build-cmake.sh`（POSIX）、`BUILD-CMAKE.md`、根 `CMakeLists.txt`、`Configure`。

构建加固要点（来自近期提交）：

- configure 时清扫残留的 `ossl-run-*.cmd` 包装脚本；
- 错误签名只匹配错误行，覆盖 RC5 / IDEA / SEED；
- 阻止残留 staged headers 与探针重跑循环破坏重建；
- 活动配置前向注入嵌套的 ossl-openssl 构建；
- MSVC 默认保留 `/nologo /debug` ldflags，注入 `/LIBPATH`；MSVC 的 `--with-*-lib` 必须带 `.lib` 后缀；依赖库名按 `.lib` 传入。

## 四、内置第三方组件（vendor / submodule，非自研）

`liboqs`、`oqs-provider`、`brotli`、`cloudflare-quiche`（QUIC）、`gost-engine`、`pkcs11-provider`、`krb5`、`python-ecdsa`、`pyca-cryptography`、`zlib`、`zstd`、`nasm`、`crypto-auditing`、`perl5`、`tlsfuzzer`、`tlslite-ng`、`wycheproof` 等，以及未跟踪的 `math/`、`security/` 参考依赖目录。

## 五、校验

- `build-verify/`：构建验证目录（安装/封装校验产物）。
- 原生测试与 fuzz 套件沿用上游 `test/`、`fuzz/`、`tlsfuzzer`、`tlslite-ng`、`wycheproof`。

## 六、安全说明

- OQS 后端是**可选加速层**，互操作或时序不达标即回退原生，不阻塞主流程。
- liboqs 被隔离在 FIPS provider 之外；后量子算法的互操作性以实测检查为准。
- 本分支为实验性源码魔改，vendor 子模块未逐一审计，生产使用前需独立验证。
