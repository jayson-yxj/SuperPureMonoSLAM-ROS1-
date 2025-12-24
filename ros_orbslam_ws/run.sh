source devel/setup.bash 
gnome-terminal -- bash -c "source devel/setup.bash; rosrun depth_maping depth_maping_node.py ; exec bash"
rosrun orb_slam3_ros orb_mono ..//Vocabulary/ORBvoc.txt ../MonoConfig/Fisheye.yaml