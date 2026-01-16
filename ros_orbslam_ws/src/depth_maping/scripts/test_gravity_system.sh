#!/bin/bash

# 重力对齐系统测试脚本
# 用于验证位姿补偿的重力估计功能

echo "=========================================="
echo "  重力对齐系统测试"
echo "=========================================="
echo ""

# 获取脚本目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GE_DIR="${SCRIPT_DIR}/GE_information"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试函数
test_passed() {
    echo -e "${GREEN}✓${NC} $1"
}

test_failed() {
    echo -e "${RED}✗${NC} $1"
}

test_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. 检查目录结构
echo "1. 检查目录结构..."
if [ -d "$GE_DIR" ]; then
    test_passed "GE_information 目录存在"
else
    test_failed "GE_information 目录不存在"
    echo "   创建目录..."
    mkdir -p "$GE_DIR"
fi
echo ""

# 2. 检查 Python 环境
echo "2. 检查 Python 环境..."

# 检查 ROS Python (应该是 3.8)
ROS_PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+')
echo "   ROS Python 版本: $ROS_PYTHON_VERSION"
if [[ "$ROS_PYTHON_VERSION" == "3.8" ]]; then
    test_passed "ROS Python 版本正确 (3.8)"
else
    test_warning "ROS Python 版本不是 3.8，可能影响兼容性"
fi

# 检查 conda plato 环境
if conda env list | grep -q "plato"; then
    test_passed "Conda plato 环境存在"
    
    # 检查 plato 环境的 Python 版本
    PLATO_PYTHON_VERSION=$(conda run -n plato python --version 2>&1 | grep -oP '\d+\.\d+')
    echo "   Plato Python 版本: $PLATO_PYTHON_VERSION"
    
    if [[ "$PLATO_PYTHON_VERSION" > "3.8" ]]; then
        test_passed "Plato Python 版本 >= 3.9 (支持 GeoCalib)"
    else
        test_failed "Plato Python 版本 < 3.9 (不支持 GeoCalib)"
    fi
else
    test_failed "Conda plato 环境不存在"
    echo "   请创建 plato 环境: conda create -n plato python=3.9"
fi
echo ""

# 3. 检查依赖包
echo "3. 检查依赖包..."

# ROS 环境依赖
echo "   检查 ROS 依赖..."
python3 -c "import rospy" 2>/dev/null && test_passed "rospy" || test_failed "rospy"
python3 -c "import cv_bridge" 2>/dev/null && test_passed "cv_bridge" || test_failed "cv_bridge"
python3 -c "import sensor_msgs" 2>/dev/null && test_passed "sensor_msgs" || test_failed "sensor_msgs"

# Python 通用依赖
echo "   检查 Python 依赖..."
python3 -c "import numpy" 2>/dev/null && test_passed "numpy" || test_failed "numpy"
python3 -c "import cv2" 2>/dev/null && test_passed "opencv-python" || test_failed "opencv-python"
python3 -c "import torch" 2>/dev/null && test_passed "pytorch" || test_failed "pytorch"
python3 -c "import open3d" 2>/dev/null && test_passed "open3d" || test_failed "open3d"
python3 -c "import pypose" 2>/dev/null && test_passed "pypose" || test_failed "pypose"
python3 -c "import yaml" 2>/dev/null && test_passed "pyyaml" || test_failed "pyyaml"

# GeoCalib 依赖（在 plato 环境中）
echo "   检查 GeoCalib 依赖..."
if conda env list | grep -q "plato"; then
    conda run -n plato python -c "import geocalib" 2>/dev/null && test_passed "geocalib (plato)" || test_failed "geocalib (plato)"
    conda run -n plato python -c "import torch" 2>/dev/null && test_passed "pytorch (plato)" || test_failed "pytorch (plato)"
fi
echo ""

# 4. 检查文件权限
echo "4. 检查文件权限..."
if [ -w "$SCRIPT_DIR" ]; then
    test_passed "脚本目录可写"
else
    test_failed "脚本目录不可写"
fi

if [ -d "$GE_DIR" ] && [ -w "$GE_DIR" ]; then
    test_passed "GE_information 目录可写"
else
    test_failed "GE_information 目录不可写"
fi
echo ""

# 5. 检查现有数据
echo "5. 检查现有数据..."
IMG_COUNT=$(find "$GE_DIR" -name "img_*.png" 2>/dev/null | wc -l)
POSE_COUNT=$(find "$GE_DIR" -name "pose_*.json" 2>/dev/null | wc -l)
YAML_EXISTS=false
if [ -f "$GE_DIR/rotation_matrices.yaml" ]; then
    YAML_EXISTS=true
