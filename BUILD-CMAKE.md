# 统一 CMake 构建

该入口是 OpenSSL 的 CMake 超级构建：工具与依赖由 CMake 构建，OpenSSL 本身仍使用上游 `Configure` 生成平台 makefile。CMake 负责依赖顺序、配置指纹、增量编译、安装和可选测试，不另写一套算法或源文件清单。

## 获取源码

```bash
git submodule update --init --recursive
```

默认链路为 `perl/nasm → zlib + zstd + brotli + liboqs → OpenSSL`。liboqs 的 `OQS_USE_OPENSSL=OFF`，不会反向依赖宿主 OpenSSL 或形成构建环。

## Windows / MSVC

```powershell
.\build-cmake.ps1 -Config Release
```

等价命令：

```powershell
cmake -S . -B build -G "Visual Studio 18 2026" -A x64
cmake --build build --config Release --target openssl-all
```

多配置生成器按配置隔离：

```text
build/deps/Release/          zlib、zstd、brotli、liboqs
build/openssl/Release/       OpenSSL 配置、对象和构建日志
build/stage/Release/         最终 OpenSSL 安装
build/stage/tools/           跨配置共用的 perl/nasm
```

`-Reconfigure` 会删除 `build` 后重建。源码移动到其他目录后应使用它，不能沿用包含旧绝对路径的缓存。

## Linux / macOS

```bash
./build-cmake.sh Release
```

或：

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target openssl-all --parallel 8
```

单配置生成器使用 `build/deps`、`build/openssl/Release` 和 `build/stage`。

## 分阶段与测试

```bash
cmake --build build --target all-tools
cmake --build build --target all-deps
cmake --build build --target ossl-openssl
cmake --build build --target openssl-all
```

测试默认不构建。显式启用后：

```bash
cmake -S . -B build -DOSSL_ENABLE_TESTS=ON
cmake --build build --target ossl-check --config Release
```

测试日志为 `build/openssl/Release/openssl-test.log`。构建失败会保留日志并直接失败，不再通过删除功能反复重试来掩盖错误。

## 主要选项

| 选项 | 默认 | 说明 |
| --- | --- | --- |
| `OSSL_TOOL_MODE` | `AUTO` | `AUTO` 优先已有工具；`BUILD` 编译 bundled 工具；`SYSTEM` 仅使用系统工具 |
| `OSSL_WITH_ZLIB` / `OSSL_WITH_ZSTD` / `OSSL_WITH_BROTLI` / `OSSL_WITH_OQS` | `ON` | 构建对应静态依赖 |
| `OSSL_BUILD_SHARED` | `ON` | 同时构建动态库；`OFF` 传 `no-shared`，静态库始终由上游构建 |
| `OSSL_ENABLE_TESTS` / `OSSL_ENABLE_DOCS` | `OFF` | 测试与文档开关 |
| `OSSL_ENABLE_ASM` | `ON` | `OFF` 跳过 nasm 并传 `no-asm` |
| `OSSL_CONFIGURE_TARGET` | 自动 | 手动指定 `VC-WIN64A`、`linux-x86_64` 等 |
| `OSSL_FEATURES` | CMP/FIPS/RFC3779/thread-pool/QUIC | 显式、分号分隔的 OpenSSL 功能参数 |
| `OSSL_OPENSSL_ARGS` | 空 | 追加给 `Configure` 的其他参数 |
| `OSSL_OQS_PROFILE` | `fast` | `fast` 仅编译 ML-KEM-512/768/1024；`full` 编译 liboqs 默认完整算法集 |
| `OSSL_WITH_OQS_ACCEL` | `ON` | OpenSSL ML-KEM 调用 liboqs 的可选后端 |
| `OSSL_JOBS` | `8` | 依赖构建并行数 |
| `OSSL_STATIC_MSVC_RUNTIME` | `OFF` | 依赖使用静态 MSVC 运行库 |

默认不会自动开启 MD2、RC5、IDEA、SEED、Whirlpool、弱 SSL 密码、Legacy provider 或 TLS 压缩。确有兼容需求时须显式加入 `OSSL_FEATURES` 或 `OSSL_OPENSSL_ARGS`。

## liboqs 加速边界

- 每个 ML-KEM 变体分别做确定性自检，相同种子必须产生一致的公钥、私钥、密文和共享秘密。
- keygen、encap、decap 分别测速；某一项失败或较慢只禁用该项，不影响其他变体。
- 随机输入来自 OpenSSL 的 `RAND_*_ex`，种子导入语义和调用方 libctx 不变。
- 任一后端调用失败均回退原生实现；部分输出会清理，错误栈不会被可选后端污染。
- FIPS provider 编译原生 stub，liboqs 不进入 FIPS 边界。
- 设置环境变量 `OPENSSL_OQS_ACCEL=0` 或 `off` 可禁用后端。

## 工具与供应链

Windows 的 nasm git 检出缺少 autoconf 生成文件时，会使用官方二进制压缩包。下载必须匹配 `OSSL_NASM_URL_HASH` 中的 SHA-256；已存在的 staged 工具不会重复下载。`OSSL_NASM_URL` 与哈希必须成对更新。

MSVC 环境从实际 C 编译器路径定位 `vcvarsall.bat`，找不到时再使用 vswhere。构建路径仍建议不要包含空格，以避开上游 Perl/nmake 的已知命令行限制。

## 模块

```text
cmake/OsslPlatform.cmake   平台、隔离前缀、MSVC 环境
cmake/OsslTools.cmake      perl/nasm
cmake/OsslDeps.cmake       zlib/zstd/brotli/liboqs
cmake/OsslOpenSSL.cmake    构建图、安装和测试目标
cmake/OsslConfigure.cmake  配置指纹与 Configure
cmake/OsslBuild.cmake      确定性 make/测试执行
cmake/OsslInstall.cmake    install_sw 与可选 FIPS 模块
cmake/OsslPerlBuild.cmake   Windows perl 干净归档构建
cmake/OsslStagePerl.cmake  Windows perl 暂存
cmake/OsslFetchNasm.cmake  带哈希验证的 nasm 兜底
```
