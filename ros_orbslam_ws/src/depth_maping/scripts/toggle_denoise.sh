#!/bin/bash

# 点云去噪功能开关脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NODE_FILE="${SCRIPT_DIR}/depth_maping_node.py"

echo "=========================================="
echo "  点云去噪功能开关"
echo "=========================================="
echo ""

# 检查当前状态
if grep -q "point_cloud = self.denoise_point_cloud(point_cloud)" "$NODE_FILE"; then
    CURRENT_STATE="启用"
else
    CURRENT_STATE="禁用"
fi

echo "当前状态: $CURRENT_STATE"
echo ""
echo "选择操作:"
echo "  1) 禁用去噪（恢复原始点云）"
echo "  2) 启用去噪（温和模式）"
echo "  3) 启用去噪（激进模式）"
echo "  4) 查看当前参数"
echo "  5) 退出"
echo ""
read -p "请选择 [1-5]: " choice

case $choice in
    1)
        echo "禁用点云去噪..."
        # 注释掉去噪调用
        sed -i 's/point_cloud = self.denoise_point_cloud(point_cloud)/#point_cloud = self.denoise_point_cloud(point_cloud)  # 已禁用/g' "$NODE_FILE"
        sed -i 's/self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)/#self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)  # 已禁用/g' "$NODE_FILE"
        echo "✓ 去噪功能已禁用"
        ;;
    2)
        echo "启用去噪（温和模式）..."
        # 取消注释
        sed -i 's/#point_cloud = self.denoise_point_cloud(point_cloud)  # 已禁用/point_cloud = self.denoise_point_cloud(point_cloud)/g' "$NODE_FILE"
        sed -i 's/#self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)  # 已禁用/self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)/g' "$NODE_FILE"
        # 设置温和参数
        sed -i 's/std_ratio=[0-9.]\+/std_ratio=3.0/g' "$NODE_FILE"
        sed -i 's/nb_points=[0-9]\+, radius=[0-9.]\+/nb_points=10, radius=0.2/g' "$NODE_FILE"
        echo "✓ 去噪功能已启用（温和模式）"
        echo "  - 统计滤波: std_ratio=3.0"
        echo "  - 半径滤波: nb_points=10, radius=0.2"
        ;;
    3)
        echo "启用去噪（激进模式）..."
        # 取消注释
        sed -i 's/#point_cloud = self.denoise_point_cloud(point_cloud)  # 已禁用/point_cloud = self.denoise_point_cloud(point_cloud)/g' "$NODE_FILE"
        sed -i 's/#self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)  # 已禁用/self.all_point_cloud = self.denoise_point_cloud(self.all_point_cloud)/g' "$NODE_FILE"
        # 设置激进参数
        sed -i 's/std_ratio=[0-9.]\+/std_ratio=2.0/g' "$NODE_FILE"
        sed -i 's/nb_points=[0-9]\+, radius=[0-9.]\+/nb_points=16, radius=0.1/g' "$NODE_FILE"
        echo "✓ 去噪功能已启用（激进模式）"
        echo "  - 统计滤波: std_ratio=2.0"
        echo "  - 半径滤波: nb_points=16, radius=0.1"
        ;;
    4)
        echo "当前参数:"
        echo ""
        echo "统计滤波:"
        grep -A 2 "remove_statistical_outlier" "$NODE_FILE" | grep "nb_neighbors"
        echo ""
        echo "半径滤波:"
        grep -A 2 "remove_radius_outlier" "$NODE_FILE" | grep "nb_points"
        echo ""
        echo "深度阈值:"
        grep "valid_mask.*depth_cropped" "$NODE_FILE" | head -1
        ;;
    5)
        echo "退出"
        exit 0
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  修改完成"
echo "=========================================="
echo ""
echo "重启节点以应用更改:"
echo "  1. 停止当前运行的节点 (Ctrl+C)"
echo "  2. 重新运行: ./launch.sh"
echo ""