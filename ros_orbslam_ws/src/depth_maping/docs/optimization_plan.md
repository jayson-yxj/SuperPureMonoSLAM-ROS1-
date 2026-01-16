# 系统性能优化计划

**文档版本**：v1.0  
**创建日期**：2026-01-15  
**状态**：待实施

---

## 📊 当前性能分析

### 性能瓶颈识别

| 模块 | 耗时（估算） | 占比 | 优先级 |
|------|-------------|------|--------|
| 深度估计 | ~0.3s/帧 | 33% | ⭐⭐⭐⭐⭐ |
| 点云处理 | ~0.2s/帧 | 22% | ⭐⭐⭐⭐ |
| 可视化 | ~0.1s/帧 | 11% | ⭐⭐⭐ |
| 2D地图生成 | ~0.05s/10帧 | 6% | ⭐⭐ |
| 其他开销 | ~0.25s/帧 | 28% | ⭐⭐⭐ |
| **总计** | **~0.9s/帧** | **100%** | **1.1 FPS** |

### 当前配置
- **深度估计分辨率**：256px
- **体素下采样**：1.0m
- **滑动窗口**：3帧
- **2D地图更新**：每10帧
- **点云发布**：每帧

---

## 🚀 优化方案

### 优先级1：深度估计加速 ⭐⭐⭐⭐⭐

#### 方案1.1：TensorRT 加速
**预期效果**：2-5倍加速（0.3s → 0.06-0.15s）

**实施步骤**：
1. 导出 ONNX 模型
   ```python
   import torch
   model = DepthAnythingV2(...)
   dummy_input = torch.randn(1, 3, 256, 256)
   torch.onnx.export(model, dummy_input, "depth_anything_v2.onnx")
   ```

2. 转换为 TensorRT engine
   ```bash
   trtexec --onnx=depth_anything_v2.onnx \
           --saveEngine=depth_anything_v2.trt \
           --fp16  # 使用FP16加速
   ```

3. 集成到代码
   ```python
   import tensorrt as trt
   import pycuda.driver as cuda
   
   class TensorRTDepthEstimator:
       def __init__(self, engine_path):
           self.engine = self.load_engine(engine_path)
           self.context = self.engine.create_execution_context()
   ```

**优点**：
- 显著提升速度
- 降低GPU占用
- 支持FP16/INT8量化

**缺点**：
- 需要NVIDIA GPU
- 首次转换耗时（~5-10分钟）
- 模型固定输入尺寸

**参考资源**：
- TensorRT官方文档：https://docs.nvidia.com/deeplearning/tensorrt/
- PyTorch to TensorRT：https://github.com/NVIDIA-AI-IOT/torch2trt

---

#### 方案1.2：模型量化
**预期效果**：1.5-2倍加速（0.3s → 0.15-0.2s）

**实施步骤**：
```python
# FP32 → FP16
model = model.half()  # 转换为FP16
input_tensor = input_tensor.half()

# 或使用 torch.cuda.amp 自动混合精度
from torch.cuda.amp import autocast

with autocast():
    depth = model(image)
```

**优点**：
- 实施简单
- 精度损失很小（<1%）
- 内存占用减半

**缺点**：
- 需要GPU支持FP16
- 某些操作可能不支持

---

#### 方案1.3：降低输入分辨率
**当前**：256px  
**可选**：192px, 384px

**权衡分析**：
| 分辨率 | 速度 | 精度 | 推荐场景 |
|--------|------|------|----------|
| 192px | 快1.5倍 | 略降 | 实时性要求高 |
| 256px | 基准 | 平衡 | 当前设置 |
| 384px | 慢2倍 | 更高 | 精度要求高 |

---

### 优先级2：并行处理 ⭐⭐⭐⭐⭐

#### 方案2.1：多线程处理
**预期效果**：整体提速30-50%

