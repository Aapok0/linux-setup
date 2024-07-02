# Linux setup

Script to setup my preferred environment to a arch or debian based distribution.

## Pre setup

I like to add my user to sudoers with option to not ask password for sudo. You can edit sudoers safely with:

```bash
sudo visudo
```

If it opens to nano, you can open it with vim the following way:

```bash
sudo VISUAL=vim visudo
```

Add the following to the end of the file:

```bash
your_username ALL=(ALL:ALL) NOPASSWD: ALL
```

## Setup

1. Clone this repo.

2. Make sure the script files are executable. Check with `ls -l`. If they're not, add executable rights with:

```bash
chmod u+x filename
```

3. Run the main script with:

```bash
./setup
```

## Post setup

1. Reboot the machine.

2. Run kitty with `mod+enter`.

3. Run the command/app `arandr`, set your screen/s and resolution correctly and save the file as `monitor.sh`.

4. If a firewall was already installed, check its rules.

5. Install nvm and node (+npm) with following commands:"

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
exec zsh
nvm install node
```

6. Open tmux session with the command `tmux` and install tmux plugins by pressing `ctrl+space I`.

7. Open neovim once with command `nvim` and let it install all the plugins.

8. If everything works, you can remove the old backup directories of configurations from `~/.config`. if you want to.

## Potential issues

The main script might not recognize, if your distribution is arch or debian based. If you know that your distribution is either, you can run the setup script with arch or debian as a variable:

```bash
./setup "arch"
#or
./setup "debian"
```

## To be added

- Swap file creation (with hibernate?)
- Setting variables with options
- Clean package caches at the end?

## Possibly missing packages

- acpi
- archlinux-xdg-menu
- awesome-terminal-fonts
- dmenu
- gvfs
- gvfs-gphoto2
- gvfs-mtp
- gvfs-ntp
- gvfs-smb
- i3lock
- i3status
- jq
- nwq-look
- mpv
- numlockx
- sysstat
- thunar-archive-plugin
- thunar-volman
- tumbler
- unzip
- xarchiver
- xbindkeys
- xdg-user-dirs-gtk
- xed
- xorg-xbacklight
- xorg-xdpyinfo
- zip
