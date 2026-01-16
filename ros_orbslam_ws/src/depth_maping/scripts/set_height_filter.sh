#!/bin/bash

# ============================================
# 点云高度过滤快速配置工具
# ============================================

echo "=========================================="
echo "  点云高度过滤配置工具"
echo "=========================================="
echo ""

# 检查 ROS 节点是否运行
if ! rosnode list | grep -q "/depth_maping_node"; then
    echo "❌ 错误: depth_maping_node 未运行"
    echo "   请先启动系统: cd ros_orbslam_ws && ./launch.sh"
    exit 1
fi

echo "当前配置："
echo "  启用状态: $(rosparam get /depth_maping_node/enable_height_filter 2>/dev/null || echo '未设置')"
echo "  过滤模式: $(rosparam get /depth_maping_node/height_filter_mode 2>/dev/null || echo '未设置')"

mode=$(rosparam get /depth_maping_node/height_filter_mode 2>/dev/null || echo 'relative')
if [ "$mode" = "relative" ]; then
    echo "  高度比例: $(rosparam get /depth_maping_node/height_ratio_min 2>/dev/null || echo '未设置') ~ $(rosparam get /depth_maping_node/height_ratio_max 2>/dev/null || echo '未设置')"
else
    echo "  高度范围: $(rosparam get /depth_maping_node/height_min 2>/dev/null || echo '未设置')m ~ $(rosparam get /depth_maping_node/height_max 2>/dev/null || echo '未设置')m"
fi
echo ""

echo "请选择预设配置："
echo "  === 相对模式（推荐用于单目SLAM） ==="
echo "  1) 禁用高度过滤（显示所有点云）"
echo "  2) 标准过滤（保留中间60%）【推荐】"
echo "  3) 轻度过滤（保留中间80%）"
echo "  4) 严格过滤（保留中间40%）"
echo "  5) 只保留中间层（保留中间30%）"
echo "  6) 自定义百分比"
echo ""
echo "  === 绝对模式（用于已知尺度场景） ==="
echo "  7) 标准室内（-2.0m ~ 3.0m）"
echo "  8) 自定义绝对范围"
echo ""

read -p "请输入选项 [1-8]: " choice

case $choice in
    1)
        echo "禁用高度过滤..."
        rosparam set /depth_maping_node/enable_height_filter false
        ;;
    2)
        echo "设置为标准过滤（保留中间60%）..."
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode relative
        rosparam set /depth_maping_node/height_ratio_min 0.2
        rosparam set /depth_maping_node/height_ratio_max 0.8
        ;;
    3)
        echo "设置为轻度过滤（保留中间80%）..."
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode relative
        rosparam set /depth_maping_node/height_ratio_min 0.1
        rosparam set /depth_maping_node/height_ratio_max 0.9
        ;;
    4)
        echo "设置为严格过滤（保留中间40%）..."
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode relative
        rosparam set /depth_maping_node/height_ratio_min 0.3
        rosparam set /depth_maping_node/height_ratio_max 0.7
        ;;
    5)
        echo "设置为只保留中间层（保留中间30%）..."
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode relative
        rosparam set /depth_maping_node/height_ratio_min 0.35
        rosparam set /depth_maping_node/height_ratio_max 0.65
        ;;
    6)
        echo "自定义百分比范围："
        echo "  提示：0.0 = 最低点，1.0 = 最高点"
        read -p "  最小百分比（如 0.2 表示过滤掉最低20%）: " ratio_min
        read -p "  最大百分比（如 0.8 表示过滤掉最高20%）: " ratio_max
        
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode relative
        rosparam set /depth_maping_node/height_ratio_min $ratio_min
        rosparam set /depth_maping_node/height_ratio_max $ratio_max
        ;;
    7)
        echo "设置为标准室内（绝对模式）..."
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode absolute
        rosparam set /depth_maping_node/height_min -2.0
        rosparam set /depth_maping_node/height_max 3.0
        ;;
    8)
        echo "自定义绝对高度范围："
        read -p "  最低高度 (m): " min_height
        read -p "  最高高度 (m): " max_height
        
        rosparam set /depth_maping_node/enable_height_filter true
        rosparam set /depth_maping_node/height_filter_mode absolute
        rosparam set /depth_maping_node/height_min $min_height
        rosparam set /depth_maping_node/height_max $max_height
        ;;
    *)
        echo "❌ 无效选项"
        exit 1
        ;;
esac

echo ""
echo "✅ 配置已更新："
echo "  启用状态: $(rosparam get /depth_maping_node/enable_height_filter)"
echo "  过滤模式: $(rosparam get /depth_maping_node/height_filter_mode)"

mode=$(rosparam get /depth_maping_node/height_filter_mode)
if [ "$mode" = "relative" ]; then
    min=$(rosparam get /depth_maping_node/height_ratio_min)
    max=$(rosparam get /depth_maping_node/height_ratio_max)
    echo "  高度比例: ${min} ~ ${max}"
    
    # 计算过滤百分比
    filter_bottom=$(echo "scale=1; $min * 100" | bc)
    filter_top=$(echo "scale=1; (1 - $max) * 100" | bc)
    keep=$(echo "scale=1; ($max - $min) * 100" | bc)
    
    echo ""
    echo "📊 过滤效果："
    echo "  - 过滤掉最低 ${filter_bottom}% 的点（地面）"
    echo "  - 过滤掉最高 ${filter_top}% 的点（天花板）"
    echo "  - 保留中间 ${keep}% 的点"
else
    echo "  高度范围: $(rosparam get /depth_maping_node/height_min)m ~ $(rosparam get /depth_maping_node/height_max)m"
fi

echo ""
echo "⚠️  注意: 参数已更新，等待新的点云帧生效（1-2秒）"
echo ""
echo "💡 提示: 在 RViz 中观察 /o3d_pointCloud 话题查看效果"