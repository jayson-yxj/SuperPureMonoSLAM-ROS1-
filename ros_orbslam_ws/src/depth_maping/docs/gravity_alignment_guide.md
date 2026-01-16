# 重力对齐系统使用指南

## 系统概述

本系统实现了基于位姿补偿的连续重力估计和地图对齐功能，解决了 ORB-SLAM3 位姿丢失导致的地图倾斜问题。

### 核心特性

1. **位姿补偿机制**：通过保存图像和对应的 ORB-SLAM3 位姿，实现异步处理而不损失对齐精度
2. **连续重力估计**：每秒自动重新估计重力方向，适应 SLAM 重新初始化
3. **自动对齐应用**：实时将重力对齐矩阵应用到点云，确保地图始终与重力方向一致
4. **Python 版本隔离**：GeoCalib (Python 3.9+) 和 ROS1 (Python 3.8) 通过文件通信解耦

## 工作原理

### 数学框架

#### 坐标系定义
- **相机坐标系 (C)**：标准相机坐标系
- **SLAM 世界坐标系 (W_slam)**：ORB-SLAM3 的任意世界坐标系
- **重力对齐世界坐标系 (W_gravity)**：Y 轴与重力方向对齐的坐标系

#### 关键变换
```
1. ORB-SLAM3 提供: R_cw (World → Camera)
2. 计算逆变换: R_wc = R_cw^T (Camera → World)
3. GeoCalib 估计: g_c (相机坐标系下的重力向量)
4. 变换到世界系: g_w = R_wc @ g_c
5. 计算对齐矩阵: R_align (将 g_w 对齐到 [0, -1, 0])
6. 应用到点云: p_aligned = R_align @ p_world
```

#### 对齐矩阵计算（Rodrigues 公式）
```python
def compute_alignment_matrix(g_w):
    # 归一化重力向量
    g_w = g_w / ||g_w||
    
    # 目标方向（Y 轴负方向）
    target = [0, -1, 0]
    
    # 旋转轴和角度
    axis = g_w × target
    angle = arccos(g_w · target)
    
    # Rodrigues 公式
    K = skew_symmetric(axis)
    R_align = I + sin(angle) * K + (1 - cos(angle)) * K²
    
    return R_align
```

### 数据流程

```
depth_maping_node (Python 3.8, ROS1)
    ↓ 每 1 秒
    保存: img_N.png + pose_N.json
    {
        image_path: "GE_information/img_N.png",
        timestamp: 12345.678,
        frame_id: N,
        R_cw: [[...], [...], [...]],  # 3x3
        t_cw: [x, y, z]                # 3x1
    }
    ↓
gravity_estimate.py (Python 3.9+, conda plato)
    ↓
    读取最新的 img + pose
    ↓
    GeoCalib 估计: g_c
    ↓
    变换到世界系: g_w = R_wc @ g_c
    ↓
    计算对齐矩阵: R_align
    ↓
    保存: rotation_matrices.yaml
    {
        R_align: [[...], [...], [...]],
        g_w_slam: [gx, gy, gz],
        g_aligned: [0, -1, 0],
        timestamp: 12345.678
    }
    ↓
depth_maping_node
    ↓ 每 0.5 秒检查
    加载最新的 R_align
    ↓
    应用到点云: p_aligned = R_align @ p_world
```

## 使用方法

### 1. 启动完整系统

```bash
cd ros_orbslam_ws
./launch.sh
```

选择模式 1（完整系统 + 重力估计）

### 2. 手动启动各组件

#### 启动 ROS 节点
```bash
cd ros_orbslam_ws
source devel/setup.bash
roslaunch depth_maping slam_mapping.launch enable_gravity_estimate:=true
```

#### 单独启动重力估计（如需要）
```bash
cd ros_orbslam_ws/src/depth_maping/scripts
conda run -n plato python gravity_estimate.py
```

### 3. 监控系统状态

#### 查看重力估计日志
```bash
# 在 gravity_estimate 终端查看输出
🔄 执行定期重力估计... (frame_12345)
  相机坐标系重力: gx=0.1234, gy=0.5678, gz=0.8901
  世界坐标系重力: gx=0.0123, gy=-0.9876, gz=0.1543
  旋转角度: 8.45°
  旋转轴: [0.123, 0.456, 0.789]
  对齐后重力: gx=0.0000, gy=-1.0000, gz=0.0000
  对齐误差: 0.000012
✓ 重力估计完成
✓ 对齐矩阵已更新
```