**架构设计**：
```python
import threading
from queue import Queue

class ParallelMappingPipeline:
    def __init__(self):
        self.depth_queue = Queue(maxsize=2)
        self.pointcloud_queue = Queue(maxsize=2)
        
        # 启动工作线程
        self.depth_thread = threading.Thread(target=self.depth_worker)
        self.pointcloud_thread = threading.Thread(target=self.pointcloud_worker)
        self.map_thread = threading.Thread(target=self.map_worker)
        
    def depth_worker(self):
        """深度估计线程"""
        while True:
            image = self.depth_queue.get()
            depth = self.depth_estimator.estimate(image)
            self.pointcloud_queue.put((image, depth))
            
    def pointcloud_worker(self):
        """点云生成线程"""
        while True:
            image, depth = self.pointcloud_queue.get()
            points = self.generate_pointcloud(depth, image)
            self.map_queue.put(points)
            
    def map_worker(self):
        """地图更新线程"""
        while True:
            points = self.map_queue.get()
            self.map_builder.update(points)
```

**注意事项**：
- 使用线程安全的数据结构
- 控制队列大小避免内存溢出
- 处理线程同步和异常

---

#### 方案2.2：GPU加速点云处理
**预期效果**：点云处理加速5-10倍

**实施方案**：
```python
import torch

class GPUPointCloudGenerator:
    def generate(self, depth, rgb, camera_params, pose):
        # 保持数据在GPU上
        depth_gpu = torch.from_numpy(depth).cuda()
        
        # GPU上进行坐标变换
        h, w = depth_gpu.shape
        u, v = torch.meshgrid(torch.arange(w), torch.arange(h))
        u, v = u.cuda(), v.cuda()
        
        # 计算3D坐标
        Z = depth_gpu
        X = (u - cx) * Z / fx
        Y = (v - cy) * Z / fy
        
        points = torch.stack([X, Y, Z], dim=-1)
        
        # 位姿变换（GPU）
        pose_gpu = torch.from_numpy(pose).cuda()
        points_world = points @ pose_gpu[:3, :3].T + pose_gpu[:3, 3]
        
        # 最后再转回CPU
        return points_world.cpu().numpy()
```

**优点**：
- 避免CPU-GPU数据传输
- 充分利用GPU并行计算
- 与深度估计共享GPU

---

### 优先级3：内存优化 ⭐⭐⭐⭐

#### 方案3.1：点云内存管理
**问题**：滑动窗口累积导致内存持续增长

**解决方案**：
```python
class MemoryManagedPointCloud:
    def __init__(self, max_points=1_000_000):
        self.max_points = max_points
        self.points = []
        self.colors = []
        
    def add_points(self, new_points, new_colors):
        self.points.append(new_points)
        self.colors.append(new_colors)
        
        # 检查总点数
        total_points = sum(len(p) for p in self.points)
        
        if total_points > self.max_points:
            # 策略1：移除最旧的帧
            self.points.pop(0)
            self.colors.pop(0)
            
            # 策略2：随机下采样
            # all_points = np.vstack(self.points)
            # indices = np.random.choice(len(all_points), self.max_points)
            # self.points = [all_points[indices]]
```

**配置参数**：
```yaml
memory_management:
  max_points: 1000000  # 100万点上限
  strategy: "remove_oldest"  # 或 "random_sample"
  warning_threshold: 0.8  # 80%时警告
```

---

#### 方案3.2：按需生成2D地图
**当前**：每10帧生成一次  
**优化**：仅在需要时生成

**实施**：
```python
class OnDemandMapBuilder:
    def __init__(self):
        self.map_dirty = False
        self.cached_map = None
        
    def update_points(self, points):
        self.points = points
        self.map_dirty = True  # 标记地图需要更新
        
    def get_map(self):
        if self.map_dirty:
            self.cached_map = self.generate_map()
            self.map_dirty = False
        return self.cached_map
```

---

### 优先级4：算法优化 ⭐⭐⭐⭐

#### 方案4.1：增量式2D地图更新
**预期效果**：2D地图生成加速5-10倍

**当前问题**：每次重新计算整个地图

