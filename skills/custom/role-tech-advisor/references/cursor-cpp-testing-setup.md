# Cursor IDE C++ 测试环境配置

> 归档日期：2026-05-29
> 问题场景：Cursor 远程 SSH 连接 Linux 服务器，C++ 项目无法使用测试面板

## 问题根因（三层叠加）

### 第一层：微软封锁 C/C++ 扩展
- **时间线**：2025 年 4 月起，微软主动限制 `ms-vscode.cpptools`（C/C++ Extension Pack）在 VS Code fork（含 Cursor）上的使用
- **表现**：C/C++ DevTools 扩展在 Cursor 扩展商店搜不到；即使手动装 VSIX，远程环境下兼容性检查也会拒掉
- **影响范围**：cppdbg/cppvsdbg 调试器、C/C++ DevTools 测试功能均不可用
- **来源**：[The Register](https://www.theregister.com/software/2025/04/24/microsoft-subtracts-c/c-extension-from-vs-code-forks/)、[DevClass](https://www.devclass.com/development/2025/04/08/vs-code-extension-marketplace-wars-cursor-users-hit-roadblocks/)
- **Cursor 工程师原话**（Ravi Rahman）：*"cppdbg and cppvsdbg are not supported in Cursor."*

### 第二层：Anysphere 替代扩展只管 IntelliSense
- Cursor 自家的 `anysphere.cpptools`（Anysphere C/C++）替代微软扩展，基于 **Clangd**
- **有能力**：代码补全、跳转定义、语法高亮、IntelliSense
- **没能力**：测试发现/运行、cppdbg 调试器
- **前置条件**：需要项目目录下有 `compile_commands.json`（CMake 生成：`cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ...`）
- **已知坑**：部分远程 Linux 环境下，`anysphere.cpptools` 安装后可能报告 `bin/cpptools is missing` → 需确认远程环境已安装 clangd（`apt install clangd` 或 `dnf install clang-tools-extra`）

### 第三层：VS Code 1.105+ 测试面板显示逻辑
- VSCode 1.105 起，Testing 活动栏图标**仅在安装至少一个测试扩展后显示**
- Cursor 已同步此行为变更
- 2023 年已有用户反馈「Where is the Testing panel」，当时解决方案是安装 Playwright 等测试扩展
- **来源**：[Cursor Forum #466](https://forum.cursor.com/t/where-is-the-testing-panel/466)、[#144150](https://forum.cursor.com/t/test-explorer-icon-does-not-display-on-side-bar-after-update/144150)

## 解决方案：第三方 C++ 测试适配器

核心思路：绕过微软 cpptools，用独立扩展直接对接 GoogleTest / Catch2 / doctest 编译出的测试可执行文件。

### 首选：TestMate C++

- **扩展 ID**：`matepek.vscode-catch2-test-adapter`
- **安装量**：61 万+
- **支持框架**：GoogleTest、Catch2、doctest、Google Benchmark
- **远程 SSH**：支持（需在远程环境也安装）
- **不依赖**：微软 cpptools，独立运行测试可执行文件

```json
// .vscode/settings.json — 最小配置
{
  "testMate.cpp.test.executables": "build/**/*{test,Test}*"
}
```

**核心特性**：
- 测试流式输出（stdout 实时可见）
- Catch2 Section / doctest SubCase 支持
- 并行执行（`testMate.cpp.test.parallelExecutionLimit`）
- 支持 lldb / cppdbg / vscode-lldb 等多种调试器
- 测试发现自动缓存（`testMate.cpp.discovery.testListCaching`）

**远程环境部署步骤**：
1. 在 Cursor 本地装 TestMate C++
2. 通过 Remote SSH 连接后，打开 Extensions 面板
3. 找到 TestMate C++ → 点 "Install in SSH: xxx.xxx.xxx.xxx"
4. 确认远程环境 `.vscode/settings.json` 中 `testMate.cpp.test.executables` 路径正确
5. 重启 Cursor / 重连远程 → Testing 图标应出现

### 备选

| 扩展 | ID | 适用场景 |
|------|-----|---------|
| GoogleTest Adapter | `davidschuldenfrei.gtest-adapter` | 纯 GoogleTest 项目 |
| C/C++ Runner | `franneck94.c-cpp-runner` | Catch2 + GoogleTest 双框架 |

## ⚠️ CTest 裸二进制陷阱（最易被忽略的根因）

**症状**：TestMate 已安装、glob 已配好、测试二进制也存在，但 Testing 面板始终为空。

**根因**：TestMate 通过调用 `./test_binary --gtest_list_tests`（或 `--list-tests` / `--list-test-cases`）来发现测试。如果二进制是**普通 C++ 程序 + CTest `add_test()` 注册**（即 `main()` 直接执行逻辑、没有链接 GoogleTest/Catch2/doctest），它不认识这些框架参数 → 崩溃退出 → TestMate 将其标记为「损坏」，跳过。

**识别方法**：
```bash
# 如果这条命令崩溃而非输出测试列表，就是这个问题
./build/measurement_sdk_tests --gtest_list_tests
```

**修复**：将测试改写为 GoogleTest/Catch2/doctest 框架格式（见下方「CMake + GoogleTest 移植模板」）。

---

## CMake + GoogleTest 移植模板（FetchContent + add_subdirectory 分离）

推荐结构（见上方「测试 CMake 与 SDK 构建分离」），此节仅保留核心 CMake 片段供快速参考。

### tests/CMakeLists.txt 最小模板

```cmake
include(FetchContent)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(measurement_sdk_tests sdk_smoke_test.cpp)
target_link_libraries(measurement_sdk_tests PRIVATE
    measurement GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(measurement_sdk_tests
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR})
```

> **根 CMakeLists.txt 只需一行**：`add_subdirectory(tests)`，放在 `if(MEASUREMENT_BUILD_TESTS)` 块内。根文件不含 `FetchContent`、不含任何 GTest 引用——发布时 `-DMEASUREMENT_BUILD_TESTS=OFF` 零污染。

### 测试代码改写模式（Plain main → GoogleTest Fixture）

```cpp
// ⚠️ 头文件顺序有讲究（见下一节），Torch 依赖头文件必须最前
#include "main.hpp"       // ← 先包含项目头文件（含 Torch 传递依赖）
#include <gtest/gtest.h>  // ← 再包含 gtest

// 用 Fixture 管理共享的初始化数据（替代原 main() 里的准备工作）
class SmokeTest : public ::testing::Test {
protected:
    void SetUp() override {
        // 加载数据、初始化资源等
        chunks_ = LoadData(/*...*/);
        ASSERT_GE(chunks_.size(), 2);
    }
    std::vector<std::string> chunks_;
};

TEST_F(SmokeTest, CaseOne) { /* ... */ }
TEST_F(SmokeTest, CaseTwo) { /* ... */ }
```

---

## LibTorch + GoogleTest `c10::optional` / `std::optional` 冲突

**症状**：编译测试目标时报大量 `reference to 'optional' is ambiguous`（`std::optional` vs `c10::optional`）。

**根因**：`<gtest/gtest.h>` 在内部 `#include <optional>`（C++17），而 LibTorch 的 `ATen/ATen.h` 等头文件在全局作用域使用了 `c10::optional`。两套 `optional` 同时可见时，裸名 `optional` 出现歧义。

**修复**：**将项目头文件（含 Torch 传递依赖）放在 gtest 之前**：

```cpp
// ✅ 正确顺序
#include "main.hpp"       // 含 Torch 传递依赖 → c10::optional 先解析
#include <gtest/gtest.h>  // 后引入 std::optional，不会造成歧义

// ❌ 错误顺序
#include <gtest/gtest.h>  // 先引入 std::optional
#include "main.hpp"       // Torch 的 c10::optional 后引入 → 歧义
```

原理：`main.hpp`（及其传递 include）中的 `using namespace c10` 或显式 `c10::optional` 用法在解析时，`std::optional` 还没进入作用域，编译器不会混淆。反之则两套同时可见。

---

## 测试 CMake 与 SDK 构建分离（add_subdirectory 模式）

**最佳实践**：测试配置全部放在 `tests/CMakeLists.txt`，根 `CMakeLists.txt` 只做 SDK 库编译+安装：

```cmake
# === 根 CMakeLists.txt（纯净，零测试依赖）===
# 不含 include(FetchContent)，不含 GTest 引用

option(MEASUREMENT_BUILD_TESTS "Build SDK test project" OFF)

# ... SDK library target & install rules ...

if(MEASUREMENT_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)  # ← 仅此一行
endif()
```

```cmake
# === tests/CMakeLists.txt（全部测试逻辑）===
include(FetchContent)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(measurement_sdk_tests sdk_smoke_test.cpp)
target_link_libraries(measurement_sdk_tests PRIVATE
    measurement           # ← 父作用域的 target，自动可见
    GTest::gtest_main)
target_compile_definitions(measurement_sdk_tests PRIVATE
    SDK_TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/data")
    # ↑ CMAKE_CURRENT_SOURCE_DIR 现在是 tests/

include(GoogleTest)
gtest_discover_tests(measurement_sdk_tests
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR})
    # ↑ 必须是 PROJECT_BINARY_DIR 而非 CMAKE_CURRENT_BINARY_DIR
    #   因为 add_subdirectory 后二进制在 build/tests/ 下
    #   但 study/ 模型资产在 build/ 根目录
```

**发布编译**：`-DMEASUREMENT_BUILD_TESTS=OFF` → 不拉 GTest、不编译测试、只出 `libmeasurement.so`。

**注意**：`add_subdirectory` 后测试二进制路径变为 `build/tests/measurement_sdk_tests`（而非 `build/measurement_sdk_tests`），TestMate 的 `executables` 必须相应调整（见下方配置）。

---

## Cursor Testing 面板配置（推荐方案）

### 方案：项目级 `.vscode/settings.json`（随 Git 分发）

**优于机器级 `~/.cursor-server/data/Machine/settings.json`**，因为：
- 任何人 clone 项目后自动生效，无需手动配
- 用 **通配符 glob** 覆盖多种构建目录名，不绑定特定目录

```json
{
    "testMate.cpp.test.executables": "{cmake-build-debug,cmake-build-release,build,out}/**/measurement_sdk_tests",
    "testMate.cpp.discovery.loadOnStartup": true,
    "testing.automaticallyOpenPeekView": "failureAnywhere"
}
```

| 配置项 | 作用 |
|--------|------|
| `executables` | **通配符 glob**。`{a,b,c,d}/**/xxx` 覆盖四种常见构建目录名（`cmake-build-debug`、`cmake-build-release`、`build`、`out`）。**必须确认 `.vscode/` 不在 `.gitignore` 中**（见下方陷阱）。 |
| `discovery.loadOnStartup` | 启动即发现，无需手动点刷新 |
| 不设 `workingDirectory` | TestMate 默认以二进制所在目录为 CWD。如需指定（如模型文件在项目根），用 `"testMate.cpp.test.workingDirectory": "${workspaceFolder}"` |

> **关键理念**：不写死 `cmake-build-debug` 这种编译产物目录名。用户第一次 clone 后还没有这个目录，Testing 面板为空是**正常状态**——编译后 glob 自动发现。

### ⚠️ `.vscode/` 被 `.gitignore` 拦截的陷阱

许多 C++ 项目的 `.gitignore` 包含 `.vscode/` 行（IDE 模板默认如此），导致 `settings.json` 无法提交到仓库。**必须从 `.gitignore` 中移除 `.vscode/`**，否则别人 clone 拿不到 Testing 配置。

```bash
# 检查是否被忽略
git check-ignore .vscode/settings.json

# 如果在 .gitignore 中，删除该行
# 然后强制加入
git add -f .vscode/settings.json
```

---

### 故障排查流程

```bash
# 1. 确认测试二进制存在且可执行
file build/measurement_sdk_tests

# 2. 确认它能响应 GoogleTest 发现命令（不崩溃！）
cd build && ./tests/measurement_sdk_tests --gtest_list_tests
# 期望输出：
#   SdkSmokeTest.
#     GetChunkReport_ProducesOutput
#     GetReport_ProducesOutput

# 3. 确认能在正确目录下运行
cd build && ./tests/measurement_sdk_tests
# 期望：所有测试 PASSED

# 4. 在 Cursor 中手动触发发现
# Cmd+Shift+P → Test: Refresh Tests
```

---

## 项目文档与构建脚本规范

针对此类 C++ SDK 项目，`build.sh` 和 `README.md` 应包含以下信息：

### build.sh 模式

```bash
#!/usr/bin/env bash
set -euo pipefail

# Release (default):
#   bash build.sh
#   → cmake -DMEASUREMENT_BUILD_TESTS=OFF → libmeasurement.so + install
#
# Debug + Tests:
#   BUILD_DIR=cmake-build-debug bash -c "
#     cmake -S . -B cmake-build-debug \
#       -DCMAKE_BUILD_TYPE=Debug \
#       -DMEASUREMENT_BUILD_TESTS=ON &&
#     cmake --build cmake-build-debug -j\$(nproc)"

BUILD_DIR="${BUILD_DIR:-cmake-build-release}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$PWD/dist}"

rm -rf "${BUILD_DIR}"

cmake -S . -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DMEASUREMENT_BUILD_TESTS=OFF

cmake --build "${BUILD_DIR}" -j"$(nproc)"
cmake --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"
```

### README.md 应覆盖的章节

- **项目结构**：根 CMakeLists.txt（SDK 库）vs tests/CMakeLists.txt（测试）职责说明
- **发布编译**：一句话命令 + 产物列表
- **测试编译**：命令 + FetchContent 首次需网络的提醒
- **运行测试**：命令行三种方式（`./binary`、`ctest`、`--gtest_list_tests`）+ Cursor TestMate 配置
- **IDE Testing 面板**：settings.json 配置示例

## 常见编译陷阱

### `libmeasurement.so: file too short`（并行构建竞态）

**症状**：`cmake --build . -j$(nproc)` 时，链接测试二进制报 `libmeasurement.so: file too short`。

**根因**：并行编译时 SDK 共享库还没写完，测试目标就开始链接它。

**修复**：顺序构建依赖链：
```bash
cmake --build . --target measurement -j$(nproc)
cmake --build . --target measurement_sdk_tests
```

或确保 CMake 目标依赖正确（`target_link_libraries(measurement_sdk_tests PRIVATE measurement)` 应已处理此问题，但部分构建系统实现有 bug）。

### `cmake/measurementConfig.cmake.in` 丢失

**症状**：CMake 配置阶段报 `File cmake/measurementConfig.cmake.in does not exist`。

**根因**：该文件是 CMake 包配置模板（`configure_package_config_file` 使用），用于 `cmake --install` 后下游项目 `find_package(measurement)`。本地被误删时构建全部中断，与测试改动无关。

**修复**：`git restore cmake/measurementConfig.cmake.in`

> **此文件必须进 Git**——它是构建系统源码的一部分，不应当被 `.gitignore` 排除。

### 模型资产（`study/`）的相对路径硬编码

**症状**：编译好的 SDK 动态库在部署后无法加载模型文件。

**根因**：SDK 代码中使用硬编码相对路径加载模型（`torch::jit::load("./study/xxx.pt")`），但 `cmake --install` 把模型安装到 `dist/share/measurement/study/`，运行时进程的 CWD 下没有 `study/` 目录。

**部署约定（须写入 README）**：
```bash
cp -r dist/share/measurement/study ./study
# 或软链接（开发环境）
ln -s dist/share/measurement/study ./study
```

> 路径硬编码在 `bpServer.cpp`、`bpServerNew.cpp`、`riskServer.cpp` 中，**不可通过环境变量修改**。此约束必须在 README 中明确说明。

---

## 远程 SSH 安装微软扩展的老方案（已过时，供参考）
