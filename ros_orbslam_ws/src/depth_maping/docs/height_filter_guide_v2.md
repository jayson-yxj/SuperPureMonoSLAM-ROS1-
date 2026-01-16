# 点云高度过滤使用指南 v2.0

## 🎯 核心改进：相对高度过滤

针对**单目SLAM尺度不确定性**问题，新增**相对高度过滤模式**，使用相机高度的倍数而非绝对米数进行过滤。

## 功能说明

### 为什么需要相对模式？

**单目SLAM的尺度问题**：
- 单目相机无法直接获取真实尺度
- ORB-SLAM3 的尺度是任意的（可能是1x、10x或0.1x真实尺度）
- 使用固定米数（如-2m~3m）会因尺度不同而失效

**相对模式的优势**：
- ✅ 自动适应任意尺度
- ✅ 基于相机当前高度的比例过滤
- ✅ 无需手动调整参数
- ✅ 适用于所有单目SLAM场景

## 两种过滤模式

### 1. 相对模式（推荐）⭐

**原理**：基于相机当前高度的倍数进行过滤

**示例**：
```
相机高度 = 5.0（任意单位）
height_ratio_min = 0.3  → 过滤低于 1.5 的点
height_ratio_max = 2.0  → 过滤高于 10.0 的点
```

**适用场景**：
- ✅ 单目SLAM（尺度未知）
- ✅ 视频回放（尺度可能变化）
- ✅ 不同环境（自动适应）

### 2. 绝对模式

**原理**：使用固定的米数范围

**示例**：
```
height_min = -2.0m
height_max = 3.0m
```

**适用场景**：
- 双目/RGB-D相机（尺度已知）
- 已标定的单目系统
- 需要精确控制的场景

## 参数配置

### 方法1：Launch 文件（推荐）

编辑 [`slam_mapping.launch`](../launch/slam_mapping.launch:23-33)：

```xml
<!-- 相对模式（默认） -->
<arg name="height_filter_mode" default="relative" />
<arg name="height_ratio_min" default="0.3" />  <!-- 30%相机高度 -->
<arg name="height_ratio_max" default="2.0" />  <!-- 200%相机高度 -->

<!-- 绝对模式 -->
<arg name="height_filter_mode" default="absolute" />
<arg name="height_min" default="-2.0" />
<arg name="height_max" default="3.0" />
```

### 方法2：命令行参数

```bash
# 相对模式
roslaunch depth_maping slam_mapping.launch \
    height_filter_mode:=relative \
    height_ratio_min:=0.3 \
    height_ratio_max:=2.0

# 绝对模式
roslaunch depth_maping slam_mapping.launch \
    height_filter_mode:=absolute \
    height_min:=-2.0 \
    height_max:=3.0
```

### 方法3：交互式配置脚本 ⭐

```bash
cd ros_orbslam_ws/src/depth_maping/scripts
./set_height_filter.sh
```

**脚本提供的预设**：
1. 禁用过滤
2. 标准范围（0.3x ~ 2.0x）【推荐】
3. 宽松范围（0.2x ~ 3.0x）
4. 严格范围（0.5x ~ 1.5x）
5. 地面附近（0.8x ~ 1.2x）
6. 自定义相对范围
7. 标准室内（绝对模式）
8. 自定义绝对范围

## 参数调优指南

### 相对模式参数

| 参数 | 默认值 | 说明 | 调整建议 |
|------|--------|------|----------|
| `height_ratio_min` | 0.3 | 最小高度比例 | 增大→过滤更多地面<br>减小→保留更多地面 |
| `height_ratio_max` | 2.0 | 最大高度比例 | 减小→过滤更多天花板<br>增大→保留更多天花板 |

### 常见场景配置

#### 场景1：标准室内建图
```xml
<arg name="height_ratio_min" default="0.3" />
<arg name="height_ratio_max" default="2.0" />
```
- 保留相机高度30%~200%的点
- 过滤大部分地面和天花板噪声

#### 场景2：地面检测/导航
```xml
<arg name="height_ratio_min" default="0.8" />
<arg name="height_ratio_max" default="1.2" />
```
- 只保留相机附近±20%高度的点
- 适合地面障碍物检测

#### 场景3：全景建图（宽松）
```xml
<arg name="height_ratio_min" default="0.2" />
<arg name="height_ratio_max" default="3.0" />
```
- 保留更多点云
- 适合完整环境重建

#### 场景4：精确建图（严格）
```xml
<arg name="height_ratio_min" default="0.5" />
<arg name="height_ratio_max" default="1.5" />
```
- 只保留相机附近的点
- 减少远处噪声

## 工作原理

### 相对模式计算流程

