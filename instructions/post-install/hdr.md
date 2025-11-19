```bash
sudo cp /usr/share/applications/steam.desktop /usr/share/applications/steam-hdr.desktop
sudo vim /usr/share/applications/steam-hdr.desktop
Name=Steam HDR (Runtime)
Exec=gamescope --hdr-enabled --steam -f -w 2560 -h 1440 -- env DXVK_HDR=1 /usr/bin/steam-runtime %U
```

```bash
sudo cp /usr/share/applications/mpv.desktop /usr/share/applications/mpv-hdr.desktop
sudo vim /usr/share/applications/mpv-hdr.desktop
Name=mpv Media Player (HDR)
Exec=ENABLE_HDR_WSI=1 mpv --player-operation-mode=pseudo-gui --vo=gpu-next --target-colorspace-hint --gpu-api=vulkan --gpu-context=waylandvk -- %U
```