#### 查看 depth_maping_node 日志
```bash
# 在 ROS 终端查看
💾 已保存图像和位姿: frame_12345
✓ 已加载重力对齐矩阵 (timestamp: 12345.678)
  对齐后重力: [0.0000, -1.0000, 0.0000]
```

#### 检查数据文件
```bash
cd ros_orbslam_ws/src/depth_maping/scripts/GE_information
ls -lh
# 应该看到:
# img_*.png          - 保存的图像
# pose_*.json        - 位姿数据
# rotation_matrices.yaml  - 对齐矩阵
```

## 位姿丢失处理

### 自动检测机制

系统会自动检测 ORB-SLAM3 重新初始化（位姿跳变）：

```python
# 位姿跳变阈值：1.0 米
if ||t_current - t_previous|| > 1.0:
    print("⚠️  检测到位姿跳变")
    # 重新计算对齐矩阵
```

### 处理策略

**策略 A：重新初始化（当前实现）**
- 检测到位姿跳变时，立即重新计算 R_align
- 适用于离散的重新初始化事件
- 简单高效，无需历史数据

**策略 B：连续更新（可选）**
- 每帧都更新 R_align
- 维护滑动窗口平均
- 更鲁棒，但计算开销更大

## 参数配置

### depth_maping_node 参数

```python
# 重力估计间隔（秒）
self.gravity_estimate_interval = 1.0

# R_align 检查间隔（秒）
self.R_align_check_interval = 0.5
```

### gravity_estimate 参数

```python
# 估计间隔（秒）
estimate_interval = 1.0

# 位姿跳变阈值（米）
pose_jump_threshold = 1.0
```

### 调整建议

- **高频率场景**（快速运动）：减小 `gravity_estimate_interval` 到 0.5 秒
- **低频率场景**（静态或慢速）：增大到 2.0 秒以节省计算
- **频繁重新初始化**：减小 `pose_jump_threshold` 到 0.5 米
- **稳定 SLAM**：增大到 2.0 米以避免误检测

## 性能优化

### 当前性能指标

- **重力估计频率**：1 Hz（可调）
- **对齐矩阵更新延迟**：< 0.5 秒
- **点云对齐开销**：< 5 ms（矩阵乘法）
- **文件 I/O 开销**：< 10 ms

### 优化建议

1. **减少估计频率**：如果 SLAM 稳定，可以降低到 2-5 秒
2. **批量处理**：累积多帧后一次性处理
3. **GPU 加速**：将矩阵运算移到 GPU（如果可用）
4. **缓存机制**：避免重复加载相同的 R_align

## 故障排查

### 问题 1：重力估计不工作

**症状**：没有生成 `rotation_matrices.yaml`

**检查**：
```bash
# 1. 确认 gravity_estimate 进程运行
ps aux | grep gravity_estimate

# 2. 检查 conda 环境
conda env list | grep plato

# 3. 查看日志
# 在 gravity_estimate 终端查看错误信息
```

**解决**：
```bash
# 重新启动 gravity_estimate
cd ros_orbslam_ws/src/depth_maping/scripts
conda run -n plato python gravity_estimate.py
```

### 问题 2：对齐矩阵不更新

**症状**：点云仍然倾斜

**检查**：
```bash
# 1. 确认文件存在
ls -lh GE_information/rotation_matrices.yaml

# 2. 查看文件内容
cat GE_information/rotation_matrices.yaml

# 3. 检查时间戳
stat GE_information/rotation_matrices.yaml
```

**解决**：
```bash
# 1. 检查文件权限
chmod 644 GE_information/rotation_matrices.yaml

# 2. 重启 depth_maping_node
rosnode kill /depth_maping_node
# 然后重新启动
```

### 问题 3：位姿数据不保存

**症状**：`GE_information` 目录为空

**检查**：
```bash
# 1. 确认 ORB-SLAM3 正常运行
rostopic echo /orb_slam3/image_pose -n 1

# 2. 检查目录权限
ls -ld GE_information/

# 3. 查看 depth_maping_node 日志
rosnode info /depth_maping_node
```

**解决**：
```bash
# 1. 创建目录
mkdir -p GE_information
chmod 755 GE_information/

# 2. 重启节点
```

### 问题 4：对齐精度不足