**优化方案**：
```python
class IncrementalOccupancyMap:
    def __init__(self, resolution):
        self.resolution = resolution
        self.grid_counts = {}  # 使用字典存储非零网格
        
    def update(self, new_points):
        """只更新新点影响的网格"""
        # 计算新点所在的网格
        grid_indices = (new_points / self.resolution).astype(int)
        
        # 更新计数
        for idx in grid_indices:
            key = tuple(idx)
            self.grid_counts[key] = self.grid_counts.get(key, 0) + 1
            
    def get_map(self):
        """从字典快速生成地图"""
        # 只处理有点的网格
        occupied_cells = {k: v for k, v in self.grid_counts.items() 
                         if v >= self.occupied_thresh}
        return self.dict_to_grid(occupied_cells)
```

**优点**：
- 避免重复计算
- 内存效率高（稀疏存储）
- 支持大范围地图

---

#### 方案4.2：自适应体素下采样
**当前**：固定 voxel_size=1.0  
**优化**：根据点云密度动态调整

**实施**：
```python
def adaptive_voxel_size(points, target_points=50000):
    """
    根据点云数量自动调整体素大小
    
    Args:
        points: 输入点云
        target_points: 目标点云数量
        
    Returns:
        optimal_voxel_size: 最优体素大小
    """
    current_points = len(points)
    
    if current_points < target_points:
        return 0.5  # 点少，用小voxel保留细节
    elif current_points < target_points * 2:
        return 1.0  # 适中
    else:
        # 计算需要的voxel大小
        ratio = current_points / target_points
        return 1.0 * (ratio ** (1/3))  # 立方根关系
```

**配置**：
```yaml
adaptive_downsampling:
  enabled: true
  target_points: 50000
  min_voxel_size: 0.5
  max_voxel_size: 2.0
```

---

### 优先级5：传输优化 ⭐⭐⭐

#### 方案5.1：点云压缩
**预期效果**：减少网络带宽50-80%

**方案A：使用ROS压缩传输**
```python
# 使用 compressed_depth_image_transport
from sensor_msgs.msg import CompressedImage

compressed_msg = CompressedImage()
compressed_msg.format = "png"
compressed_msg.data = cv2.imencode('.png', depth_image)[1].tobytes()
```

**方案B：自定义压缩**
```python
import zlib

def compress_pointcloud(points, colors):
    """压缩点云数据"""
    # 量化坐标（float32 → int16）
    points_quantized = (points * 1000).astype(np.int16)
    colors_quantized = (colors * 255).astype(np.uint8)
    
    # 压缩
    points_compressed = zlib.compress(points_quantized.tobytes())
    colors_compressed = zlib.compress(colors_quantized.tobytes())
    
    return points_compressed, colors_compressed
```

---

#### 方案5.2：降低发布频率
**当前配置**：
- 点云：每帧发布
- 2D地图：每10帧发布

**优化配置**：
```yaml
publish_rate:
  point_cloud: 2  # 每2帧发布一次
  occupancy_grid: 30  # 每30帧发布一次
  depth_image: 5  # 每5帧发布一次（如果需要）
```

**实施**：
```python
if self.frame_counter % self.point_cloud_publish_rate == 0:
    self.pcl_pub.publish(point_cloud_msg)
    
if self.frame_counter % self.map_publish_rate == 0:
    self.map_pub.publish(occupancy_grid_msg)
```

---

## 📈 预期性能提升

### 阶段性目标

#### 阶段1：快速优化（1-2天）⚡
**实施内容**：
- ✅ 禁用Open3D可视化（已完成）
- 降低2D地图更新频率（10→30帧）
- 调整点云发布频率（每帧→每2帧）
- 增加体素下采样（1.0→1.5）

**预期效果**：
```
当前：1.1 FPS
优化后：2.0 FPS
提升：82%
```

---

#### 阶段2：中期优化（3-5天）🚀
**实施内容**：
- 实施多线程处理
- GPU加速点云处理
- 增量式2D地图更新
- 内存管理优化

**预期效果**：
```
当前：2.0 FPS
优化后：4.0 FPS
提升：100%
```

---

#### 阶段3：深度优化（1-2周）🔥
**实施内容**：
- TensorRT加速深度估计
- 模型量化（FP16）
- 点云压缩传输
- 自适应参数调整