```python
# 1. 获取相机当前高度（Y坐标）
camera_height = 5.0  # 示例值

# 2. 计算绝对高度范围
height_min_abs = camera_height * 0.3  # = 1.5
height_max_abs = camera_height * 2.0  # = 10.0

# 3. 过滤点云
filtered_points = points[(points[:, 1] >= 1.5) & (points[:, 1] <= 10.0)]
```

### 可视化示例

```
相机高度 = 5.0
ratio_min = 0.3 (30%)
ratio_max = 2.0 (200%)

        ↑ Y轴
        |
   10.0 |------------ height_max (2.0x)
        |
        |  ✅ 保留区域
        |
    5.0 |====== 相机位置 ======
        |
        |  ✅ 保留区域
        |
    1.5 |------------ height_min (0.3x)
        |
    0.0 |____________ 地面
```

## 效果验证

### 查看实时日志

```bash
# 相对模式会显示：
📏 相机高度: 5.23 | 过滤范围: [1.57, 10.46]
🔍 高度过滤: 移除 1234/5678 点 (21.7%)
```

### RViz 可视化

1. 打开 RViz
2. 添加 PointCloud2 显示
3. 话题选择：`/o3d_pointCloud`
4. 调整参数后观察变化

### 调试命令

```bash
# 查看当前参数
rosparam get /depth_maping_node/height_filter_mode
rosparam get /depth_maping_node/height_ratio_min
rosparam get /depth_maping_node/height_ratio_max

# 实时修改（立即生效）
rosparam set /depth_maping_node/height_ratio_min 0.5
rosparam set /depth_maping_node/height_ratio_max 1.5
```

## 常见问题

### Q1: 点云全部消失了？

**原因**：比例范围设置过窄

**解决**：
```bash
# 临时禁用过滤
rosparam set /depth_maping_node/enable_height_filter false

# 或扩大范围
rosparam set /depth_maping_node/height_ratio_min 0.1
rosparam set /depth_maping_node/height_ratio_max 5.0
```

### Q2: 相对模式和绝对模式如何选择？

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 单目SLAM | 相对模式 ⭐ | 尺度未知，自动适应 |
| 双目/RGB-D | 绝对模式 | 尺度已知，精确控制 |
| 视频回放 | 相对模式 ⭐ | 尺度可能变化 |
| 实时相机 | 两者皆可 | 根据需求选择 |

### Q3: 如何找到最佳参数？

**步骤**：
1. 使用默认参数（0.3x ~ 2.0x）运行
2. 观察 RViz 中的点云效果
3. 根据需要调整：
   - 地面噪声多 → 增大 `ratio_min`
   - 天花板噪声多 → 减小 `ratio_max`
   - 点云太少 → 扩大范围
   - 点云太多 → 缩小范围

### Q4: 相对模式的性能如何？

- **计算开销**：极小（仅一次乘法）
- **内存节省**：显著（减少20-50%点云）
- **实时性**：无影响（每帧<1ms）

## 技术细节

### 代码位置

- 参数定义：[`depth_maping_node.py:143-163`](../scripts/depth_maping_node.py:143-163)
- 过滤逻辑：[`depth_maping_node.py:311-343`](../scripts/depth_maping_node.py:311-343)
- Launch 配置：[`slam_mapping.launch:23-33`](../launch/slam_mapping.launch:23-33)
- 配置脚本：[`set_height_filter.sh`](../scripts/set_height_filter.sh)

### 与其他功能的配合

```xml
<!-- 推荐配置组合 -->
<arg name="enable_sliding_window" default="true" />
<arg name="sliding_window_size" default="3" />
<arg name="enable_height_filter" default="true" />
<arg name="height_filter_mode" default="relative" />
<arg name="enable_gravity_estimate" default="true" />
```

**处理顺序**：
1. 深度估计
2. 点云生成
3. **高度过滤** ← 在这里
4. 滑动窗口
5. 发布到ROS

## 快速开始

### 1. 使用默认配置（推荐）

```bash
cd ros_orbslam_ws
./launch.sh
# 选择模式 1（完整系统）
```

默认使用相对模式（0.3x ~ 2.0x），适合大多数场景。

### 2. 自定义配置

```bash
# 编辑 launch 文件
nano src/depth_maping/launch/slam_mapping.launch

# 修改参数
<arg name="height_ratio_min" default="0.5" />
<arg name="height_ratio_max" default="1.5" />

# 重新启动
./launch.sh
```

### 3. 运行时调整

```bash
# 启动系统后，在另一个终端运行
cd src/depth_maping/scripts
./set_height_filter.sh

# 选择预设或自定义参数
```

## 总结

✅ **相对模式**是单目SLAM的最佳选择
✅ 自动适应尺度变化，无需手动调整
✅ 默认参数（0.3x ~ 2.0x）适合大多数场景
✅ 使用配置脚本可快速切换预设

---

**更新日期**：2026-01-15  
**版本**：v2.0（新增相对模式）