fi

echo "   图像文件数量: $IMG_COUNT"
echo "   位姿文件数量: $POSE_COUNT"

if [ "$IMG_COUNT" -gt 0 ]; then
    test_passed "发现 $IMG_COUNT 个图像文件"
else
    test_warning "未发现图像文件（系统尚未运行）"
fi

if [ "$POSE_COUNT" -gt 0 ]; then
    test_passed "发现 $POSE_COUNT 个位姿文件"
else
    test_warning "未发现位姿文件（系统尚未运行）"
fi

if [ "$YAML_EXISTS" = true ]; then
    test_passed "发现 rotation_matrices.yaml"
    
    # 检查 YAML 内容
    if grep -q "R_align" "$GE_DIR/rotation_matrices.yaml"; then
        test_passed "YAML 包含 R_align"
    else
        test_failed "YAML 不包含 R_align"
    fi
    
    # 显示最新时间戳
    TIMESTAMP=$(grep "timestamp:" "$GE_DIR/rotation_matrices.yaml" | head -1 | awk '{print $2}')
    if [ -n "$TIMESTAMP" ]; then
        echo "   最新时间戳: $TIMESTAMP"
    fi
else
    test_warning "未发现 rotation_matrices.yaml（重力估计尚未运行）"
fi
echo ""

# 6. 测试文件读写
echo "6. 测试文件读写..."
TEST_FILE="$GE_DIR/test_write.tmp"
if echo "test" > "$TEST_FILE" 2>/dev/null; then
    test_passed "文件写入测试通过"
    rm -f "$TEST_FILE"
else
    test_failed "文件写入测试失败"
fi
echo ""

# 7. 检查 ROS 环境
echo "7. 检查 ROS 环境..."
if [ -n "$ROS_DISTRO" ]; then
    test_passed "ROS 环境已配置 ($ROS_DISTRO)"
else
    test_warning "ROS 环境未配置"
    echo "   请运行: source /opt/ros/noetic/setup.bash"
fi

if [ -f "${SCRIPT_DIR}/../../../devel/setup.bash" ]; then
    test_passed "工作空间已编译"
else
    test_warning "工作空间未编译"
    echo "   请运行: cd ros_orbslam_ws && catkin_make"
fi
echo ""

# 8. 生成测试报告
echo "=========================================="
echo "  测试总结"
echo "=========================================="
echo ""

# 统计测试结果
TOTAL_TESTS=20
PASSED_TESTS=$(grep -c "✓" /tmp/test_output.txt 2>/dev/null || echo "0")

echo "系统状态："
echo "  - Python 环境: $([ "$ROS_PYTHON_VERSION" == "3.8" ] && echo "✓" || echo "✗") ROS (3.8) | $(conda env list | grep -q "plato" && echo "✓" || echo "✗") Plato (3.9+)"
echo "  - 依赖包: $(python3 -c "import rospy, cv2, torch, open3d, pypose, yaml" 2>/dev/null && echo "✓ 完整" || echo "✗ 缺失")"
echo "  - 数据文件: $IMG_COUNT 图像 | $POSE_COUNT 位姿 | $([ "$YAML_EXISTS" = true ] && echo "✓" || echo "✗") 对齐矩阵"
echo ""

# 9. 提供下一步建议
echo "下一步操作："
echo ""

if [ "$IMG_COUNT" -eq 0 ] && [ "$POSE_COUNT" -eq 0 ]; then
    echo "1. 启动完整系统："
    echo "   cd ros_orbslam_ws"
    echo "   ./launch.sh"
    echo "   选择模式 1（完整系统 + 重力估计）"
    echo ""
elif [ "$YAML_EXISTS" = false ]; then
    echo "1. 系统正在运行，等待重力估计完成..."
    echo "   监控命令: watch -n 1 ls -lh $GE_DIR"
    echo ""
else
    echo "✓ 系统运行正常！"
    echo ""
    echo "监控命令："
    echo "  - 查看重力估计日志: tail -f gravity_estimate.log"
    echo "  - 查看对齐矩阵: cat $GE_DIR/rotation_matrices.yaml"
    echo "  - 监控文件更新: watch -n 1 ls -lht $GE_DIR"
    echo ""
fi

echo "详细文档："
echo "  - 使用指南: ros_orbslam_ws/src/depth_maping/docs/gravity_alignment_guide.md"
echo "  - 故障排查: 参见文档中的「故障排查」章节"
echo ""

echo "=========================================="
echo "  测试完成"
echo "=========================================="