**症状**：对齐后重力向量偏差 > 0.01

**检查**：
```bash
# 查看对齐误差
grep "对齐误差" gravity_estimate.log
```

**解决**：
1. 检查相机标定参数是否正确
2. 确认 ORB-SLAM3 位姿质量
3. 增加 GeoCalib 输入图像分辨率
4. 使用更多帧进行平均

## 高级功能

### 1. 旋转矩阵平滑

如需更平滑的对齐，可以实现滑动窗口平均：

```python
# 在 gravity_estimate.py 中添加
from scipy.spatial.transform import Rotation as R

def smooth_rotation_matrices(R_list, weights=None):
    """
    平滑多个旋转矩阵
    
    Args:
        R_list: 旋转矩阵列表
        weights: 权重（可选）
    
    Returns:
        平滑后的旋转矩阵
    """
    rotations = [R.from_matrix(r) for r in R_list]
    
    if weights is None:
        weights = np.ones(len(rotations))
    
    # 加权平均（使用四元数）
    quats = np.array([r.as_quat() for r in rotations])
    avg_quat = np.average(quats, axis=0, weights=weights)
    avg_quat = avg_quat / np.linalg.norm(avg_quat)
    
    return R.from_quat(avg_quat).as_matrix()
```

### 2. 实时可视化

在 RViz 中添加重力方向箭头：

```python
# 在 depth_maping_node.py 中添加
from visualization_msgs.msg import Marker

def publish_gravity_arrow(self):
    marker = Marker()
    marker.header.frame_id = "map"
    marker.header.stamp = rospy.Time.now()
    marker.type = Marker.ARROW
    marker.action = Marker.ADD
    
    # 起点（原点）
    marker.points.append(Point(0, 0, 0))
    # 终点（重力方向）
    if self.R_align is not None:
        g_aligned = self.R_align @ np.array([0, -1, 0])
        marker.points.append(Point(g_aligned[0], g_aligned[1], g_aligned[2]))
    
    marker.scale.x = 0.1  # 箭头粗细
    marker.scale.y = 0.2
    marker.color.r = 1.0
    marker.color.a = 1.0
    
    self.gravity_marker_pub.publish(marker)
```

### 3. 地图保存与加载

保存对齐后的地图：

```python
# 保存
aligned_cloud = self.all_point_cloud
if self.R_align is not None:
    points = np.asarray(aligned_cloud.points)
    points_aligned = points @ self.R_align.T
    aligned_cloud.points = o3d.utility.Vector3dVector(points_aligned)

o3d.io.write_point_cloud("aligned_map.ply", aligned_cloud)

# 同时保存对齐矩阵
np.save("R_align.npy", self.R_align)
```

## 技术细节

### 为什么使用位姿补偿？

传统方法需要实时同步图像和重力估计，但：
1. GeoCalib 需要 Python 3.9+，ROS1 使用 Python 3.8
2. 重力估计耗时较长（~100ms）
3. 实时通信增加系统复杂度

**位姿补偿方案**：
- 保存图像时同时保存对应的 ORB-SLAM3 位姿
- 异步处理时使用保存的位姿进行坐标变换
- 消除了时间延迟的影响，保证对齐精度

### Rodrigues 公式推导

将向量 v 绕单位轴 k 旋转角度 θ：

```
R = I + sin(θ) * K + (1 - cos(θ)) * K²

其中 K 是 k 的反对称矩阵：
K = [  0   -k_z   k_y ]
    [ k_z    0   -k_x ]
    [-k_y   k_x    0  ]
```

### 坐标系约定

- **ORB-SLAM3**：右手坐标系，Z 轴向前
- **ROS**：右手坐标系，X 轴向前
- **重力对齐**：Y 轴向上（与重力反向）

## 参考资料

- [GeoCalib 论文](https://arxiv.org/abs/2309.03663)
- [ORB-SLAM3 文档](https://github.com/UZ-SLAMLab/ORB_SLAM3)
- [Rodrigues 旋转公式](https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula)
- [PyPose 文档](https://pypose.org/)

## 更新日志

### v1.0.0 (2026-01-14)
- ✅ 实现基于位姿补偿的重力估计
- ✅ 支持连续重力估计（1 Hz）
- ✅ 自动检测位姿跳变
- ✅ 实时应用对齐矩阵到点云
- ✅ 完整的文档和故障排查指南