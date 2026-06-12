# Guide to add vortex mod manager (DOES NOT WORK YET)

- download vortex mod manager installer
- add the installer to steam as a non-steam game
  - force it use proton as compatibilty tool through properties
  - run installer
- in file manager or terminal, go to /path/to/your/steam/steamapps/compatdata/
  - sort by last modified and navigate to <last-modified>/pfx/drive_c/Program Files/Black Tree Gaming Ltd/Vortex/
  - add the vortex executable as a non-steam game with the path
  - force it use proton as compatibilty tool through properties
- run vortex
  - install dotnet as prompted
  - enable symlinks without elavation from settings
- create staging directory to the managed game directory and symlink it to /path/to/gamedirectory/Vortex Mods/
- install mods
