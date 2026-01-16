# ROS Navigation Stack 集成指南

本文档说明如何将 ROS Navigation Stack 集成到当前的视觉SLAM系统中。

## 📋 前提条件

- ✅ 已有 OccupancyGrid 地图发布到 `/projected_map`
- ✅ ORB-SLAM3 提供位姿信息
- ⚠️ 需要机器人底盘控制接口

---

## 🚀 快速开始

### 1. 安装依赖

```bash
sudo apt-get install ros-noetic-navigation \
                     ros-noetic-move-base \
                     ros-noetic-amcl \
                     ros-noetic-map-server \
                     ros-noetic-dwa-local-planner
```

### 2. 配置机器人参数

编辑 `config/robot_params.yaml`，填入您的机器人参数：

```yaml
# 机器人物理参数
robot_radius: 0.2          # 机器人半径（米）
max_vel_x: 0.5            # 最大线速度（米/秒）
max_vel_theta: 1.0        # 最大角速度（弧度/秒）
acc_lim_x: 2.5            # 线加速度限制
acc_lim_theta: 3.2        # 角加速度限制

# TF 坐标系
base_frame: "base_link"
odom_frame: "odom"
map_frame: "map"
```

### 3. 启动导航

```bash
# 终端1: 启动SLAM和建图
cd ~/Desktop/HighTorque_vision/orbslam_depthmaping_ros_2/ros_orbslam_ws
./launch.sh

# 终端2: 启动导航
roslaunch robot_navigation navigation.launch
```

### 4. 发送导航目标

在 RViz 中：
1. 点击 "2D Nav Goal"
2. 在地图上点击目标位置
3. 拖动箭头设置目标方向

---

## 📁 文件结构

```
robot_navigation/
├── package.xml                    # ROS包配置
├── CMakeLists.txt                 # 编译配置
├── launch/
│   ├── navigation.launch          # 主启动文件
│   └── move_base.launch           # move_base配置
├── params/
│   ├── costmap_common_params.yaml # 代价地图通用参数
│   ├── local_costmap_params.yaml  # 局部代价地图
│   ├── global_costmap_params.yaml # 全局代价地图
│   ├── base_local_planner_params.yaml  # 局部规划器
│   └── dwa_local_planner_params.yaml   # DWA规划器
└── config/
    └── robot_params.yaml          # 机器人参数
```

---

## ⚙️ 关键配置说明

### 1. 地图话题映射

由于您的地图发布在 `/projected_map`，需要重映射：

```xml
<remap from="map" to="/projected_map"/>
```

### 2. 定位方式

**选项A: 使用 ORB-SLAM3 位姿（推荐）**
- 直接使用 ORB-SLAM3 的位姿
- 不需要 AMCL
- 需要发布 TF: `map -> odom -> base_link`

**选项B: 使用 AMCL**
- 在地图上进行粒子滤波定位
- 适合地图已知的情况
- 需要里程计信息

### 3. 代价地图配置

```yaml
# 全局代价地图 - 使用完整地图
global_costmap:
  global_frame: map
  robot_base_frame: base_link
  update_frequency: 1.0
  static_map: false  # 使用动态地图
  rolling_window: false

# 局部代价地图 - 机器人周围小范围
local_costmap:
  global_frame: odom
  robot_base_frame: base_link
  update_frequency: 5.0
  publish_frequency: 2.0
  static_map: false
  rolling_window: true
  width: 4.0
  height: 4.0
  resolution: 0.05
```

---

## 🔧 需要实现的功能

### 1. TF 发布器

创建节点发布 TF 变换：

```python
#!/usr/bin/env python3
import rospy
import tf2_ros
from geometry_msgs.msg import TransformStamped

def publish_tf():
    br = tf2_ros.TransformBroadcaster()
    
    # 从 ORB-SLAM3 获取位姿
    # 发布 map -> odom -> base_link
    
    t = TransformStamped()
    t.header.stamp = rospy.Time.now()
    t.header.frame_id = "map"
    t.child_frame_id = "odom"
    # 填充位姿数据
    br.sendTransform(t)
```

### 2. 速度命令接口

订阅 `/cmd_vel` 并转发给机器人：

```python
def cmd_vel_callback(msg):
    # msg.linear.x  - 线速度
    # msg.angular.z - 角速度
    # 发送给机器人底盘
    pass
```

### 3. 里程计发布（可选）

如果使用 AMCL，需要发布里程计：

```python
from nav_msgs.msg import Odometry

def publish_odom():
    odom = Odometry()
    odom.header.stamp = rospy.Time.now()
    odom.header.frame_id = "odom"
    odom.child_frame_id = "base_link"
    # 填充里程计数据
    odom_pub.publish(odom)
```

---

## 📊 调试步骤

### 1. 验证地图

```bash
# 查看地图话题
rostopic echo /projected_map --noarr

# 在 RViz 中添加 Map 显示
# Topic: /projected_map
```

### 2. 检查 TF 树

```bash
# 查看 TF 树
rosrun tf view_frames

# 应该看到: map -> odom -> base_link
```

### 3. 测试导航

```bash
# 发送简单的速度命令测试
rostopic pub /cmd_vel geometry_msgs/Twist "linear:
  x: 0.2
  y: 0.0
  z: 0.0
angular:
  x: 0.0
  y: 0.0
  z: 0.0"
```

---

## 🎯 下一步

1. **创建 TF 发布节点**: 将 ORB-SLAM3 位姿转换为 TF
2. **配置机器人参数**: 根据实际机器人调整参数
3. **实现速度控制接口**: 连接到机器人底盘
4. **调试导航**: 在 RViz 中测试路径规划

---

## 📚 参考资源

- [ROS Navigation Tuning Guide](http://wiki.ros.org/navigation/Tutorials/Navigation%20Tuning%20Guide)
- [move_base Documentation](http://wiki.ros.org/move_base)
- [costmap_2d Documentation](http://wiki.ros.org/costmap_2d)

---

**注意**: 由于您的系统使用视觉SLAM，地图是实时更新的。建议：
1. 先在静态环境中测试
2. 确保地图质量稳定
3. 考虑添加地图保存/加载功能

如需帮助创建具体的配置文件和节点，请告诉我您的机器人具体参数。
