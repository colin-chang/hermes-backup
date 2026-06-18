# LibTorch `c10::optional` vs `std::optional` 冲突

## 触发条件

同时满足以下三点时爆发：

1. 项目依赖 LibTorch（PyTorch C++ API）
2. 使用 GoogleTest 框架
3. `#include <gtest/gtest.h>` 出现在 Torch 头文件之前

## 原因

- GTest 的 `gtest-port.h` 间接引入了 `<optional>`（C++17），使 `std::optional` 进入全局命名空间作用域
- LibTorch 在 `c10/util/Optional.h` 定义了 `c10::optional`
- Torch 内部代码（如 `ATen/ops/from_blob.h`）使用裸名 `optional<T>`（依赖 `using namespace c10` 或类似上下文），编译器无法区分 `c10::optional` 和 `std::optional`

## 典型错误信息

```
/usr/local/libtorch/include/ATen/DeviceGuard.h:25:8: error: reference to 'optional' is ambiguous
   25 | inline optional<Device> device_of(const optional<Tensor>& t) {

/usr/include/c++/13/optional:72:11: note: candidates are: 'template<class _Tp> class std::optional'
/usr/local/libtorch/include/c10/util/Optional.h:65:7: note:                 'template<class T> class c10::optional'

/usr/local/libtorch/include/ATen/ops/from_blob.h:29:31: error: 'optional' has not been declared
/usr/local/libtorch/include/ATen/ops/from_blob.h:30:5: error: 'strides_' was not declared in this scope
```

## 修复

**把头文件顺序倒过来**：先引 Torch 依赖的头文件，再引 GTest。

```cpp
// ✅ 正确顺序
#include "main.hpp"           // 内部间接引入 torch/script.h、ATen 等
#include <gtest/gtest.h>      // 此时 std::optional 不会与 c10 上下文冲突
```

```cpp
// ❌ 错误顺序（导致上述编译错误）
#include <gtest/gtest.h>      // 先引入了 std::optional
#include "main.hpp"           // Torch 的 c10::optional 再进来 → 歧义
```

## 为什么"Torch 先"能解决

Torch 头文件加载时，`<optional>` 尚未被引入，`c10::optional` 是唯一的 `optional` 候选。到 GTest 引入 `<optional>` 时，Torch 内部的 `using` 上下文已经闭合，不会产生歧义。

## 替代方案（不推荐）

- 在项目级 CMake 加 `add_definitions(-Doptional=c10::optional)` — 太粗暴，污染全局命名空间
- 把 GTest 换成 doctest — 可能避免，但未验证且改动太大
