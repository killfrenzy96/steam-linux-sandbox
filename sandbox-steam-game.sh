#!/bin/bash
# Tested on CachyOS, with a NVIDIA GPU.
# Depends on `xdg-dbus-proxy` and `bubblewrap`.
# This script should be launched within Steam's launch arguments something like this:
# ~/sandbox-steam-game.sh %command%


# log outputs to file instead of terminal
rm /tmp/steam-game.txt
set -eu
exec > /tmp/steam-game.txt 2>&1
set -o


# debug information
echo "START steam-games.sh"
echo "Working Directory: $(pwd)"
echo "Arguments: $@"
echo "ENV:"
env


# setup ENV stuff
BASE_NAME="$SteamAppId"
STEAM_RUNTIMES="${STEAM_RUNTIME%/*}"
STEAM_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
LD_LIBRARY_PATH=
STEAM_LD_PRELOAD="$LD_PRELOAD"
LD_PRELOAD=


# dbus proxy setup
RANDOM_STRING=$(tr -dc 'A-Za-z' </dev/urandom | head -c 16)
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:?}"
DBUS_PROXY_DIR="$XDG_RUNTIME_DIR/bus-proxy"
mkdir -p "$DBUS_PROXY_DIR"
SESSION_PROXY="$DBUS_PROXY_DIR/$BASE_NAME-$RANDOM_STRING-session-$$"
SYSTEM_PROXY="$DBUS_PROXY_DIR/$BASE_NAME-$RANDOM_STRING-system-$$"


# start xdg-dbus-proxy
exec {SYNC_FD}<> <(:)

xdg-dbus-proxy \
	--fd="$SYNC_FD" \
	"$DBUS_SESSION_BUS_ADDRESS" "$SESSION_PROXY" \
	--filter \
	\
	unix:path=/run/dbus/system_bus_socket "$SYSTEM_PROXY" \
	--filter \
	& dbus_proxy_pid=$!


# cleanup on exit
cleanup() {
	echo "Cleaning up: Kill $dbus_proxy_pid"
	if kill -0 "$dbus_proxy_pid" 2>/dev/null; then
		kill "$dbus_proxy_pid"
	fi
	echo "Cleaning up: Delete $SESSION_PROXY $SYSTEM_PROXY"
	rm -f "$SESSION_PROXY" "$SYSTEM_PROXY"
}
trap cleanup EXIT INT TERM


# wait until proxy is ready
read -r -n1 <&"$SYNC_FD"


# dynamic binds
for bind in /dev/nvidia*; do
  [[ -e "$bind" ]] && dynamic_args+=(--dev-bind "$bind" "$bind")
done

for bind in /dev/hidraw*; do
  [[ -e "$bind" ]] && dynamic_args+=(--dev-bind "$bind" "$bind")
done

for bind in $XDG_RUNTIME_DIR/xauth*; do
  [[ -e "$bind" ]] && dynamic_args+=(--ro-bind "$bind" "$bind")
done

IFS=':' read -r -a compat_paths <<< "$LD_PRELOAD"
for path in "${compat_paths[@]}"; do
  [[ -e "$path" ]] && dynamic_args+=(--ro-bind-try "$path" "$path")
done

IFS=':' read -r -a compat_paths <<< "$PATH"
for path in "${compat_paths[@]}"; do
  [[ -e "$path" ]] && dynamic_args+=(--ro-bind-try "$path" "$path")
done

IFS=':' read -r -a compat_paths <<< "$STEAM_COMPAT_TOOL_PATHS"
for path in "${compat_paths[@]}"; do
  [[ -e "$path" ]] && dynamic_args+=(--bind "$path" "$path")
done


# r2modman / doorstop support
args=("$@")
is_r2modman=false
for arg in "${args[@]}"; do
    if [[ "$arg" == "--r2profile" ]]; then
        is_r2modman=true
        break
    fi
done

