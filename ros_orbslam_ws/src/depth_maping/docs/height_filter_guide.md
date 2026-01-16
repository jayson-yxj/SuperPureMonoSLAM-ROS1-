# 点云高度过滤使用指南

## 功能说明

高度过滤功能可以过滤掉超出指定高度范围的点云，主要用于：
- 🔽 **过滤地面以下的噪声点**（如地面反射、误检测）
- 🔼 **过滤天花板以上的噪声点**（如天花板、灯具）
- 🎯 **只保留感兴趣的高度范围**（如人体活动区域）

## 坐标系说明

- **Y 轴**：垂直方向（上下）
  - Y > 0：相机上方
  - Y < 0：相机下方
- **高度过滤在世界坐标系中进行**（已经过重力对齐）

## 参数配置

### 方法1：修改 Launch 文件（推荐）

编辑 [`slam_mapping.launch`](../launch/slam_mapping.launch:23-26)：

```xml
<!-- 高度过滤参数 (Y轴方向，单位：米) -->
<arg name="enable_height_filter" default="true" />
<arg name="height_min" default="-2.0" />  <!-- 最低高度 -->
<arg name="height_max" default="3.0" />   <!-- 最高高度 -->
```

### 方法2：命令行参数

```bash
roslaunch depth_maping slam_mapping.launch \
    enable_height_filter:=true \
    height_min:=-1.5 \
    height_max:=2.5
```

### 方法3：运行时动态调整

```bash
# 禁用高度过滤
rosparam set /depth_maping_node/enable_height_filter false

# 调整高度范围
rosparam set /depth_maping_node/height_min -1.0
rosparam set /depth_maping_node/height_max 2.0

# 重启节点使参数生效
rosnode kill /depth_maping_node
# 然后重新启动节点
```

## 参数调优建议

### 室内场景（默认）
```xml
<arg name="height_min" default="-2.0" />  <!-- 过滤地面以下 2m -->
<arg name="height_max" default="3.0" />   <!-- 过滤天花板以上 3m -->
```
- 适用于标准层高（2.5-3m）的室内环境
- 保留人体活动区域（-2m 到 +3m）

### 低矮空间（如车库、地下室）
```xml
<arg name="height_min" default="-1.0" />
<arg name="height_max" default="2.0" />
```

### 高层空间（如大厅、仓库）
```xml
<arg name="height_min" default="-3.0" />
<arg name="height_max" default="5.0" />
```

### 只保留地面附近（如扫地机器人）
```xml
<arg name="height_min" default="-0.5" />
<arg name="height_max" default="0.5" />
```

### 只保留人体高度
```xml
<arg name="height_min" default="0.5" />   <!-- 腰部以上 -->
<arg name="height_max" default="2.0" />   <!-- 头部以下 -->
```

## 效果验证

### 查看日志
系统会定期输出过滤统计信息：
```
🔍 高度过滤: 移除 1234/5678 点 (21.7%)
```

### RViz 可视化
1. 打开 RViz
2. 查看 `/o3d_pointCloud` 话题
3. 调整参数后观察点云变化

### 调试技巧
```bash
# 查看当前参数
rosparam get /depth_maping_node/enable_height_filter
rosparam get /depth_maping_node/height_min
rosparam get /depth_maping_node/height_max

# 查看点云话题信息
rostopic echo /o3d_pointCloud --noarr
```

## 常见问题

### Q1: 点云全部消失了？
**原因**：高度范围设置过窄，所有点都被过滤掉了

**解决**：
```bash
# 临时禁用过滤
rosparam set /depth_maping_node/enable_height_filter false
# 或扩大高度范围
rosparam set /depth_maping_node/height_min -5.0
rosparam set /depth_maping_node/height_max 5.0
```

### Q2: 地面噪声还是很多？
**原因**：`height_min` 设置过低

**解决**：逐步提高 `height_min`
```bash
rosparam set /depth_maping_node/height_min -1.0  # 从 -2.0 提高到 -1.0
```

### Q3: 天花板还是显示？
**原因**：`height_max` 设置过高

**解决**：逐步降低 `height_max`
```bash
rosparam set /depth_maping_node/height_max 2.5  # 从 3.0 降低到 2.5
```

### Q4: 如何找到合适的参数？
**方法**：
1. 先禁用过滤，观察完整点云
2. 在 RViz 中测量地面和天花板的 Y 坐标
3. 设置 `height_min` 略高于地面，`height_max` 略低于天花板
4. 逐步调整直到满意

## 与其他功能的配合

### 与滑动窗口配合
```xml
<arg name="enable_sliding_window" default="true" />
<arg name="sliding_window_size" default="3" />
<arg name="enable_height_filter" default="true" />
```
- 先进行高度过滤，再加入滑动窗口
- 减少内存占用和计算量

### 与重力对齐配合
```xml
<arg name="enable_gravity_estimate" default="true" />
<arg name="enable_height_filter" default="true" />
```
- **必须启用重力对齐**，否则高度过滤无效
- 重力对齐确保 Y 轴垂直向上

## 性能影响

- **计算开销**：极小（仅数组索引操作）
- **内存节省**：显著（减少 20-50% 点云数量）
- **可视化性能**：提升（点云更少，渲染更快）

## 代码位置

- 参数定义：[`depth_maping_node.py:143-151`](../scripts/depth_maping_node.py:143-151)
- 过滤逻辑：[`depth_maping_node.py:311-327`](../scripts/depth_maping_node.py:311-327)
- Launch 配置：[`slam_mapping.launch:23-26`](../launch/slam_mapping.launch:23-26)

## 示例场景

### 场景1：办公室建图
```bash
roslaunch depth_maping slam_mapping.launch \
    height_min:=-1.5 \
    height_max:=2.5
```

### 场景2：仓库巡检
```bash
roslaunch depth_maping slam_mapping.launch \
    height_min:=-2.0 \
    height_max:=4.0
```

### 场景3：地面检测
```bash
roslaunch depth_maping slam_mapping.launch \
    height_min:=-0.3 \
    height_max:=0.3
```

---

**提示**：建议先使用默认参数运行，观察效果后再根据实际场景调整。