# FishBot 机器人 Gazebo Sim 仿真 · SLAM 建图 · 定位 · 路径规划 · 自主导航 全流程教程

> 面向初学者：从零开始，按本文顺序复制命令即可完成
> 「Gazebo Sim 仿真 → SLAM 实时建图 → 保存地图 → AMCL 定位 → 路径规划 → 自主导航」完整流程。
>
> 环境：Ubuntu 22.04 + ROS 2 Humble + **Gazebo Sim（Ignition Fortress 6）**
> 机器人：FishBot（两轮差速底盘 + 被动万向支撑轮 + 单线激光雷达 + IMU）

---

## 零、先读：本教程用的是哪套 Gazebo？

Gazebo 有两代产品，名字很容易混，务必先分清楚：

| | **Gazebo Classic**（旧） | **Gazebo Sim**（新，本教程采用） |
|---|---|---|
| 版本 | 11.x | Fortress 6.x（原 Ignition Gazebo） |
| 启动命令 | `gazebo` / `gzserver` / `gzclient` | **`ign gazebo`** |
| 与 ROS 通信 | 插件**直连** ROS 2（`gazebo_ros`），无需桥接 | 插件只说 **gz 话题**，必须用 **`ros_gz_bridge` 桥接** |
| 差速插件 | `libgazebo_ros_diff_drive.so` | `ignition-gazebo-diff-drive-system` |
| 雷达 | `<sensor type="ray">`（**CPU 计算**） | `<sensor type="gpu_lidar">`（**走 GPU 渲染，无 3D 时自动退化为软件渲染**） |
| 你的其它项目 | | ✅ 与本教程一致（都用 `ign gazebo` + bridge） |