for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--doorstop-target-assembly" ]]; then
        assembly_path="${args[$((i+1))]}" # get full path
        assembly_path="${assembly_path#*:}" # strip the Z: prefix

        if [[ "$is_r2modman" == true ]]; then
            # r2modman: bind the profile folder
            profile_path="${assembly_path%%/BepInEx/*}"
            dynamic_args+=(--bind-try "$profile_path" "$profile_path")
        else
            # otherwise bind the target assembly file
            dynamic_args+=(--ro-bind-try "$assembly_path" "$assembly_path")
        fi
        break
    fi
done


# strace -f -e trace=openat,open,stat,access -o /tmp/steam-game-trace.txt \
bwrap \
	--die-with-parent \
	--unshare-user \
	--tmpfs ${HOME} \
	--ro-bind-try ${HOME}/.steam/bin ${HOME}/.steam/bin \
	--ro-bind-try ${HOME}/.steam/bin32 ${HOME}/.steam/bin32 \
	--ro-bind-try ${HOME}/.steam/bin64 ${HOME}/.steam/bin64 \
	--ro-bind-try ${HOME}/.steam/root ${HOME}/.steam/root \
	--ro-bind-try ${HOME}/.steam/sdk32 ${HOME}/.steam/sdk32 \
	--ro-bind-try ${HOME}/.steam/sdk64 ${HOME}/.steam/sdk64 \
	--ro-bind-try ${HOME}/.steam/steam ${HOME}/.steam/steam \
	--bind "$(pwd)" "$(pwd)" \
	--ro-bind "$STEAM_RUNTIMES" "$STEAM_RUNTIMES" \
	--bind "$STEAM_COMPAT_DATA_PATH" "$STEAM_COMPAT_DATA_PATH" \
	--tmpfs "$XDG_RUNTIME_DIR" \
	--ro-bind-try "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-0" \
	--ro-bind-try "$XDG_RUNTIME_DIR/pipewire-0" "$XDG_RUNTIME_DIR/pipewire-0" \
	--ro-bind "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/pulse" \
	--ro-bind "$SESSION_PROXY" "$XDG_RUNTIME_DIR/bus" \
	--ro-bind "$SYSTEM_PROXY" /run/dbus/system_bus_socket \
	--tmpfs /tmp \
	--ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
	--dev /dev \
	--dev-bind /dev/dri /dev/dri \
	--dev-bind /dev/input /dev/input \
	--dev-bind /dev/hugepages /dev/hugepages \
	"${dynamic_args[@]}" \
	--dev-bind /dev/snd /dev/snd \
	--dev-bind /dev/fuse /dev/fuse \
	--dev-bind /sys/block/ /sys/block/ \
	--dev-bind /sys/bus/ /sys/bus/ \
	--dev-bind /sys/class/ /sys/class/ \
	--dev-bind /sys/dev/ /sys/dev/ \
	--dev-bind /sys/devices/ /sys/devices/ \
	--dev-bind /sys/module/ /sys/module/ \
	--proc /proc \
	--dir /run \
	--ro-bind /usr /usr \
	--ro-bind /lib /lib \
	--ro-bind /usr/lib32 /lib32 \
	--ro-bind /lib64 /lib64 \
	--ro-bind /bin /bin \
	--tmpfs /etc \
	--ro-bind-try /etc/passwd /etc/passwd \
	--ro-bind-try /etc/fonts /etc/fonts \
	--ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
	--ro-bind-try /etc/ld.so.conf.d /etc/ld.so.conf.d \
	--ro-bind-try /etc/ld.so.preload /etc/ld.so.preload \
	--ro-bind-try /etc/nvidia /etc/nvidia \
	--ro-bind-try /etc/pulse /etc/pulse \
	--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
	--ro-bind-try /etc/vulkan /etc/vulkan \
	--setenv HOME ${HOME} \
	--setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
	--setenv XDG_DATA_HOME ${HOME}/.local/share \
	--setenv LD_LIBRARY_PATH "$STEAM_LD_LIBRARY_PATH" \
	--setenv LD_PRELOAD "$STEAM_LD_PRELOAD" \
	"${@}"
