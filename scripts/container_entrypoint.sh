#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/workspace"
ROS_DISTRO="${ROS_DISTRO:-jazzy}"

# ROS setup scripts reference unset vars (AMENT_TRACE_SETUP_FILES, ...). With
# `set -u` that aborts the entrypoint (container exits 1 and restart-loops), so
# relax nounset just around the sourcing.
set +u
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u
cd "${REPO_ROOT}"

if [ "${OPENAMR_REBUILD_ON_START:-0}" = "1" ]; then
  bash scripts/build_frontend.sh
  bash scripts/sync_frontend_to_ros.sh
  bash scripts/build_ros.sh
fi

set +u
source "${REPO_ROOT}/ros2/install/setup.bash"
set -u
exec ros2 launch openamr_ui_bringup ui.launch.py
