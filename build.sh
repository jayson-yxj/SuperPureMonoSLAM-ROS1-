#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ORB-SLAM3 项目构建脚本${NC}"
echo -e "${GREEN}========================================${NC}"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 函数：检测并删除 build 目录
clean_build_dir() {
    local build_path=$1
    local dir_name=$2
    
    if [ -d "$build_path" ]; then
        echo -e "${YELLOW}检测到 $dir_name 目录存在，正在删除...${NC}"
        rm -rf "$build_path"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ $dir_name 目录删除成功${NC}"
        else
            echo -e "${RED}✗ $dir_name 目录删除失败${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}$dir_name 目录不存在，跳过删除${NC}"
    fi
}

# 函数：创建并进入 build 目录
create_and_enter_build() {
    local build_path=$1
    local dir_name=$2
    
    echo -e "${YELLOW}创建 $dir_name 目录...${NC}"
    mkdir -p "$build_path"
    cd "$build_path"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 进入 $dir_name 目录${NC}"
    else
        echo -e "${RED}✗ 无法进入 $dir_name 目录${NC}"
        exit 1
    fi
}

# 1. 构建 Thirdparty/DBoW2
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}步骤 1: 构建 DBoW2${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR/Thirdparty/DBoW2"
clean_build_dir "build" "DBoW2/build"
create_and_enter_build "build" "DBoW2/build"

echo -e "${YELLOW}运行 cmake...${NC}"
cmake .. -DCMAKE_BUILD_TYPE=Release
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ DBoW2 cmake 失败${NC}"
    exit 1
fi

echo -e "${YELLOW}运行 make...${NC}"
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ DBoW2 编译失败${NC}"
    exit 1
fi

echo -e "${GREEN}✓ DBoW2 构建成功${NC}"

# 2. 构建 Thirdparty/g2o
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}步骤 2: 构建 g2o${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR/Thirdparty/g2o"
clean_build_dir "build" "g2o/build"
create_and_enter_build "build" "g2o/build"

echo -e "${YELLOW}运行 cmake...${NC}"
cmake .. -DCMAKE_BUILD_TYPE=Release
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ g2o cmake 失败${NC}"
    exit 1
fi

echo -e "${YELLOW}运行 make...${NC}"
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ g2o 编译失败${NC}"
    exit 1
fi

echo -e "${GREEN}✓ g2o 构建成功${NC}"

# 3. 构建 Thirdparty/Sophus
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}步骤 3: 构建 Sophus${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR/Thirdparty/Sophus"
clean_build_dir "build" "Sophus/build"
create_and_enter_build "build" "Sophus/build"

echo -e "${YELLOW}运行 cmake...${NC}"
cmake .. -DCMAKE_BUILD_TYPE=Release
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Sophus cmake 失败${NC}"
    exit 1
fi

echo -e "${YELLOW}运行 make...${NC}"
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Sophus 编译失败${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Sophus 构建成功${NC}"

# 4. 构建 ORB-SLAM3 主库
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}步骤 4: 构建 ORB-SLAM3 主库${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR"
clean_build_dir "build" "ORB-SLAM3/build"
create_and_enter_build "build" "ORB-SLAM3/build"

echo -e "${YELLOW}运行 cmake...${NC}"
cmake .. -DCMAKE_BUILD_TYPE=Release
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ ORB-SLAM3 cmake 失败${NC}"
    exit 1
fi

echo -e "${YELLOW}运行 make...${NC}"
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ ORB-SLAM3 编译失败${NC}"
    exit 1
fi

echo -e "${GREEN}✓ ORB-SLAM3 主库构建成功${NC}"

# 5. 构建 ROS 工作空间
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}步骤 5: 构建 ROS 工作空间${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR/ros_orbslam_ws"

# 检查是否存在 src 目录
if [ ! -d "src" ]; then
    echo -e "${YELLOW}未找到 src 目录，跳过 ROS 工作空间构建${NC}"
else
    clean_build_dir "build" "ROS/build"
    clean_build_dir "devel" "ROS/devel"
    
    echo -e "${YELLOW}运行 catkin_make...${NC}"
    catkin_make
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ ROS 工作空间构建失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ ROS 工作空间构建成功${NC}"
fi

# 构建完成
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ 所有构建步骤完成！${NC}"
echo -e "${GREEN}========================================${NC}"

cd "$SCRIPT_DIR"

echo -e "\n${YELLOW}提示：${NC}"
echo -e "  - ORB-SLAM3 库位于: ${GREEN}lib/libORB_SLAM3.so${NC}"
echo -e "  - 要运行 ROS 节点，请执行: ${GREEN}cd ros_orbslam_ws && ./run.sh${NC}"
echo -e "  - 或者手动 source: ${GREEN}source ros_orbslam_ws/devel/setup.bash${NC}"