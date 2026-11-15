grep PRETTY /etc/os-release
uname -r
echo "--- daemon.json"
cat /etc/docker/daemon.json
echo "--- subuid"
cat /etc/subuid
echo "--- subgid"
cat /etc/subgid
echo "--- binder module"
modinfo -n binder_linux 2>&1
grep -i binder /proc/modules
echo "--- tools"
systemctl --version | head -1
command -v podman weston fuse-overlayfs newuidmap docker dockerd
systemctl is-active docker
id sysbox 2>&1
echo "--- cgroup"
stat -fc %T /sys/fs/cgroup
echo "--- docker run user"
ls -ld /home/* 2>&1
