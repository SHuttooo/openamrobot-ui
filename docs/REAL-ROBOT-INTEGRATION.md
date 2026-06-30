# Running the UI against the real robot (OpenAMRobot)

How to connect this UI to the **real** robot (the `openamr-platform-sw` stack on
the Raspberry Pi), not the simulation. The UI does **not** start Nav2 / the map
server / docking — it connects to the robot stack that is already running.

> **TL;DR order:** (1) start the robot stack on the Pi → (2) start the UI with
> the **same DDS + domain as the robot** → (3) open `http://<robot-ip>:5050/control`.

---

## 0. ⚠️ The one gotcha that silently breaks everything: DDS + domain

The UI's `rosbridge` is a normal ROS 2 node. It only sees the robot's topics if
it uses the **same RMW implementation and `ROS_DOMAIN_ID`** as the robot.

This robot runs **CycloneDDS on domain 0**. But `docker-compose.yml` defaults to
`rmw_fastrtps_cpp` — with that default the UI connects to rosbridge fine yet
**sees zero robot topics** (FastDDS and CycloneDDS do not talk to each other).

**Always launch the UI with:**

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
```

For Docker, put them in a `.env` next to `docker-compose.yml` (it already reads
`${RMW_IMPLEMENTATION}` / `${ROS_DOMAIN_ID}`):

```dotenv
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ROS_DOMAIN_ID=0
```

Symptom if this is wrong: UI says "ROS connected" (rosbridge is up) but every
panel is empty (no map, no pose, no camera, no nav status).

---

## 1. Start the robot stack (on the Pi)

```bash
ssh botshare@172.17.201.29
source /opt/ros/jazzy/setup.bash
source ~/linorobot2_ws/install/setup.bash
source ~/openamr-platform-sw/ros2/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
ros2 launch openamrobot_bringup bringup.launch.py \
     map:=/home/botshare/maps/piece_actuelle.yaml use_docking:=true
```

Then set the initial pose once with RViz "2D Pose Estimate" (or the UI, see below)
so AMCL gives `map -> odom` and the costmaps fill.

## 2. Start the UI

The UI runs **on the Pi** (so the browser reaches it at the Pi's IP), or on a PC
that shares the robot's DDS/domain. Two ways:

**Docker (recommended)** — with the `.env` above:

```bash
cd ~/openamrobot-ui
docker compose up --build
```

**Manual (ROS 2 launch):**

```bash
source /opt/ros/jazzy/setup.bash
source ~/openamrobot-ui/ros2/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=0
ros2 launch openamr_ui_bringup ui.launch.py
```

This starts: the Flask server (serves the React app on **:5050**), `rosbridge`
(**:9090**), `web_video_server` (camera MJPEG on **:8080**), `rosapi`, and the
QoS relay nodes (`/ui/map`, `/ui/amcl_pose`, `/ui/navigate_to_pose/status`).

## 3. Open the dashboard

```
http://<robot-ip>:5050/control      # e.g. http://172.17.201.29:5050/control
```

When you browse to the robot's IP, the app auto-points rosbridge and the camera
stream at that same host (`window.location.hostname`), so no IP editing is
needed for the deployed case. Confirm the header shows **ROS connected** before
driving or sending goals.

---

## What already works (verified topic match with the robot)

The UI's topic/service interface matches `openamr-platform-sw` **exactly** — no
remapping needed:

| Function | Topic / service | Type | Direction |
|---|---|---|---|
| Send nav goal | `/goal_pose` | `geometry_msgs/PoseStamped` | UI → robot |
| Cancel nav | `/navigate_to_pose/_action/cancel_goal` | `action_msgs/CancelGoal` | UI → robot |
| Dock | `/dock_trigger` | `std_msgs/Bool` | UI → robot |
| Undock | `/undock_robot` | `std_msgs/Bool` | UI → robot |
| Dock status | `/dock_trigger_status` | `std_msgs/String` | robot → UI |
| Teleop / stop | `/cmd_vel` | `geometry_msgs/Twist` | UI → robot |
| Pose | `/amcl_pose` → `/ui/amcl_pose` | `PoseWithCovarianceStamped` | robot → UI (relay) |
| Map | `/map` → `/ui/map` | `nav_msgs/OccupancyGrid` | robot → UI (relay) |
| Nav status | `/navigate_to_pose/_action/status` → `/ui/...` | `GoalStatusArray` | robot → UI (relay) |
| Laser / health | `/scan_filtered`, `/odom`, `/tf` | — | robot → UI |
| Camera | `/camera/image_raw` | `sensor_msgs/Image` (MJPEG via web_video_server) | robot → UI |

The `/ui/*` relays exist because Nav2 publishes map/pose/status with
**TRANSIENT_LOCAL** QoS, which rosbridge cannot forward to the browser; the relay
nodes re-publish them as **VOLATILE**.

> Note: the platform-sw **on-demand AprilTag gate** sits between the camera and
> `apriltag_node` — it does **not** touch `/camera/image_raw`, so the UI camera
> panel works regardless of dock state.

---

## Robot-specific values to set for this deployment

These are the only deployment-specific spots (defaults are generic):

1. **Camera topic** — defaulted to `/camera/image_raw` (this robot). *(done)*
2. **Dev rosbridge IP** — `web/src/shared/constants/index.js`
   `ROSBRIDGE_SERVER_IP` (only used by `npm run dev` from a separate PC; the
   deployed `:5050` case auto-resolves). Set to `172.17.201.29` for PC dev.
3. **Standby pose after undock** — `web/src/components/DockingControl.jsx`
   (`STANDBY_POSE` ~line 6): set to a real free pose on the `piece_actuelle`
   map.
4. **Default named locations** — `ros2/.../openamr_ui_package/flask_app.py`
   (`DEFAULT_BLOCK_LOCATIONS`): replace the placeholder coords with real map
   coordinates (Home / Charging / Pickup / Dropoff).

## Prerequisites (ROS packages on the host that runs the UI)

`ros-jazzy-rosbridge-server`, `ros-jazzy-rosapi`, `ros-jazzy-web-video-server`
(the Docker image installs these).

## Troubleshooting

- **"ROS connected" but all panels empty** → DDS/domain mismatch (see §0). Verify
  `ros2 topic list` from the UI host shows the robot topics.
- **No camera** → `web_video_server` running? Topic correct (`/camera/image_raw`)?
  On the real robot the camera must be up (`use_camera:=true`, default).
- **No map** → the `map_relay` node must be running and the robot's `/map` must be
  published (map_server active after the 2D Pose Estimate).
- **No pose / nav status** → the `nav_relays` node must be running; AMCL active.
