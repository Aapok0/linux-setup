- move default vm location to somewhere, where you are not taking btrfs snapshots
- install software virtualized tpm2

```bash
paru -S swtpm
```

- download windows 11 iso: https://www.microsoft.com/en-us/software-download/windows11
- create vm with the iso in virtualbox and install
- mount /usr/lib/virtualbox/additions/VBoxGuestAdditions.iso and install guest additions from it
- reboot
- adjust window size -> right ctrl + a, or do fullscreen right ctrl + f