**预期效果**：
```
当前：4.0 FPS
优化后：8-10 FPS
提升：100-150%
```

---

### 最终性能预测

| 模块 | 当前耗时 | 优化后耗时 | 提升 |
|------|---------|-----------|------|
| 深度估计 | 0.3s | 0.06s | 5x |
| 点云处理 | 0.2s | 0.04s | 5x |
| 可视化 | 0.1s | 0.0s | ∞ |
| 2D地图 | 0.05s | 0.01s | 5x |
| 其他 | 0.25s | 0.14s | 1.8x |
| 并行节省 | - | -0.1s | - |
| **总计** | **0.9s** | **0.15s** | **6x** |
| **FPS** | **1.1** | **6.7** | **6x** |

---

## 🛠️ 实施优先级建议

### 如果追求快速见效
1. 阶段1快速优化
2. 多线程处理
3. 降低发布频率

**时间**：2-3天  
**效果**：1.1 FPS → 3 FPS

---

### 如果追求最佳性能
1. 完整实施阶段1-3
2. TensorRT加速
3. GPU加速点云

**时间**：2-3周  
**效果**：1.1 FPS → 8-10 FPS

---

### 如果硬件受限（无GPU）
1. 算法优化（增量更新）
2. 自适应采样
3. 降低分辨率

**时间**：1周  
**效果**：1.1 FPS → 2-3 FPS

---

## 📝 实施检查清单

### 准备工作
- [ ] 性能基准测试（记录当前FPS）
- [ ] 确认硬件配置（GPU型号、内存）
- [ ] 备份当前代码
- [ ] 创建性能测试脚本

### 阶段1
- [ ] 禁用可视化
- [ ] 调整发布频率
- [ ] 增加体素大小
- [ ] 性能测试

### 阶段2
- [ ] 实现多线程框架
- [ ] GPU点云处理
- [ ] 增量地图更新
- [ ] 内存管理
- [ ] 性能测试

### 阶段3
- [ ] TensorRT模型转换
- [ ] 集成TensorRT推理
- [ ] FP16量化
- [ ] 点云压缩
- [ ] 最终性能测试

---

## 🔍 性能监控

### 监控指标
```python
class PerformanceMonitor:
    def __init__(self):
        self.metrics = {
            'depth_estimation_time': [],
            'pointcloud_generation_time': [],
            'map_update_time': [],
            'total_callback_time': [],
            'memory_usage': [],
            'fps': []
        }
        
    def log_metrics(self):
        """记录性能指标"""
        rospy.loginfo_throttle(10, f"""
        性能统计（最近100帧）:
        - 深度估计: {np.mean(self.metrics['depth_estimation_time']):.3f}s
        - 点云生成: {np.mean(self.metrics['pointcloud_generation_time']):.3f}s
        - 地图更新: {np.mean(self.metrics['map_update_time']):.3f}s
        - 总耗时: {np.mean(self.metrics['total_callback_time']):.3f}s
        - FPS: {1/np.mean(self.metrics['total_callback_time']):.1f}
        - 内存: {self.get_memory_usage():.1f} MB
        """)
```

---

## 📚 参考资源

### TensorRT
- 官方文档：https://docs.nvidia.com/deeplearning/tensorrt/
- PyTorch转换：https://github.com/NVIDIA-AI-IOT/torch2trt
- 示例代码：https://github.com/NVIDIA/TensorRT/tree/main/samples/python

### 并行处理
- Python threading：https://docs.python.org/3/library/threading.html
- Python multiprocessing：https://docs.python.org/3/library/multiprocessing.html
- ROS多线程：http://wiki.ros.org/rospy/Overview/Publishers%20and%20Subscribers

### 点云处理
- Open3D文档：http://www.open3d.org/docs/
- PCL教程：https://pcl.readthedocs.io/
- GPU加速：https://github.com/NVIDIA/cuda-samples

---

## 📅 更新日志

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-01-15 | v1.0 | 初始版本，完整优化方案 |

---

**注意**：本文档为优化计划，实际实施时需要根据具体情况调整。建议先进行性能基准测试，然后逐步实施优化方案。