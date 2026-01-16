cmake_minimum_required(VERSION 3.0.2)
project(robot_navigation)

find_package(catkin REQUIRED COMPONENTS
  rospy
  roscpp
  std_msgs
  geometry_msgs
  nav_msgs
  sensor_msgs
  tf
  tf2_ros
  move_base
  costmap_2d
)

catkin_package(
  CATKIN_DEPENDS 
    rospy 
    roscpp 
    std_msgs 
    geometry_msgs 
    nav_msgs 
    sensor_msgs 
    tf 
    tf2_ros
    move_base
    costmap_2d
)

include_directories(
  ${catkin_INCLUDE_DIRS}
)

# 安装 launch 文件
install(DIRECTORY launch/
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/launch
)

# 安装参数文件
install(DIRECTORY params/
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/params
)

# 安装配置文件
install(DIRECTORY config/
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/config
)
