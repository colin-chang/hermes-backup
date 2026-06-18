---
name: cursor-cpp-setup
description: C++ 项目在 Cursor IDE 中的扩展选择、远程开发与测试面板配置。当用户遇到 Cursor 下 C++ 调试/测试/IntelliSense 问题（微软扩展被屏蔽、Testing 面板不显示、TestMate 不发现测试、LibTorch 头文件冲突）时使用。
version: 1.2.0
metadata:
  hermes:
    tags: [cursor, cpp, testing, cmake, gtest, remote-ssh]
---

# C++ 项目在 Cursor 中的配置

## 核心认知

Cursor 是 VS Code fork，但微软自 2025 年 4 月起**主动阻止**其 `ms-vscode.cpptools`（C/C++ Extension Pack）在 fork 上运行。这导致以下问题链条：

```
微软封锁 cpptools → C/C++ DevTools 不提供 → 测试扩展不工作
                 → 远程 SSH 下扩展安装失败
                 → cppdbg 调试器不可用
```

## 扩展选择矩阵

| 需求 | VS Code（原始） | Cursor（替代） | 备注 |
|------|----------------|----------------|------|
| IntelliSense + 跳转 | `ms-vscode.cpptools` | **`anysphere.cpptools`** | Anysphere 官方出品，基于 Clangd，需要 `compile_commands.json` |
| 调试 | cppdbg (cpptools 内置) | **CodeLLDB** (`vadimcn.vscode-lldb`) | Cursor 工程师推荐 |
| C++ 测试面板 | C/C++ DevTools | **TestMate C++** (`matepek.vscode-catch2-test-adapter`) | 详见下方测试章节 |
| CTest（无框架） | N/A | **终端 `ctest`** | 测试面板不支持裸 CTest |

## 测试面板配置（TestMate C++）

### 前提：TestMate 只支持框架测试

TestMate 通过执行 `--gtest_list_tests`（GoogleTest）/ `--list-tests`（Catch2）/ `--list-test-cases`（doctest）发现测试。**如果你的测试是 `main()` + `add_test(NAME ... COMMAND ...)` 的 CTest 模式，TestMate 发现时会崩溃，不会显示任何测试。**

必须把测试改写为 GoogleTest / Catch2 / doctest 之一。

### CMake 最佳实践：测试隔离

根 `CMakeLists.txt` 保持纯净（只负责 SDK 库编译发布），测试全部放进 `tests/CMakeLists.txt`：

```cmake
# 根 CMakeLists.txt — 只做 SDK
option(MEASUREMENT_BUILD_TESTS "Build SDK test project" ON)

if(MEASUREMENT_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
```

```cmake
# tests/CMakeLists.txt — 所有测试逻辑
include(FetchContent)

FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(measurement_sdk_tests sdk_smoke_test.cpp)
target_link_libraries(measurement_sdk_tests PRIVATE measurement GTest::gtest_main)
target_compile_definitions(measurement_sdk_tests PRIVATE
    SDK_TEST_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/data")

include(GoogleTest)
gtest_discover_tests(measurement_sdk_tests
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR})  # 测试需要 build/study/ 等资产
```

> `WORKING_DIRECTORY ${PROJECT_BINARY_DIR}` 而非 `${CMAKE_CURRENT_BINARY_DIR}`，因为测试二进制在 `build/tests/` 下运行，但资源文件（如 TorchScript 模型）在 `build/study/`。

### Cursor 远程 Settings

```json
{
    "testMate.cpp.test.executables": "build/tests/measurement_sdk_tests",
    "testMate.cpp.test.workingDirectory": "${workspaceFolder}/build",
    "testMate.cpp.discovery.loadOnStartup": true
}
```

路径写死到具体二进制，不要用 glob（`{test,Test}` 花括号展开在 VS Code 设置中不受支持）。

### 常见问题排查清单

| 症状 | 原因 | 解决 |
|------|------|------|
| 侧栏无 Testing 图标 | 没有安装任何测试扩展 | 安装 TestMate C++ |
| Testing 面板空、无测试发现 | 测试没使用 GTest/Catch2/doctest | 改为框架测试 |
| `--gtest_list_tests` 崩溃 | 二进制不认该参数（不是 GTest） | 改为框架测试 |
| Testing 面板空，但 CLI 下 `--gtest_list_tests` 正常 | **settings.json 的 `executables` 路径与实际构建目录不匹配**（如 settings 写 `build/` 但 CMake 输出到 `cmake-build-debug/`） | 检查构建目录名，更新 settings path |
| 编译报 `c10::optional` 歧义 | GTest 先引了 `<optional>`，Torch 的 `c10::optional` 冲突 | `#include "main.hpp"` 在 `#include <gtest/gtest.h>` **之前** |
| 远程 SSH 下扩展安装失败 | 微软 `ms-vscode.cpptools` 被拦截 | 装 `anysphere.cpptools` |
| `libmeasurement.so: file too short` | 并行编译竞态，链接时库未写完 | 先 `cmake --build . --target measurement` 再 `--target measurement_sdk_tests` |
| Testing 面板显示但无测试 | settings 中 `workingDirectory` 未设置，测试运行时找不到模型/数据文件 | 设 `"testMate.cpp.test.workingDirectory": "${workspaceFolder}/build"` |
| 改了 settings.json 后 Testing 面板仍不刷新 | TestMate 缓存未失效 | `Cmd+Shift+P` → `Test: Refresh Tests` |

### 远程 Cursor Settings 位置

远程 SSH 环境下 settings.json 路径不同于本地：

```
~/.cursor-server/data/Machine/settings.json
```

本地 settings 与远程 settings **互不继承**。排查远程 Testing 面板问题时，必须检查此路径而非本地 `~/Library/Application Support/Cursor/User/settings.json`。

## 参考

- `references/c10-optional-conflict.md` — LibTorch `c10::optional` 与 C++17 `std::optional` 冲突的完整诊断与修复过程。
- `references/model-deployment-pattern.md` — SDK 模型资产（`study/*.pt`）的安装路径、部署步骤与常见坑。
- `references/cursor-server-removal.md` — 从远程服务器彻底卸载 Cursor Server 的步骤（进程清理 + 目录删除 + 验证）。
