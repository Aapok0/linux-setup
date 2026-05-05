Install menu
    - Advanced options ... -> ... Graphical expert install

Choose language
    1. Language -> English
    2. Location -> other -> Europe -> Finland
    3. Locale -> en_US.UTF-8
    4. Additional locale -> fi_FI.UTF-8
    5. Default locale -> fi_FI.UTF-8

Configure the keyboard
    - Keymap -> Finnish

Detect and mount installation media
    - Choose needed modules

Load installer components from installation media
    - Nothing needed from here

Detect network hardware

Configure the network
    1. Auto-configure
    2. Default wait time
    3. Chosen hostname
    4. Leave domain name empty for now

Set up users and passwords
    1. Don't allow login as root (check if recommended -> how to fix installation, if broken?)
    2. Chosen user and pass

Configure the clock
    1. Use NTP
    2. Default NTP server (check if there's something better (arch install instructions))
    3. Timezone -> Europe/Helsinki

Detect disks

Partition disks (need to figure this out with fresh install, might need to use more space and/or ram to fully test)
    1. Guided partitioning
    2. Guided - use entire disk and set up encrypted LVM
    3. Choose disk
    4a. Separate /home partition
        - If using only one disk
    4b. All files in one partition (or manual?), if using separate disks for root, home and possibly also games/media.
    5. Write partitions
    6. Give encryption password
    7. Give volume group name and amount of space used for it
    8. Use defaults

Install the base system
    1. Choose kernel -> linux-image-amd64 (no +deb13 specific)
    2. initrd drivers -> targeted

Configure the package manager
    1. No extra installation media
    2. Use a network mirror
    3. https downloads
    4. Use defaults for mirror
    5. No proxy
    6. Use non-free firmware
    7. Enable source repositories in APT
    8. Security and release updates (no backports for now)

Select and install software
    1. No automatic updates
    2. Don't send package usage data to Debian
    3. KDE Plasma + default tools
    4. Connect to debian's debuginfod server to download debug symbols
    5. libpaper2 default size -> a4
    6. PAM defaults (add fingerprint if needed)
    7. Fontconfig defaults
    8. Don't set mandb to be used by man uid
    9. List APT changes with pager
    10. Show news with APT
    11. Give email to sen APT changes to or leave empty
    12. Ask for confirmation after showing apt changes, don't show headers, show changes in reverse order and skip already show changes
    13. Don't setup BSD ldp
    14. Let CUPS print unkown work
    15. Default CUPS extensions
    16. Add saned user to scanner group