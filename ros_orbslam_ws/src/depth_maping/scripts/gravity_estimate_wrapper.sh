#!/bin/bash
# Gravity Estimate 包装脚本
# 用于在 roslaunch 中启动需要 conda 环境的 Python 脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 激活 conda 环境并运行 gravity_estimate.py
conda run -n plato python "$SCRIPT_DIR/gravity_estimate.py"