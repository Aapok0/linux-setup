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

1. If i3 installed correctly, you should be able to logout of your current session and then choose i3 in the login screen.
  - If your distribution did not have desktop environment or window manager before, you can start i3 by running the command `i3`.

2. Open tmux session with the command `tmux` and install tmux plugins by pressing `ctrl+space I`.

3. Open neovim once with command `nvim` and let it install all the plugins.

4. If everything works, you can remove the old backup directories of configurations from `~/.config`. if you want to.

## Potential issues

The main script might not recognize, if your distribution is arch or debian based. If you know that your distribution is either, you can run the corresponding script:

```bash
./setup_arch
#or
./setup_debian
