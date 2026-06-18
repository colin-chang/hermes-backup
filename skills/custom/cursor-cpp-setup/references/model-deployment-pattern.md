# 模型资产部署模式

## 场景

SDK 内部通过硬编码相对路径加载 TorchScript 模型文件：

```cpp
// bpServer.cpp — 旧分支
torch::jit::load("./study/systolic.pt");
torch::jit::load("./study/diastolic.pt");

// bpServerNew.cpp — 新分支
torch::jit::load("study/systolic_best.pt");
torch::jit::load("study/dia_best_cnn_9B_3K_32F.pt");

// riskServer.cpp
torch::jit::load("./study/risknet_heart_attack_1023.pt");
```

所有路径都是相对于**当前工作目录**的 `./study/` 或 `study/`，不可通过环境变量修改。

## 构建与安装

CMake 的 `install(DIRECTORY ...)` 将模型安装到标准位置：

```cmake
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/study/"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/measurement/study")
```

产物结构：

```
dist/
├── lib/libmeasurement.so
├── include/...
└── share/measurement/study/
    ├── systolic.pt
    ├── diastolic.pt
    ├── systolic_best.pt
    ├── dia_best_cnn_9B_3K_32F.pt
    └── ...（其余 .pt 文件）
```

## 部署步骤

用户拿到 `dist/` 后，必须将 `study/` 放到应用启动目录下：

```bash
# 方式一：拷贝
cp -r dist/share/measurement/study ./study

# 方式二：软链接（开发/测试环境推荐）
ln -s dist/share/measurement/study ./study
```

之后从**含 `study/` 的目录**启动应用：

```bash
cd /path/to/app  # 此目录下必须有 study/
./my_app
```

## README 文档化要点

必须在 SDK 的 README 中明确说明：

1. 模型文件通过**相对路径**加载
2. 部署后的 `study/` 目录必须与可执行文件位于**同一工作目录**
3. 路径不可通过环境变量修改
4. 提供 `cp` / `ln -s` 两种部署方式示例

## 常见坑

| 症状 | 原因 |
|------|------|
| `open file failed because of errno 2 on fopen: file path: study/systolic_best.pt` | 工作目录下没有 `study/` |
| CTest/TestMate 测试失败但 CLI 下 `cd build && ./tests/measurement_sdk_tests` 通过 | TestMate 的 `workingDirectory` 没指向 `build/`，模型找不到 |
