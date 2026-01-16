# 重力对齐系统 - 快速开始

## 概述

基于位姿补偿的连续重力估计系统，解决 ORB-SLAM3 位姿丢失导致的地图倾斜问题。

### 核心特性
- ✅ **位姿补偿**：通过保存图像+位姿，实现异步处理而不损失精度
- ✅ **连续估计**：每秒自动重新估计重力方向
- ✅ **自动对齐**：实时应用对齐矩阵到点云
- ✅ **位姿跳变检测**：自动处理 SLAM 重新初始化

## 快速开始

### 1. 系统测试

```bash
cd ros_orbslam_ws/src/depth_maping/scripts
./test_gravity_system.sh
```

这将检查：
- Python 环境配置
- 依赖包安装
- 文件权限
- 现有数据状态

### 2. 启动系统

```bash
cd ros_orbslam_ws
./launch.sh
```

选择 **模式 1**（完整系统 + 重力估计）

### 3. 监控运行

**查看重力估计日志：**
```bash
# 在 gravity_estimate 终端查看
🔄 执行定期重力估计... (frame_12345)
  相机坐标系重力: gx=0.1234, gy=0.5678, gz=0.8901
  世界坐标系重力: gx=0.0123, gy=-0.9876, gz=0.1543
  旋转角度: 8.45°
✓ 重力估计完成
```

**查看 depth_maping_node 日志：**
```bash
# 在 ROS 终端查看
💾 已保存图像和位姿: frame_12345
✓ 已加载重力对齐矩阵
  对齐后重力: [0.0000, -1.0000, 0.0000]
```

**检查数据文件：**
```bash
cd ros_orbslam_ws/src/depth_maping/scripts/GE_information
ls -lh
# img_*.png          - 保存的图像
# pose_*.json        - 位姿数据
# rotation_matrices.yaml  - 对齐矩阵
```

## 工作原理

```
depth_maping_node (ROS, Python 3.8)
    ↓ 每 1 秒
    保存: img_N.png + pose_N.json
    {
        image_path: "...",
        R_cw: [[...], [...], [...]],  # 3x3 旋转矩阵
        t_cw: [x, y, z]                # 3x1 平移向量
    }
    ↓
gravity_estimate.py (conda plato, Python 3.9+)
    ↓
    GeoCalib 估计: g_c (相机坐标系重力)
    ↓
    变换到世界系: g_w = R_wc @ g_c
    ↓
    计算对齐矩阵: R_align (Rodrigues 公式)
    ↓
    保存: rotation_matrices.yaml
    ↓
depth_maping_node
    ↓ 每 0.5 秒检查
    加载并应用 R_align 到点云
```

## 数学原理

### 坐标变换链
```
1. ORB-SLAM3: R_cw (World → Camera)
2. 逆变换: R_wc = R_cw^T (Camera → World)
3. GeoCalib: g_c (相机坐标系重力)
4. 变换: g_w = R_wc @ g_c (世界坐标系重力)
5. 对齐: R_align (将 g_w 对齐到 [0, -1, 0])
6. 应用: p_aligned = R_align @ p_world
```

### Rodrigues 公式
```
R_align = I + sin(θ) * K + (1 - cos(θ)) * K²

其中：
- θ = arccos(g_w · [0, -1, 0])
- K = skew_symmetric(g_w × [0, -1, 0])
```

## 参数配置

### depth_maping_node.py
```python
self.gravity_estimate_interval = 1.0  # 保存间隔（秒）
self.R_align_check_interval = 0.5     # 检查间隔（秒）
```

### gravity_estimate.py
```python
estimate_interval = 1.0          # 估计间隔（秒）
pose_jump_threshold = 1.0        # 位姿跳变阈值（米）
```

### 调整建议
- **快速运动**：减小 `gravity_estimate_interval` 到 0.5 秒
- **静态场景**：增大到 2.0 秒以节省计算
- **频繁重新初始化**：减小 `pose_jump_threshold` 到 0.5 米

## 故障排查

### 问题 1：重力估计不工作

**检查：**
```bash
# 1. 确认进程运行
ps aux | grep gravity_estimate

# 2. 检查 conda 环境
conda env list | grep plato

# 3. 查看日志
# 在 gravity_estimate 终端查看错误
```

**解决：**
```bash
cd ros_orbslam_ws/src/depth_maping/scripts
conda run -n plato python gravity_estimate.py
```

### 问题 2：对齐矩阵不更新

**检查：**
```bash
# 1. 确认文件存在
ls -lh GE_information/rotation_matrices.yaml

# 2. 查看内容
cat GE_information/rotation_matrices.yaml

# 3. 检查时间戳
stat GE_information/rotation_matrices.yaml
```

### 问题 3：位姿数据不保存

**检查：**
```bash
# 1. 确认 ORB-SLAM3 运行
rostopic echo /orb_slam3/image_pose -n 1

# 2. 检查目录权限
ls -ld GE_information/

# 3. 查看节点日志
rosnode info /depth_maping_node
```

## 文件结构

```
ros_orbslam_ws/src/depth_maping/
├── scripts/
│   ├── depth_maping_node.py          # 主节点（保存数据+应用对齐）
│   ├── gravity_estimate.py           # 重力估计节点
│   ├── gravity_estimate_wrapper.sh   # Conda 环境包装器
│   ├── test_gravity_system.sh        # 系统测试脚本
│   └── GE_information/                # 数据目录
│       ├── img_*.png                  # 图像
│       ├── pose_*.json                # 位姿
│       └── rotation_matrices.yaml     # 对齐矩阵
├── docs/
│   └── gravity_alignment_guide.md     # 详细文档
└── launch/
    └── slam_mapping.launch            # Launch 文件
```

## 性能指标

- **重力估计频率**：1 Hz（可调）
- **对齐矩阵更新延迟**：< 0.5 秒
- **点云对齐开销**：< 5 ms
- **文件 I/O 开销**：< 10 ms

## 详细文档

完整的使用指南、技术细节和高级功能请参见：
- [`docs/gravity_alignment_guide.md`](docs/gravity_alignment_guide.md)

## 技术支持

如遇问题，请：
1. 运行测试脚本：`./test_gravity_system.sh`
2. 查看详细文档中的「故障排查」章节
3. 检查日志输出中的错误信息

## 更新日志

### v1.0.0 (2026-01-14)
- ✅ 实现基于位姿补偿的重力估计
- ✅ 支持连续重力估计（1 Hz）
- ✅ 自动检测位姿跳变
- ✅ 实时应用对齐矩阵
- ✅ 完整的测试和文档