# /dev/regex

Developed on stream on [twitch](https://twitch.tv/sphaerophoria) and [youtube](https://youtube.com/playlist?list=PL980gcR1LE3L_RdprUI2GkbyZPY998lLT&si=LBuXPSGYk8gGefBw)
A kernel regex engine for fun with the intent of

* Writing a regex engine
* Writing a kernel driver in zig

## Usage

Build/load the driver
```
cd driver
make -C <LINUX KERNEL BUILD DIR> M=$(pwd)
insmod dev_regex.ko
```

And run the test app
```
cd ../
zig build
./zig-out/bin/test_app
```

