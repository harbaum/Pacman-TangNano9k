# Pacman ROMs

Required original Pacman arcade ROMS are `82s123.7f`, `82s126.1m`, `82s126.3m`, `82s126.4a`, `pacman.5e`, `pacman.5f`, `pacman.6e`, `pacman.6f`, `pacman.6h` and `pacman.6j`

These need to be converted to hex like so:

```xxd -c1 -p 82s123.7f > 82s123_7f.mem```

or all at once:

```for i in pacman.?? 82s12?.??; do xxd -c1 -p $i > ${i//./_}.mem; done```