> 💡 **关于雷达渲染**：Gazebo Sim 的雷达是 GPU 渲染型。**即使虚拟机没开硬件 3D 加速也能用**——
> Gazebo Sim 会自动退化为 **Mesa 软件渲染（llvmpipe/swrast）**，雷达照样出数据（实测 `ranges` 正常）。
> 代价是**启动较慢**：传感器渲染线程初始化约需 15 秒左右才会开始出 `/scan`，且 CPU 占用偏高。
> - 有硬件 3D：更快。
> - 无硬件 3D（如未开 3D 加速的 VMware/VirtualBox）：可用，但慢。
> - 若长时间（>30 秒）仍无 `/scan`，再排查渲染，见 [八、常见问题 FAQ](#八常见问题-faq) 第 1 条。

---

## 一、项目梳理总结

### 1.1 这个项目是什么

本项目是《动手学 ROS2》配套代码（Fork 自鱼香 ROS 的 `ros2bookcode`）的**第 9 章 FishBot 机器人工程**，目标是在
**Gazebo Sim 仿真环境**中，用一套标准 ROS 2 工具链完成移动机器人的经典全流程：

```
Gazebo Sim 仿真   →   SLAM 建图   →   保存地图   →   AMCL 定位   →   路径规划   →   自主导航
（ign gazebo        （slam_toolbox）  （map_saver）  （nav2_amcl）   （navfn/DWB）   （bt_navigator）
  + ros_gz_bridge）
```

### 1.2 工作空间目录结构

工程实际位于（本机路径）：

```
/home/heu402/fishbot_ws/src/ros2bookcode/chapt9/fishbot_ws/     ← 这就是 ROS 2 工作空间根目录
├── src/
│   ├── fishbot_description/      # 机器人 URDF 模型（车体/轮子/雷达/IMU + Gazebo Sim 插件）
│   │   └── urdf/fishbot.urdf
│   ├── fishbot_bringup/          # 仿真启动、世界文件、桥接、真机 bringup
│   │   ├── launch/fishbot_gazebo.launch.py      # 【核心】Gazebo Sim 仿真启动
│   │   ├── launch/fishbot_bridge.launch.py      # 【核心】ros_gz_bridge 话题桥接
│   │   ├── launch/bringup.launch.py             # 真机（雷达/串口/ros 代理）启动
│   │   ├── launch/urdf2tf.launch.py             # URDF → TF
│   │   ├── worlds/fishbot_world.world           # 【核心】仿真房间世界
│   │   ├── map/room.pgm|.yaml
│   │   └── src/odom2tf.cpp                      # odom 话题 → TF 广播（真机用）
│   ├── fishbot_navigation2/      # 建图与导航
│   │   ├── launch/fishbot_slam.launch.py        # 【核心】slam_toolbox 建图
│   │   ├── launch/fishbot_nav.launch.py         # 【核心】Nav2 导航入口
│   │   ├── launch/navigation2.launch.py         # Nav2 启动（被上者引用）
│   │   ├── config/slam_toolbox.yaml             # SLAM 参数
│   │   ├── config/nav2_params.yaml              # Nav2 全套参数（AMCL/代价地图/DWB…）
│   │   └── maps/room.pgm|.yaml                  # 地图（建图后保存到这里）
│   ├── ydlidar_ros2/             # YDLidar 雷达驱动（真机用）
│   └── ros_serial2wifi/          # 串口转 WiFi（真机用）
└── install/  build/  log/        # colcon 编译产物
```

### 1.3 原有内容 vs 本次补充

| 模块 | 原仓库状态 | 本次工作 |
|------|-----------|---------|
| `fishbot_description/urdf/fishbot.urdf` | 只有 `base_footprint` / `base_link` / `laser_link`，**无轮子、无惯性、无仿真插件**，无法仿真 | ✅ 补全车体/左右驱动轮/万向轮/雷达/IMU（含惯量），并加入 Gazebo Sim 三大 system 插件：差速驱动、雷达（gpu_lidar）、IMU |
| Gazebo 世界 | **不存在** | ✅ 新增 `fishbot_world.world`（5 m × 4 m 房间 + 3 个障碍物 + 必备 system 插件，SDF 1.9） |
| 仿真启动 | **不存在** | ✅ 新增 `fishbot_gazebo.launch.py`（`ign gazebo` 启动 + `ign service` 生成机器人） |
| gz↔ROS 桥接 | **不存在** | ✅ 新增 `fishbot_bridge.launch.py`（`ros_gz_bridge` 把 gz 话题桥接成 ROS 话题） |
| SLAM 建图 | **不存在** | ✅ 新增 `fishbot_slam.launch.py` + `slam_toolbox.yaml` |
| Nav2 导航 | 只有 `navigation2.launch.py` 且参数写法存在隐患 | ✅ 重写为健壮版本，新增 `fishbot_nav.launch.py` 入口，支持 `rviz:=`/`use_composition:=` 开关 |
| 地图 | 书里的旧地图（与本次世界不匹配） | ✅ 通过真实 SLAM 重新生成并保存 `maps/room.pgm|.yaml` |

### 1.4 系统数据流（理解这一点，后面就不会迷路）

Gazebo Sim 的关键差异：**仿真器与 ROS 之间隔着一条 bridge**。

```
                ROS 侧                                   │        Gazebo Sim 侧 (gz)
                                                        │
  /cmd_vel ──┐                                          │
  (遥控/Nav2)│   ┌──────────────────────────────────┐   │   ┌─────────────────────────────┐
             └──►│  ros_gz_bridge (parameter_bridge)│◄──┼──►│ ignition-gazebo-diff-drive  │
                 │   gz话题 <───► ROS话题 双向翻译     │   │   └──────────┬──────────────┘
  /scan   ◄──┐   └──────────────────────────────────┘   │              │ 驱动左右轮
  /odom   ◄──┤                                          │              ▼
  /imu    ◄──┤                                          │        Gazebo 物理引擎
  /tf     ◄──┘                                          │              │
                                                        │   ┌──────────┴────────────┐
  /scan ───────────────────────────────────────────────┼──►│ gpu_lidar 传感器        │  (GPU/软件渲染)
  /imu  ───────────────────────────────────────────────┼──►│ imu 传感器              │
                                                        │   └─────────────────────────┘

  建图阶段： /scan + /odom + TF ──► slam_toolbox ──► /map + TF(map→odom)
                                    └──► map_saver ──► room.pgm / room.yaml
  导航阶段： map_server 加载地图 → AMCL(/scan+TF) 估计位姿并发布 TF(map→odom)
             → planner_server 全局规划 → controller_server(DWB) 局部控制 → /cmd_vel →(bridge)→ 仿真
```

### 1.5 关键坐标系（TF 树）与话题

坐标系：`map` → `odom` → `base_footprint` → `base_link` → {`left_wheel_link`, `right_wheel_link`, `laser_link`, `imu_link`}

| ROS 话题 | 类型 | 方向 | 对应的 gz 话题 |
|------|------|------|------|
| `/cmd_vel` | `geometry_msgs/Twist` | ROS → gz | `/cmd_vel` |
| `/odom` | `nav_msgs/Odometry` | gz → ROS | `/odom` |
| `/scan` | `sensor_msgs/LaserScan` | gz → ROS | `/scan` |
| `/imu` | `sensor_msgs/Imu` | gz → ROS | `/imu` |
| `/tf` | `tf2_msgs/TFMessage` | gz → ROS | `/tf`（差速插件发布 odom→base_footprint） |
| `/clock` | `rosgraph_msgs/Clock` | gz → ROS | `/clock`（`use_sim_time` 依赖它） |
| `/map` | `nav_msgs/OccupancyGrid` | — | （纯 ROS，无 gz 侧） |

---

## 二、环境准备

### 2.1 安装 ROS 2 与所需功能包

```bash
# 假设已完成 ROS 2 Humble 基础安装；安装本项目所需功能包
sudo apt update
sudo apt install -y \
  ros-humble-desktop \
  ros-humble-ros-gz-bridge ros-humble-ros-gz-interfaces \
  ros-humble-slam-toolbox \
  ros-humble-nav2-bringup ros-humble-nav2-map-server \
  ros-humble-teleop-twist-keyboard \
  ros-humble-robot-state-publisher ros-humble-xacro

# (可选) 若你更习惯用 ros_gz_sim create 生成机器人，可再加装：
sudo apt install -y ros-humble-ros-gz-sim
```

同时确认系统已安装 **Gazebo Sim（Ignition Fortress）**：

```bash
ign gazebo --version     # 应输出：Gazebo Sim, version 6.x.x
```

### 2.2 用 rosdepc 安装依赖（已装鱼香 ROS 的 rosdepc）

> 本机安装的是鱼香 ROS 版 **`rosdepc`**，凡涉及依赖初始化的命令**一律用 `rosdepc`，不要用 `rosdep`**。

```bash
cd /home/heu402/fishbot_ws/src/ros2bookcode/chapt9/fishbot_ws

sudo rosdepc init          # 首次使用需初始化（只做一次）
rosdepc update
rosdepc install -i --from-path src --rosdistro humble -y
```

### 2.3 准备代码

代码已位于 `/home/heu402/fishbot_ws/src/ros2bookcode/chapt9/fishbot_ws`。
下文所有命令中的 `WS` 均指该工作空间根目录，请先设置一次：

```bash
export WS=/home/heu402/fishbot_ws/src/ros2bookcode/chapt9/fishbot_ws
```

> 也可以在 `~/.bashrc` 里加上：
> `export WS=/home/heu402/fishbot_ws/src/ros2bookcode/chapt9/fishbot_ws`

---

## 三、编译工作空间

```bash
# 1) 生效 ROS 2 环境
source /opt/ros/humble/setup.bash

# 2) 进入工作空间编译（只需编译本次用到的 3 个包，更快）
cd $WS
colcon build --symlink-install \
  --packages-select fishbot_description fishbot_bringup fishbot_navigation2

# 3) 生效工作空间环境（每个新终端都要执行一次）
source $WS/install/setup.bash
```

看到 `Summary: 3 packages finished` 即编译成功。

> 💡 建议写入 `~/.bashrc`，避免每次手动 source：
> ```bash
> echo "source /opt/ros/humble/setup.bash"              >> ~/.bashrc
> echo "source $WS/install/setup.bash"                  >> ~/.bashrc   # 注意 $WS 需展开为绝对路径
> ```

---

## 四、第一步：Gazebo Sim 仿真，让小车跑起来

### 4.1 启动仿真

**终端 A**：

```bash
source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
ros2 launch fishbot_bringup fishbot_gazebo.launch.py
```

该 launch 会依次完成：

1. 启动 `ign gazebo -r -s` 并加载 `worlds/fishbot_world.world`（一个 5 m×4 m 的房间）；
2. 启动 `ign gazebo -g` 图形界面（加 `gui:=false` 可关闭，用于无显示器/服务器）；
3. 启动 `robot_state_publisher`，读取 `fishbot.urdf` 发布静态 TF；
4. 启动 `fishbot_bridge.launch.py`（`ros_gz_bridge`），把 gz 话题桥接为 ROS 话题；
5. 延迟 15 秒后调用 gz 的 `/world/fishbot_world/create` 服务，把 FishBot 生成到房间原点
   （等效于 `ros_gz_sim create`，这样不强制依赖 `ros_gz_sim` 包）。

看到 Gazebo Sim 窗口中出现蓝色小车和房间，即成功。

> 无图形界面（服务器）时：`ros2 launch fishbot_bringup fishbot_gazebo.launch.py gui:=false`
>
> ⏱️ **耐心等 15~30 秒**：本机为软件渲染，传感器（雷达）渲染线程初始化较慢，`/scan` 需要十几秒才会开始出数据，属正常现象。

### 4.2 键盘遥控小车

**终端 B**（新开）：

```bash
source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

操作：`i` 前进、`,` 后退、`j` 左转、`l` 右转、`k` 停止。
**注意：键盘焦点必须停在终端 B 上**，小车才会动。

> `/cmd_vel` 会被 `ros_gz_bridge` 翻译成 gz 的 `/cmd_vel`，驱动机器人运动。

### 4.3 验证仿真数据是否正常

**终端 C**：

```bash
source $WS/install/setup.bash

ros2 topic list                       # 应能看到 /cmd_vel /odom /scan /imu /tf /clock ...

# 里程计
ros2 topic echo /odom --once

# 雷达（若 echo 无输出，换成 best_effort；见 FAQ 第 3 条）
ros2 topic echo /scan --once

# 查看 TF 树（确认 odom→base_footprint→base_link→laser_link 是否连通）
ros2 run tf2_tools view_frames        # 生成 frames.pdf
```

至此，仿真层面（传感器 + 底盘运动）已全部打通。

> ⏱️ 若 `/odom`、`/tf` 已有数据，但 **`/scan` 暂时为空**，先**等待 15~30 秒**：
> 本机为软件渲染，雷达渲染线程初始化较慢，稍等片刻 `/scan` 就会出数据。
> 长时间仍为空再排查，见 [FAQ 第 1 条](#八常见问题-faq)。

---

## 五、第二步：SLAM 实时建图（slam_toolbox）

SLAM = 同步定位与建图：一边估计机器人位姿，一边把激光数据拼成栅格地图。

### 5.1 启动建图

保持**终端 A 的仿真运行**，**新开终端 D**：

```bash
source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
ros2 launch fishbot_navigation2 fishbot_slam.launch.py
```

该 launch 启动：

- `slam_toolbox`（`async_slam_toolbox_node`，在线异步建图），参数来自 `config/slam_toolbox.yaml`；
- `rviz2`，加载 Nav2 默认视图（`rviz:=false` 可关闭）。

### 5.2 遥控走一圈完成建图

回到**终端 B**，用键盘遥控小车在房间里缓慢走一圈（原地旋转一圈也能扫到四周墙壁）。
RViz 中会实时出现灰色的 `/map`，白色为可通行区域，黑色为墙壁/障碍。

> 💡 建图要点：速度放慢（≤0.2 m/s），转弯不要过猛，尽量让雷达覆盖到每个角落，并形成**闭环**（走回起点）。

### 5.3 保存地图

建图满意后，**新开终端 E**：

```bash
source /opt/ros/humble/setup.bash
source $WS/install/setup.bash

# 保存到 fishbot_navigation2/maps/ ，会生成 room.pgm 与 room.yaml 两个文件
ros2 run nav2_map_server map_saver_cli -f $WS/src/fishbot_navigation2/maps/room
```

成功后查看：

```bash
cat $WS/src/fishbot_navigation2/maps/room.yaml
# image: room.pgm
# mode: trinary
# resolution: 0.05          ← 每个像素代表 0.05 m
# origin: [x, y, yaw]        ← 地图左下角在世界中的位姿
# negate: 0
# occupied_thresh: 0.65
# free_thresh: 0.25
```

保存完即可 **Ctrl+C 关闭建图终端 D**（建图任务结束）。

---

## 六、第三步：定位 + 路径规划 + 自主导航（Nav2）

Nav2 是一个“任务栈”，`fishbot_nav.launch.py` 会一次性拉起：
`map_server`（加载地图）、`amcl`（定位）、`planner_server`（全局路径规划，默认 NavFn/A*）、
`controller_server`（局部控制，默认 DWB）、`behavior_server`（恢复行为）、`bt_navigator`（行为树调度）等。

> 📌 Nav2 全部工作在 **ROS 话题**层面（`/scan`、`/odom`、`/cmd_vel`、`/tf`…），
> 这些话题已由 `ros_gz_bridge` 提供，所以 **Nav2 部分与 Gazebo Classic 完全一样，无需任何改动**。

### 6.1 启动导航

保持**终端 A 的仿真运行**，**新开终端 F**：

```bash
source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
ros2 launch fishbot_navigation2 fishbot_nav.launch.py
```

- 默认加载地图 `maps/room.yaml`，参数 `config/nav2_params.yaml`；
- 同时打开 RViz（`rviz:=false` 可关闭）；
- 启动约需 30–60 秒（Nav2 节点较多），耐心等待 RViz 中出现地图与机器人。

如需指定别的地图：

```bash
ros2 launch fishbot_navigation2 fishbot_nav.launch.py \
  map:=$WS/src/fishbot_navigation2/maps/room.yaml
```

### 6.2 设置初始位姿（AMCL 定位的关键一步）

AMCL 需要知道机器人“大概在哪儿”才能开始定位：

1. 在 RViz 顶部工具栏点 `2D Pose Estimate`；
2. 在地图上机器人实际所在位置**按下并拖动**，箭头指向车头方向，松开。

RViz 中会出现一团绿色粒子云（AMCL 粒子），随后收敛，表示定位成功
（此时 `/amcl_pose` 稳定、TF：`map→odom` 建立）。

### 6.3 设置导航目标点

1. 在 RViz 顶部工具栏点 `2D Goal Pose`；
2. 在地图上的目标位置按下并拖出朝向，松开。

随后你会看到：

- 一条**全局路径**（红色/绿色线）从当前位置规划到目标；
- 小车自动开始运动，`/cmd_vel` 有速度输出；
- 遇到动态障碍时，局部代价地图会实时避障并重规划；
- 抵达目标后 `bt_navigator` 返回 `SUCCEEDED`。

### 6.4 命令行方式发目标（无 RViz 时）

```bash
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
"{pose: {header: {frame_id: 'map'}, pose: {position: {x: 1.5, y: 0.0, z: 0.0}, orientation: {w: 1.0}}}}"
```

---

## 七、完整命令速查

| 终端 | 作用 | 命令 |
|------|------|------|
| A | Gazebo Sim 仿真（含 bridge） | `ros2 launch fishbot_bringup fishbot_gazebo.launch.py` |
| B | 键盘遥控 | `ros2 run teleop_twist_keyboard teleop_twist_keyboard` |
| C | 数据检查 | `ros2 topic list` / `ros2 topic echo /scan --once` |
| D | SLAM 建图 | `ros2 launch fishbot_navigation2 fishbot_slam.launch.py` |
| E | 保存地图 | `ros2 run nav2_map_server map_saver_cli -f $WS/src/fishbot_navigation2/maps/room` |
| F | Nav2 导航 | `ros2 launch fishbot_navigation2 fishbot_nav.launch.py` |

> 建图流程：A + B + D 建图 → E 保存。导航流程：A（重启）+ F → RViz 设初始位姿与目标。
>
> 想单独调试 bridge 时，可只启动桥接：`ros2 launch fishbot_bringup fishbot_bridge.launch.py`

---

## 八、常见问题 FAQ

1. **`/odom`、`/tf` 有数据，但 `/scan` 一开始为空**
   原因：Gazebo Sim 的雷达是 **`gpu_lidar`（GPU 渲染型）**，渲染线程初始化需要时间。
   - **先等 15~30 秒**：本机无硬件 3D，Gazebo Sim 会自动退化为 **Mesa 软件渲染（llvmpipe/swrast）**，
     雷达仍会正常出数据，只是启动慢（实测 `/scan` 的 `ranges` 正常）。
   - 日志里出现 `VMware: No 3D enabled`、`egl: failed to create dri2 screen` 属**正常提示**（软件渲染兜底），
     不影响雷达数据。
   - 若确实长时间无数据（>30 秒），再考虑开硬件 3D 加速（VMware：设置 → 显示器 → 「加速 3D 图形」）。
   > 对比：Gazebo Classic 的 `ray` 雷达是 CPU 计算，不涉及渲染，启动即出数据；Sim 的雷达走渲染，启动慢一点。

2. **仿真启动很慢 / 卡在加载**
   首次加载模型较慢，属正常；本教程世界文件不依赖在线模型库，可离线加载。

3. **`ros2 topic echo /scan`（或 `/odom`）没有输出**
   bridge 发布的部分话题可能是 Best Effort QoS，echo 默认 Reliable 订阅不上，请加参数：
   ```bash
   ros2 topic echo /scan --qos-reliability best_effort --once
   ```

4. **RViz 里没有地图/雷达**
   确认已 `source $WS/install/setup.bash`；确认固定坐标系（Fixed Frame）设为 `map`（建图时先设 `odom` 也行）。

5. **AMCL 定位跑偏 / 小车乱跑**
   一定要先做 **2D Pose Estimate** 给初始位姿；地图与仿真世界不一致时也会定位失败（请用自己建的地图）。

6. **Nav2 启动后一直没反应、目标不可达**
   Nav2 节点多，首次启动需要较长时间；可用 `ros2 node list` 确认 `amcl/planner_server/controller_server/bt_navigator` 是否都起来了。

7. **小车压不住 / 打滑 / 原地打转**
   通常是差速轮轴向或摩擦参数问题；本 URDF 已设置左右轮轴同向 `axis (0 1 0)`、轮子摩擦 0.8、万向轮摩擦 0.01。

8. **`ign gazebo` 命令找不到**
   说明未安装 Gazebo Sim（Ignition Fortress）。安装：`sudo apt install ignition-fortress`，
   确认 `ign gazebo --version` 能输出版本号。

---

## 九、附录：本次新增/修改文件清单

新增：

- `fishbot_bringup/worlds/fishbot_world.world`（Gazebo Sim 世界，SDF 1.9 + 必备 system 插件）
- `fishbot_bringup/launch/fishbot_gazebo.launch.py`（`ign gazebo` 启动 + `ign service` 生成机器人）
- `fishbot_bringup/launch/fishbot_bridge.launch.py`（`ros_gz_bridge` 话题桥接）
- `fishbot_navigation2/launch/fishbot_slam.launch.py`
- `fishbot_navigation2/launch/fishbot_nav.launch.py`
- `fishbot_navigation2/config/slam_toolbox.yaml`

修改：

- `fishbot_description/urdf/fishbot.urdf`（补全模型 + **Gazebo Sim system 插件**：diff-drive / gpu_lidar / imu）
- `fishbot_bringup/package.xml`（运行依赖改为 `ros_gz_bridge`、`ros_gz_interfaces`）
- `fishbot_navigation2/launch/navigation2.launch.py`（重写参数传递，新增 `rviz`/`use_composition` 开关）
- `fishbot_navigation2/package.xml`（补充运行依赖）
- `fishbot_navigation2/maps/room.pgm|room.yaml`（由 SLAM 实测生成）
