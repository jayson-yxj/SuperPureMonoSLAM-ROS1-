#!/usr/bin/env python3
"""
Gravity Estimate 节点 - 基于位姿补偿的重力对齐
通过 ORB-SLAM3 位姿信息补偿时间延迟，实现准确的重力估计
"""
import torch
import cv2
import numpy as np
import os
import yaml
import json
import time
import glob

from geocalib import GeoCalib

# 获取当前文件路径
current_file_path = os.path.abspath(__file__)
current_folder = os.path.dirname(current_file_path)

# 设备和模型初始化
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"🚀 Gravity Estimate 启动（位姿补偿版本）")
print(f"📍 设备: {device}")

model = GeoCalib(weights="distorted").to(device)
print("✓ GeoCalib 模型已加载")

# 目录设置
ge_info_dir = f"{current_folder}/GE_information"
if not os.path.exists(ge_info_dir):
    os.makedirs(ge_info_dir)
    print(f"✓ 创建目录: {ge_info_dir}")

# 配置参数
estimate_interval = 0.1  # 每n秒估计一次
pose_jump_threshold = 1.0  # 位姿跳变阈值（米）


def compute_alignment_matrix(g_w):
    """
    计算将重力向量对齐到 [0, -1, 0] 的旋转矩阵
    
    Args:
        g_w: 世界坐标系下的重力向量 (3,)
    
    Returns:
        R_align: 对齐旋转矩阵 (3, 3)
    """
    g_w = g_w / np.linalg.norm(g_w)  # 归一化
    
    # 目标方向（重力向下，Y轴负方向）
    target = np.array([0, 0, 1])
    
    # 如果已经对齐，返回单位矩阵
    if np.allclose(g_w, target, atol=1e-6):
        print("  重力已对齐，无需旋转")
        return np.eye(3)
    
    # 旋转轴：g_w × target
    axis = np.cross(g_w, target)
    axis_norm = np.linalg.norm(axis)
    
    if axis_norm < 1e-6:
        # g_w 和 target 平行（可能反向）
        if np.dot(g_w, target) < 0:
            # 反向，需要180度旋转
            # 选择一个垂直于 target 的轴
            if abs(target[0]) < 0.9:
                axis = np.array([1, 0, 0])
            else:
                axis = np.array([0, 0, 1])
            angle = np.pi
        else:
            return np.eye(3)
    else:
        axis = axis / axis_norm
        # 旋转角度
        angle = np.arccos(np.clip(np.dot(g_w, target), -1.0, 1.0))
    
    # Rodrigues 公式构建旋转矩阵
    K = np.array([
        [0, -axis[2], axis[1]],
        [axis[2], 0, -axis[0]],
        [-axis[1], axis[0], 0]
    ])
    
    R_align = np.eye(3) + np.sin(angle) * K + (1 - np.cos(angle)) * (K @ K)
    
    print(f"  旋转角度: {np.degrees(angle):.2f}°")
    print(f"  旋转轴: [{axis[0]:.3f}, {axis[1]:.3f}, {axis[2]:.3f}]")
    
    return R_align


