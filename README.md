# Info

Experimental script that runs a Steam game inside a sandbox (Linux only).
- Depends `bubblewrap` for the main sandbox, and `xdg-dbus-proxy` to isolate the dbus.
- Binds only the folders, devices, and files that the game needs to run. The home directory is mounted as a tmpfs, preventing the game from accessing your data.
- Tested only on CachyOS, with a NVIDIA GPU.
- Should work with any Steam game launched via Proton.

## Installation

1. Download `sandbox-steam-game.sh` and place it in your home directory (or anywhere you want, really).

2. Give `sandbox-steam-game.sh` execute permissions:
```bash
chmod +x ~/sandbox-steam-game.sh
```

3. Install `bubblewrap` and `xdg-dbus-proxy`. On CachyOS, this can be done like this:
```bash
sudo pacman -S bubblewrap xdg-dbus-proxy
```

4. For any Steam game you want sandboxed, right click the game on Steam, click Properties, and add this to your launch options:
```bash
~/sandbox-steam-game.sh %command%
```