def estimate_and_save_gravity(image_path, pose_data):
    """
    估计重力方向并计算对齐矩阵
    
    Args:
        image_path: 图像文件路径
        pose_data: 位姿数据字典 {R_cw, t_cw, timestamp, frame_id}
    
    Returns:
        bool: 是否成功
    """
    try:
        # 读取图像
        img = cv2.imread(image_path)
        if img is None:
            print(f"✗ 无法读取图像: {image_path}")
            return False
        
        # 预处理图像
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img_rgb = cv2.resize(img_rgb, (640, 480))
        img_tensor = torch.from_numpy(img_rgb).permute(2, 0, 1).unsqueeze(0).float().to(device) / 255.0
        
        # 估计相机坐标系下的重力
        results = model.calibrate(img_tensor)
        g_c = results["gravity"][0].cpu().numpy()
        
        print(f"  相机坐标系重力: gx={g_c[0]:.4f}, gy={g_c[1]:.4f}, gz={g_c[2]:.4f}")
        
        # 获取 ORB-SLAM3 位姿
        R_cw = np.array(pose_data['R_cw'])
        t_cw = np.array(pose_data['t_cw'])
        
        # 转换到世界坐标系
        R_wc = R_cw.T
        g_w_slam = R_wc @ g_c
        
        print(f"  世界坐标系重力: gx={g_w_slam[0]:.4f}, gy={g_w_slam[1]:.4f}, gz={g_w_slam[2]:.4f}")
        
        # 计算对齐旋转矩阵
        R_align = compute_alignment_matrix(g_w_slam)
        
        # 验证对齐结果
        g_aligned = R_align @ g_w_slam
        print(f"  对齐后重力: gx={g_aligned[0]:.4f}, gy={g_aligned[1]:.4f}, gz={g_aligned[2]:.4f}")
        print(f"  对齐误差: {np.linalg.norm(g_aligned - np.array([0, -1, 0])):.6f}")
        
        # 保存到 YAML
        data_to_save = {
            'R_align': R_align.tolist(),
            'R_cw': R_cw.tolist(),
            'R_wc': R_wc.tolist(),
            'g_c': g_c.tolist(),
            'g_w_slam': g_w_slam.tolist(),
            'g_aligned': g_aligned.tolist(),
            'timestamp': pose_data['timestamp'],
            'frame_id': pose_data.get('frame_id', 0)
        }
        
        yaml_path = f"{ge_info_dir}/rotation_matrices.yaml"
        with open(yaml_path, 'w') as file:
            yaml.dump(data_to_save, file)
        
        print(f"✓ 重力估计完成")
        print(f"✓ 对齐矩阵已更新: {yaml_path}")
        
        return True
        
    except Exception as e:
        print(f"✗ 重力估计失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def get_latest_pose_data():
    """
    获取最新的位姿数据文件（使用固定文件名）
    
    Returns:
        tuple: (image_path, pose_data, mtime) 或 (None, None, None)
    """
    # 使用固定文件名
    pose_file = f"{ge_info_dir}/latest_pose.json"
    
    if not os.path.exists(pose_file):
        return None, None, None
    
    try:
        # 获取文件修改时间
        mtime = os.path.getmtime(pose_file)
        
        with open(pose_file, 'r') as f:
            pose_data = json.load(f)
        
        image_path = pose_data.get('image_path')
        if image_path and os.path.exists(image_path):
            return image_path, pose_data, mtime
        else:
            print(f"⚠️  图像文件不存在: {image_path}")
            return None, None, None
            
    except Exception as e:
        print(f"✗ 读取位姿文件失败: {e}")
        return None, None, None


def detect_pose_jump(current_pose, previous_pose):
    """
    检测位姿跳变（ORB-SLAM3 重新初始化）
    
    Args:
        current_pose: 当前位姿数据
        previous_pose: 上一次位姿数据
    
    Returns:
        bool: 是否发生跳变
    """
    if previous_pose is None:
        return True
    
    # 计算位置差异
    t_current = np.array(current_pose['t_cw'])
    t_previous = np.array(previous_pose['t_cw'])
    t_diff = np.linalg.norm(t_current - t_previous)
    
    # 如果位移过大，认为是重新初始化
    if t_diff > pose_jump_threshold:
        print(f"⚠️  检测到位姿跳变: Δt = {t_diff:.3f}m > {pose_jump_threshold}m")
        return True
    
    return False


def main():
    """主循环"""
    last_process_time = 0
    last_pose_data = None
    last_file_mtime = 0  # 记录上次处理的文件修改时间
    
    print(f"⏱️  更新频率: 每 {estimate_interval} 秒")
    print(f"📂 监控目录: {ge_info_dir}")
    print(f"📄 监控文件: latest_pose.json, latest_img.png")
    print("🔁 开始定期重力估计...")
    
    # 等待第一个位姿数据
    print("⏳ 等待位姿数据...")
    while True:
        image_path, pose_data, mtime = get_latest_pose_data()
        if image_path and pose_data:
            print(f"✓ 发现位姿数据: frame_{pose_data.get('frame_id', 0)}")
            last_file_mtime = mtime
            break
        time.sleep(0.5)
    
    # 立即进行第一次估计
    print("🔄 执行初始重力估计...")
    if estimate_and_save_gravity(image_path, pose_data):
        last_process_time = time.time()
        last_pose_data = pose_data
        print("✓ 初始重力估计完成\n")
    else:
        print("✗ 初始重力估计失败\n")
    
    # 主循环：定期重新估计
    print(f"🔁 开始定期重力估计（监控文件更新）...\n")
    
    try:
        while True:
            current_time = time.time()
            
            # 检查是否需要重新估计（基于时间间隔）
            if current_time - last_process_time >= estimate_interval:
                image_path, pose_data, mtime = get_latest_pose_data()
                
                if image_path and pose_data and mtime:
                    # 检查文件是否已更新（修改时间变化）
                    if mtime > last_file_mtime:
                        frame_id = pose_data.get('frame_id', 0)
                        print(f"🔄 检测到新数据，执行重力估计... (frame_{frame_id})")
                        
                        # 检测位姿跳变
                        if detect_pose_jump(pose_data, last_pose_data):
                            print("  → 位姿跳变，重新计算对齐矩阵")
                        
                        # 估计重力
                        if estimate_and_save_gravity(image_path, pose_data):
                            last_process_time = current_time
                            last_pose_data = pose_data
                            last_file_mtime = mtime
                            print()  # 空行分隔
                    else:
                        # 文件未更新，跳过（不打印日志，避免刷屏）
                        pass
                else:
                    print("⚠️  无可用位姿数据，跳过本次估计")
                    last_process_time = current_time
            
            time.sleep(0.1)  # 100ms 检查间隔
            
    except KeyboardInterrupt:
        print("\n👋 Gravity Estimate 已停止")
    except Exception as e:
        print(f"✗ 运行出错: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()