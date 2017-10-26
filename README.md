# asafw

**asafw** is a set of scripts to deal with Cisco ASA firmware. It allows
someone to unpack firmware required when debugging with gdb, as well as
unpacking/repacking them in order to enable certain features such as:

* Enabling gdb at boot
* Disabling ASLR to ease debugging
* Injecting a Linux debug shell to allow CTRL^C in gdb when used with real 
  hardware
* Rooting a firmware (generally deprecated by enabling gdb at boot and injecting
  a root shell)
* etc.

The more useful tools are `unpack_repack_bin.sh` and `unpack_repack_qcow2.sh`.
They allow respectively to manipulate `asa*.bin` and `asav*.qcow2` image 
formats. They both need to be executed as root when actually repacking rootfs to
keep the right permissions.

## Requirements

* Python3 only
* Heavily tested on Linux (but could work on OS X to)

You initially need to modify `asafw/env.sh` to match your environment. It will
allow you to define paths to the tools used by all the scripts as well as some
variables matching your ASA environment. Note there is a simmilar 
`asadbg/env.sh` but only one is required to be used for both projects. We 
recommend that you add it to your `~/.bashrc`:

```
source /path/to/asafw/env.sh
```

# unpack_repack_bin.sh

`unpack_repack_bin.sh` is used to unpack/repack `asa*.bin` images which are used
for real Cisco ASA hardware (such as ASA 5500 and 5500-X series). The complete
usage is:

```
$ unpack_repack_bin.sh -h
Usage:
./unpack_repack_bin.sh -i <firmware_file> -o <out_dir> [-f -g -G -a -A -m -b -r -u -l <linabin_dir> -d -e -k]
      -h, --help                    This help menu
      -i, --input <firmware_file>   What firmware bin to operate on
      -o, --output  <out_dir>       Where to write new firmware
      -f, --free-space              Remove space from .bin to ensure injections fit
      -g, --enable-gdb              Set gdb to start on boot
      -G, --disable-gdb             Stop gdb from starting on boot
      -a, --enable-aslr             Turn on ASLR
      -A, --disable-aslr            Turn off ASLR
      -m, --inject-gdb              Inject gdbserver to run
      -b, --debug-shell             Inject ssh-triggered debug shell
      -H, --lina-hook               Inject hooks for monitor lina heap (requires -b)
      -r, --root                    root the bin to get a rootshell on boot
      -c, --custom                  custom?
      -n, --n-custom                custom?
      -q, --gns3-fixup              gns?
      -u, --unpack-only             unpack the firmware and nothing else
      -l, --linabins <linabin_dir>  destination folder to save lina binaries
      -d, --delete-extracted        delete files extracted during modification
      -e, --delete-original-bin     delete the original firmware being modified
      -k, --keep-rootfs             keep the extracted rootfs on disk
      -s, --simple-name             use a simple name for the output .bin with just appended '-repacked'
Examples:
 ./unpack_repack_bin.sh -i /home/user/firmware -o /home/user/firmware_repacked --free-space --enable-gdb --inject-gdb
 ./unpack_repack_bin.sh -i /home/user/firmware/asa961-smp-k8.bin -f -g -m
 ./unpack_repack_bin.sh -u -i /home/user/firmware -l /home/user/linabins
 ./unpack_repack_bin.sh -u -i /home/user/firmware/asa924-k8.bin -k
```

## Extract multiple firmare

Let's assume we have these two firmware:

```
~/fw$ ls
asa924-k8.bin  asa981-smp-k8.bin
```

If you only want to extract firmware, e.g. to debug them with
[asadbg](https://github.com/nccgroup/asadbg), you can use `-u` to unpack only
and `-k` to only keep the rootfs and delete other files extracted by binwalk
that you don't need:

```
~/fw$ unpack_repack_bin.sh -i . -o . -k -u
[unpack_repack_bin] Directory of firmware detected: .
[unpack_repack_bin] extract_one: asa924-k8.bin

DECIMAL       HEXADECIMAL     DESCRIPTION
--------------------------------------------------------------------------------
75000         0x124F8         SHA256 hash constants, little endian
144510        0x2347E         gzip compressed data, maximum compression, from Unix, last modified: 2015-07-15 04:53:23
1501296       0x16E870        gzip compressed data, has original file name: "rootfs.img", from Unix, last modified: 2015-07-15 05:19:52
27168620      0x19E8F6C       MySQL ISAM index file Version 4
28192154      0x1AE2D9A       Zip archive data, at least v2.0 to extract, name: com/cisco/webvpn/csvrjavaloader64.dll
28773362      0x1B70BF2       Zip archive data, at least v2.0 to extract, name: AliasHandlerWrapper-win64.dll

[unpack_repack_bin] Extracted firmware to /home/user/fw/_asa924-k8.bin.extracted
[unpack_repack_bin] Firmware uses regular rootfs/ dir
[unpack_repack_bin] Extracting /home/user/fw/_asa924-k8.bin.extracted/rootfs/rootfs.img into /home/user/fw/_asa924-k8.bin.extracted/rootfs
[unpack_repack_bin] Keeping rootfs
[unpack_repack_bin] Deleting "/home/user/fw/_asa924-k8.bin.extracted/rootfs.img"
[unpack_repack_bin] Deleting "/home/user/fw/_asa924-k8.bin.extracted/2347E"
[unpack_repack_bin] Deleting "/home/user/fw/_asa924-k8.bin.extracted/1AE2D9A.zip"
[unpack_repack_bin] extract_one: asa981-smp-k8.bin

DECIMAL       HEXADECIMAL     DESCRIPTION
--------------------------------------------------------------------------------
75264         0x12600         SHA256 hash constants, little endian
133120        0x20800         Microsoft executable, portable (PE)
149183        0x246BF         gzip compressed data, maximum compression, from Unix, last modified: 2017-01-30 19:33:09
3678112       0x381FA0        gzip compressed data, has original file name: "rootfs.img", from Unix, last modified: 2017-05-10 22:42:05
14838307      0xE26A23        MySQL MISAM compressed data file Version 4
87985870      0x53E8ECE       MySQL MISAM compressed data file Version 7
96261881      0x5BCD6F9       Zip archive data, at least v2.0 to extract, name: com/cisco/webvpn/csvrjavaloader64.dll
96890193      0x5C66D51       MySQL ISAM compressed data file Version 5

[unpack_repack_bin] Extracted firmware to /home/user/fw/_asa981-smp-k8.bin.extracted
[unpack_repack_bin] Firmware uses regular rootfs/ dir
[unpack_repack_bin] Extracting /home/user/fw/_asa981-smp-k8.bin.extracted/rootfs/rootfs.img into /home/user/fw/_asa981-smp-k8.bin.extracted/rootfs
[unpack_repack_bin] Keeping rootfs
[unpack_repack_bin] Deleting "/home/user/fw/_asa981-smp-k8.bin.extracted/rootfs.img"
[unpack_repack_bin] Deleting "/home/user/fw/_asa981-smp-k8.bin.extracted/5BCD6F9.zip"
[unpack_repack_bin] Deleting "/home/user/fw/_asa981-smp-k8.bin.extracted/246BF"
```

Note that errors like below you may get don't matter in this case because you
are not going to repack the firmware:

```
cpio: lib/udev/devices/kmem: Function mknod failed: Operation not permitted
cpio: lib/udev/devices/net/tun: Function mknod failed: Operation not permitted
cpio: lib/udev/devices/loop01: Function mknod failed: Operation not permitted
cpio: lib/udev/devices/null: Function mknod failed: Operation not permitted
cpio: lib/udev/devices/console: Function mknod failed: Operation not permitted
cpio: lib/udev/devices/loop00: Function mknod failed: Operation not permitted
134992 blocks
```

## Enable gdb at boot / debug shell

Let's assume we have these two firmware:

```
~/fw$ ls
asa924-k8.bin  asa981-smp-k8.bin
```

We enable gdb with `-g` and remove some unused files with `-f` to be able to
repack the firmware (the compressed rootfs needs to be smaller than the original
one). We also patch `lina` to add a debug shell with `-b`. As we see below, it
worked for `asa924-k8.bin` but it failed for `asa981-smp-k8.bin`. This is
because we haven't added the target to our json database:

```
~/fw# unpack_repack_bin.sh -i . -f -g -b -o .
[unpack_repack_bin] Directory of firmware detected: .
[unpack_repack_bin] unpack_one: asa924-k8.bin
[bin] Unpacking...
[bin] Writing /home/user/fw/asa924-k8-initrd-original.gz (29013841 bytes)...
[bin] unpack: Writing /home/user/fw/asa924-k8-vmlinuz (1368176 bytes)...
134992 blocks
[unpack_repack_bin] modify_one: asa924-k8.bin
[unpack_repack_bin] ENABLE GDB
[unpack_repack_bin] FREE SPACE IN .BIN
[unpack_repack_bin] Using 32-bit firmware
[unpack_repack_bin] Adding debug shell for 192.168.210.78:4444
[lina] WARN: No index specified. Will guess based on lina path...
[lina] Using index: 132 for asa924-k8.bin
[lina] Input file: /home/user/fw/work/asa/bin/lina
[lina] Size of clean lina: 43386588 bytes
[lina] Patching lina offset: 0x3db00 with len = 445 bytes
[lina] Output file: /home/user/fw/work/asa/bin/lina
[unpack_repack_bin] repack_one: asa924-k8.bin
132192 blocks
[bin] Repacking...
[bin] repack: Writing ./asa924-k8-debugshell-gdbserver.bin (30597120 bytes)...
[unpack_repack_bin] MD5: 6ee6af342a5b1ef31d633fca6dfa0d1a  ./asa924-k8-debugshell-gdbserver.bin
[unpack_repack_bin] CLEANUP
[unpack_repack_bin] unpack_one: asa981-smp-k8.bin
[bin] Unpacking...
[bin] Writing /home/user/fw/asa981-smp-k8-initrd-original.gz (100973358 bytes)...
[bin] Could not find Direct booting from string
[bin] Probably handling a 64-bit firmware...
[bin] unpack: Writing /home/user/fw/asa981-smp-k8-vmlinuz (3544992 bytes)...
458699 blocks
[unpack_repack_bin] modify_one: asa981-smp-k8.bin
[unpack_repack_bin] ENABLE GDB
[unpack_repack_bin] FREE SPACE IN .BIN
[unpack_repack_bin] Using 32-bit firmware
[unpack_repack_bin] Adding debug shell for 192.168.210.78:4444
[lina] WARN: No index specified. Will guess based on lina path...
[lina] [x] Failed to get target index matching bin name
/path/asafw/lina.py -b asa981-smp-k8.bin -f /home/user/fw/work/asa/bin/lina -o /home/user/fw/work/asa/bin/lina -c 192.168.210.78 -p 4444 -d /path/to/asadbg/asadb.json failed
```

As you can see we get an additional firmware with gdb enabled: 
`asa924-k8-debugshell-gdbserver.bin` that can be used with 
[asadbg](https://github.com/nccgroup/asadbg). 

```
~/fw# ls
asa924-k8.bin                       asa981-smp-k8.bin                   asa981-smp-k8-initrd-original.gz  work
asa924-k8-debugshell-gdbserver.bin  asa981-smp-k8-initrd-original.cpio  asa981-smp-k8-vmlinuz
```

Also the latest extracted rootfs is kept in `work` for debugging purpose. 
The remaining files for `asa981-smp-*` are there because of the failure. You can
use the idahunt scripts in [asadbg](https://github.com/nccgroup/asadbg) to 
import the new `lina`. You can more specifically refer to the 
`Importing additional symbols` section in the 
[README](https://github.com/nccgroup/asadbg/README.md#Importing additional symbols).

# unpack_repack_qcow2.sh

## Extract one firmware

You need to be root even if you just want to unpack firmware:

```
$ unpack_repack_qcow2.sh -i asav941-200.qcow2 -u
[unpack_repack_qcow2] You need to be root to mount/unmount the qcow2
```

You can extract one `asav*.qcow2` image with the following. Again `-u` is used
to unpack only.

```
~/fw_qcow2# unpack_repack_qcow2.sh -i asav941-200.qcow2 -u
[unpack_repack_qcow2] Using input qcow2 file: asav941-200.qcow2
[unpack_repack_qcow2] Using template qcow2 file: asav941-200.qcow2
[unpack_repack_qcow2] Using output qcow2 file: /home/user/fw_qcow2/asav941-200-repacked.qcow2
[unpack_repack_qcow2] Command line: -f 
[unpack_repack_qcow2] extract_one: asav941-200.qcow2
[unpack_repack_qcow2] Mounted /dev/nbd01 to /home/user/mnt/qcow2
[unpack_repack_qcow2] Copied asa941-200-smp-k8.bin to /home/user/fw_qcow2/bin/asav941-200.qcow2
[unpack_repack_qcow2] Unmounted /home/user/mnt/qcow2
[unpack_repack_bin] Single firmware detected
[unpack_repack_bin] extract_one: asav941-200.qcow2

DECIMAL       HEXADECIMAL     DESCRIPTION
--------------------------------------------------------------------------------
74656         0x123A0         SHA256 hash constants, little endian
133120        0x20800         Microsoft executable, portable (PE)
149183        0x246BF         gzip compressed data, maximum compression, from Unix, last modified: 1970-01-01 00:00:00 (null date)
3447872       0x349C40        gzip compressed data, has original file name: "rootfs.img", from Unix, last modified: 2015-05-12 00:16:47
68057161      0x40E7849       Zip archive data, at least v2.0 to extract, name: com/cisco/webvpn/csvrjavaloader64.dll
68700208      0x4184830       Zip archive data, at least v2.0 to extract, name: libAliasHandlerWrapper-mac.jnilib

[unpack_repack_bin] Extracted firmware to /home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted
[unpack_repack_bin] Firmware uses regular rootfs/ dir
[unpack_repack_bin] Extracting /home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted/rootfs/rootfs.img into /home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted/rootfs
334503 blocks
[unpack_repack_bin] Keeping rootfs
[unpack_repack_bin] Deleting "/home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted/rootfs.img"
[unpack_repack_bin] Deleting "/home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted/246BF"
[unpack_repack_bin] Deleting "/home/user/fw_qcow2/bin/_asav941-200.qcow2.extracted/40E7849.zip"
```

We can access the extracted rootfs or use it with 
[asadbg](https://github.com/nccgroup/asadbg).

```
~/fw_qcow2# ls
asav941-200.qcow2  _asav941-200.qcow2.extracted  asav971.qcow2  bin
~/fw_qcow2# ls _asav941-200.qcow2.extracted/rootfs/
asa  bin  boot  dev  etc  home  init  lib  lib64  media  mnt  proc  root  run  sbin  sys  tmp  usr  var
```

## Enable gdb at boot / disable ASLR

You can enable gdb at boot with `-g` and disable ASLR with `-A`. This allows
debugging the firmware with gdb after loading it with GNS3:

```
~/fw_qcow2# unpack_repack_qcow2.sh -i asav962-7.qcow2 -g -A 
[unpack_repack_qcow2] Using input qcow2 file: asav962-7.qcow2
[unpack_repack_qcow2] Using template qcow2 file: asav962-7.qcow2
[unpack_repack_qcow2] Using output qcow2 file: /home/user/fw_qcow2/asav962-7-repacked.qcow2
[unpack_repack_qcow2] Command line: -f  -g -A
[unpack_repack_qcow2] extract_repack_one: asav962-7.qcow2
[unpack_repack_qcow2] Mounted /dev/nbd01 to /home/user/mnt/qcow2
[unpack_repack_qcow2] Copied asa962-7-smp-k8.bin to /home/user/fw_qcow2/bin/asav962-7.qcow2
[unpack_repack_qcow2] Unmounted /home/user/mnt/qcow2
[unpack_repack_bin] Single firmware detected
[unpack_repack_bin] unpack_one: asav962-7.qcow2
[bin] Unpacking...
[bin] Writing /home/user/fw_qcow2/bin/asav962-7-initrd-original.gz (86019506 bytes)...
[bin] Could not find Direct booting from string
[bin] Probably handling a 64-bit firmware...
[bin] unpack: Writing /home/user/fw_qcow2/bin/asav962-7-vmlinuz (3624768 bytes)...
455629 blocks
[unpack_repack_bin] modify_one: asav962-7.qcow2
[unpack_repack_bin] DISABLE ASLR
[unpack_repack_bin] ENABLE GDB
[unpack_repack_bin] FREE SPACE IN .BIN
[unpack_repack_bin] repack_one: asav962-7.qcow2
442851 blocks
[bin] Repacking...
[bin] repack: Writing /home/user/fw_qcow2/bin/asav962-7-repacked-gdbserver.qcow2 (89874432 bytes)...
[unpack_repack_bin] MD5: b898d5db383a95fa412527f8b1cd52e4  /home/user/fw_qcow2/bin/asav962-7-repacked-gdbserver.qcow2
[unpack_repack_bin] CLEANUP
[unpack_repack_qcow2] Mounted /dev/nbd01 to /home/user/mnt/qcow2
[unpack_repack_qcow2] Moved modified .bin inside of /home/user/fw_qcow2/asav962-7-repacked.qcow2
[unpack_repack_qcow2] Unmounted /home/user/mnt/qcow2
````

The obtained `/home/user/fw_qcow2/asav962-7-repacked.qcow2` has both gdb enabled
at boot and ASLR disabled.

# Firmware helpers

## bin.py

`bin.py` is used to manipulate `asa*.bin` images. It is mainly used by 
`unpack_repack_bin.sh` and `unpack_repack_qcow2.sh`.

```
$ bin.py -h
usage: bin.py [-h] [-f FIRMWARE_FILE] [-g GZIP_FILE] [-u] [-r] [-t] [-T]
              [-o OUTPUTFILE]

optional arguments:
  -h, --help            show this help message and exit
  -f FIRMWARE_FILE, --firmware-file FIRMWARE_FILE
  -g GZIP_FILE, --gzip-file GZIP_FILE
  -u, --unpack
  -r, --repack
  -t, --root
  -T, --unroot
  -o OUTPUTFILE, --output-file OUTPUTFILE
```

It can still be used to quickly extract a Linux kernel and a rootfs from an
`asa*.bin` firmware:

```
$ bin.py -f asa924-k8.bin -u
[bin] Unpacking...
[bin] Writing asa924-k8-initrd-original.gz (29013841 bytes)...
[bin] unpack: Writing asa924-k8-vmlinuz (1368176 bytes)...
$ file asa924-k8-*
asa924-k8-initrd-original.gz:       gzip compressed data, was "rootfs.img", from Unix, last modified: Wed Jul 15 06:19:52 2015
asa924-k8-vmlinuz:                  x86 boot sector
```

You can also use it to root a single binary:

```
$ bin.py -f asa924-k8.bin -t
[bin] root: Writing asa924-k8-rooted.bin (30597120 bytes)...
```

We check the differences in the two `asa*.bin`:

```
$ xxd asa924-k8.bin > b1.hex
$ xxd asa924-k8-rooted.bin > b2.hex
$ diff b1.hex b2.hex 
1907204,1907206c1907204,1907206
< 1d1a030: 0048 2000 70e0 1400 51b7 ba01 7175 6965  .H .p...Q...quie
< 1d1a040: 7420 6c6f 676c 6576 656c 3d30 2061 7574  t loglevel=0 aut
< 1d1a050: 6f20 6b73 7461 636b 3d31 3238 2072 6562  o kstack=128 reb
---
> 1d1a030: 0048 2000 70e0 1400 51b7 ba01 7264 696e  .H .p...Q...rdin
> 1d1a040: 6974 3d2f 6269 6e2f 7368 2020 2020 2020  it=/bin/sh      
> 1d1a050: 2020 6b73 7461 636b 3d31 3238 2072 6562    kstack=128 reb
```

## cpio.sh

The `cpio.sh` is used to manipulate CPIO images (rootfs). It is mainly used by 
`unpack_repack_bin.sh` and `unpack_repack_qcow2.sh`. It's a pretty slim wrapper
around cpio to just combine a few commands together for convenience:

```
$ cpio.sh -h
Unknown option
-c  Create cpio image
-d  Directory to turn into cpio image
-e  Extract cpio image
-o  Output file
Examples:
Create ./cpio.sh -c -d rootfs -o rootfs.img
Extract ./cpio.sh -e -i rootfs.img
```

If you want to play with it as standalone, you can do the following.
After extracting a gzipped rootfs with `bin.py`, we decompress it:

```
$ gunzip asa924-k8-initrd-original.gz
$ file asa924-k8-initrd-original 
asa924-k8-initrd-original: ASCII cpio archive (SVR4 with no CRC)
```

Now we extract the rootfs into the `rootfs_924` folder:

```
$ cpio.sh -e -i asa924-k8-initrd-original -d rootfs_924
$ ls rootfs_924/
asa  bin  boot  config  dev  etc  home  init  lib  lib64  linuxrc  mnt  opt  proc  root  sbin  share  sys  tmp  usr  var
```

## lina.py

`lina.py` is used to patch the main Cisco ASA executable a.k.a. `lina`. It
is mainly used by `unpack_repack_bin.sh` and `unpack_repack_qcow2.sh`.

```
$ lina.py -h
usage: lina.py [-h] [-c CBHOST] [-p CBPORT] [--log-port CBLOGPORT]
               [-i TARGET_INDEX] [-f LINA_FILE] [-b BIN_NAME]
               [-o LINA_FILE_OUT] [--hook] [-v] [-d TARGET_FILE]

optional arguments:
  -h, --help            show this help message and exit
  -c CBHOST             Attacker or debugger IP addr for reverse shell
  -p CBPORT             Attacker or debugger port for reverse shell
  --log-port CBLOGPORT  Port for sending hook logs
  -i TARGET_INDEX       Index of the target (use -l to list them all)
  -f LINA_FILE          Input lina file
  -b BIN_NAME           Input bin name
  -o LINA_FILE_OUT      Output lina file
  --hook                Insert lina hooks
  -v                    Display more info
  -d TARGET_FILE        JSON db name
```

We can use it as a standalone tool to patch `lina` to contain a debug shell. We
use the `asadbg.json` from [asadbg](https://github.com/nccgroup/asadbg) as it
already contains addresses required. Otherwise you may need to use
[idahunt](https://github.com/nccgroup/idahunt) to find them first.

```
$ lina.py -c 192.168.1.1 -p 5555 -f _asa924-k8.bin.extracted/rootfs/asa/bin/lina -b asa924-k8.bin -o lina_patched -d /path/to/asadbg/asadb.json 
[lina] WARN: No index specified. Will guess based on lina path...
[lina] Using index: 0 for asa924-k8.bin
[lina] Input file: _asa924-k8.bin.extracted/rootfs/asa/bin/lina
[lina] Size of clean lina: 43386588 bytes
[lina] Patching lina offset: 0x3db00 with len = 445 bytes
[lina] Output file: lina_patched
```

We can check that it just patched one function with the reverse debug shell
shellcode:

```
$ xxd _asa924-k8.bin.extracted/rootfs/asa/bin/lina > b1.hex
$ xxd lina_patched > b2.hex
$ diff b1.hex b2.hex 
15793,15820c15793,15820
< 003db00: 5589 e557 5653 81ec 8c05 0000 8b7d 208d  U..WVS.......} .
< 003db10: 45f0 c745 f001 0000 0066 c745 b0c1 1085  E..E.....f.E....
< 003db20: ffc7 45b4 0400 0000 8945 b866 c745 bc00  ..E......E.f.E..
< 003db30: 00c7 45c0 0000 0000 c745 c400 0000 0074  ..E......E.....t
< 003db40: 088b 4520 66c7 0000 008b 7524 85f6 7409  ..E f.....u$..t.
< 003db50: 8b55 24c7 0200 0000 008d 95f4 feff ff31  .U$............1
< 003db60: db89 d789 d8b9 2000 0000 f3ab c785 f4fe  ...... .........
< 003db70: ffff 0100 0000 c785 50ff ffff ffff ffff  ........P.......
< 003db80: 8b45 0889 1424 8985 68ff ffff e8bf 3525  .E...$..h.....5%
< 003db90: 01c7 85a4 faff ff00 0000 0085 c089 85a0  ................
< 003dba0: faff ff0f 849f 0400 008b 4018 8db5 38fe  ..........@...8.
< 003dbb0: ffff 89f7 8904 24e8 24a9 2501 b92f 0000  ......$.$.%../..
< 003dbc0: 0089 85b0 faff ff89 d8f3 abc7 8538 feff  .............8..
< 003dbd0: ff00 0000 008b 95a0 faff ff8b 7d08 8b42  ............}..B
< 003dbe0: 1889 853c feff ff8b 4244 897c 2404 c785  ...<....BD.|$...
< 003dbf0: 4cfe ffff ffff ffff c785 48fe ffff ffff  L.........H.....
< 003dc00: ffff 8985 44fe ffff 8934 24e8 e0f8 ffff  ....D....4$.....
< 003dc10: b909 0000 0089 8590 faff ff8d 8574 ffff  .............t..
< 003dc20: ff89 859c faff ff89 c789 d8f3 abc7 85a4  ................
< 003dc30: faff ffff ffff ff83 bd90 faff ffff 0f84  ................
< 003dc40: 1c04 0000 8d85 b4fa ffff b1a1 8985 98fa  ................
< 003dc50: ffff 89c7 89d8 f3ab 8d95 b4fa ffff 8d9d  ................
< 003dc60: 33fb ffff 8b4d 0ceb 138d b426 0000 0000  3....M.....&....
< 003dc70: 8802 83c2 0139 da74 0a83 c101 0fb6 0184  .....9.t........
< 003dc80: c075 edc6 0200 8d9d b3fb ffff 8b4d 108d  .u...........M..
< 003dc90: 9534 fbff ffeb 0d90 8802 83c2 0139 da74  .4...........9.t
< 003dca0: 0a83 c101 0fb6 0184 c075 edc6 0200 8b55  .........u.....U
< 003dcb0: 148d bd6c 2e00 008b 4508 c785 10fd ffff  ...l....E.......
---
> 003db00: b840 bc2a 09ff d0b8 0200 0000 cd80 85c0  .@.*............
> 003db10: 0f85 a101 0000 baed 0100 00b9 c200 0000  ................
> 003db20: 682f 7368 0068 2f74 6d70 8d1c 24b8 0500  h/sh.h/tmp..$...
> 003db30: 0000 cd80 50eb 3159 8b11 8d49 0489 c3b8  ....P.1Y...I....
> 003db40: 0400 0000 cd80 5bb8 0600 0000 cd80 8d1c  ......[.........
> 003db50: 2431 d252 538d 0c24 b80b 0000 00cd 8031  $1.RS..$.......1
> 003db60: dbb8 0100 0000 cd80 e8ca ffff ff46 0100  .............F..
> 003db70: 007f 454c 4601 0101 0000 0000 0000 0000  ..ELF...........
> 003db80: 0002 0003 0001 0000 0054 8004 0834 0000  .........T...4..
> 003db90: 0000 0000 0000 0000 0034 0020 0001 0000  .........4. ....
> 003dba0: 0000 0000 0001 0000 0000 0000 0000 8004  ................
> 003dbb0: 0800 8004 08f2 0000 00f2 0000 0007 0000  ................
> 003dbc0: 0000 1000 0055 89e5 83ec 106a 006a 016a  .....U.....j.j.j
> 003dbd0: 028d 0c24 bb01 0000 00b8 6600 0000 cd80  ...$......f.....
> 003dbe0: 83c4 0c89 45fc 687f 0000 0168 0200 0438  ....E.h....h...8
> 003dbf0: 8d14 246a 1052 508d 0c24 bb03 0000 00b8  ..$j.RP..$......
> 003dc00: 6600 0000 cd80 83c4 1485 c07d 186a 006a  f..........}.j.j
> 003dc10: 018d 1c24 31c9 b8a2 0000 00cd 8083 c408  ...$1...........
> 003dc20: ebc4 8b45 fc83 ec20 8d0c 24ba 0300 0000  ...E... ..$.....
> 003dc30: 8b5d fcc7 0105 0100 00b8 0400 0000 cd80  .]..............
> 003dc40: ba04 0000 00b8 0300 0000 cd80 c701 0501  ................
> 003dc50: 0001 c741 04c0 a801 0166 c741 0815 b3ba  ...A.....f.A....
> 003dc60: 0a00 0000 b804 0000 00cd 80ba 2000 0000  ............ ...
> 003dc70: b803 0000 00cd 8083 c420 8b5d fcb9 0200  ......... .]....
> 003dc80: 0000 b83f 0000 00cd 8049 7df6 31d2 682d  ...?.....I}.1.h-
> 003dc90: 6900 0089 e768 2f73 6800 682f 6269 6e89  i....h/sh.h/bin.
> 003dca0: e352 5753 8d0c 24b8 0b00 0000 cd80 31db  .RWS..$.......1.
> 003dcb0: b801 0000 00cd 80b8 0100 0000 c3fd ffff  ................
```

# Datamining 

## info.sh

The `info.sh` script allows listing mitigations on the firmare in the current
folder.

```
$ info.sh -h
Display/save mitigations and additional info for all firmware in the current folder
Usage: info.sh [--save-result --db-name <json_db>]
```

Once you have extracted all firmware, you can analyse them:

```
fw$ ls
_asa802-k8.bin.extracted         _asa825-51-k8.bin.extracted      _asa844-5-k8.bin.extracted    _asa911-4-k8.bin.extracted    _asa922-4-k8.bin.extracted        _asa944-smp-k8.bin.extracted
_asa803-k8.bin.extracted         _asa825-52-k8.bin.extracted      _asa844-9-k8.bin.extracted    _asa911-k8.bin.extracted      _asa922-4-smp-k8.bin.extracted    _asa951-smp-k8.bin.extracted
_asa804-16-k8.bin.extracted      _asa825-57-k8.bin.extracted      _asa844-k8.bin.extracted      _asa911-smp-k8.bin.extracted  _asa922-k8.bin.extracted          _asa952-smp-k8.bin.extracted
_asa804-k8.bin.extracted         _asa825-59-k8.bin.extracted      _asa845-k8.bin.extracted      _asa912-k8.bin.extracted      _asa923-k8.bin.extracted          _asa953-smp-k8.bin.extracted
_asa805-23-k8.bin.extracted      _asa825-k8.bin.extracted         _asa845-smp-k8.bin.extracted  _asa912-smp-k8.bin.extracted  _asa923-smp-k8.bin.extracted      _asa961-10-smp-k8.bin.extracted
_asa805-28-k8.bin.extracted      _asa825-smp-k8.bin.extracted     _asa846-5-k8.bin.extracted    _asa913-k8.bin.extracted      _asa924-10-k8.bin.extracted       _asa961-smp-k8.bin.extracted
_asa805-31-k8.bin.extracted      _asa831-k8.bin.extracted         _asa846-k8.bin.extracted      _asa913-smp-k8.bin.extracted  _asa924-13-smp-k8.bin.extracted   _asa962-3-smp-k8.bin.extracted
_asa805-k8.bin.extracted         _asa831-smp-k8.bin.extracted     _asa846-smp-k8.bin.extracted  _asa914-5-k8.bin.extracted    _asa924-14-k8.bin.extracted       _asa962-smp-k8.bin.extracted
_asa811-smp-k8.bin.extracted     _asa832-13-k8.bin.extracted      _asa847-15-k8.bin.extracted   _asa914-k8.bin.extracted      _asa924-18-k8.bin.extracted       _asa971-smp-k8.bin.extracted
_asa812-23-smp-k8.bin.extracted  _asa832-25-k8.bin.extracted      _asa847-26-k8.bin.extracted   _asa914-smp-k8.bin.extracted  _asa924-5-k8.bin.extracted        _asav932-200.qcow2.extracted
_asa812-49-smp-k8.bin.extracted  _asa832-39-k8.bin.extracted      _asa847-28-k8.bin.extracted   _asa915-12-k8.bin.extracted   _asa924-5-smp-k8.bin.extracted    _asav933-10.qcow2.extracted
_asa812-50-smp-k8.bin.extracted  _asa832-40-k8.bin.extracted      _asa847-29-k8.bin.extracted   _asa915-16-k8.bin.extracted   _asa924-8-k8.bin.extracted        _asav933-11.qcow2.extracted
_asa812-55-smp-k8.bin.extracted  _asa832-44-k8.bin.extracted      _asa847-30-k8.bin.extracted   _asa915-19-k8.bin.extracted   _asa924-8-smp-k8.bin.extracted    _asav933-9.qcow2.extracted
_asa812-56-smp-k8.bin.extracted  _asa832-44-smp-k8.bin.extracted  _asa847-31-k8.bin.extracted   _asa915-21-k8.bin.extracted   _asa924-k8.bin.extracted          _asav941-13.qcow2.extracted
_asa812-smp-k8.bin.extracted     _asa832-4-k8.bin.extracted       _asa847-k8.bin.extracted      _asa915-k8.bin.extracted      _asa924-smp-k8.bin.extracted      _asav941-200.qcow2.extracted
_asa821-k8.bin.extracted         _asa832-k8.bin.extracted         _asa847-smp-k8.bin.extracted  _asa915-smp-k8.bin.extracted  _asa931-smp-k8.bin.extracted      _asav941-6.qcow2.extracted
_asa822-k8.bin.extracted         _asa832-smp-k8.bin.extracted     _asa861-smp-k8.bin.extracted  _asa916-10-k8.bin.extracted   _asa932-200-smp-k8.bin.extracted  _asav941.qcow2.extracted
_asa822-smp-k8.bin.extracted     _asa841-11-k8.bin.extracted      _asa901-k8.bin.extracted      _asa916-11-k8.bin.extracted   _asa932-smp-k8.bin.extracted      _asav942-6.qcow2.extracted
_asa823-k8.bin.extracted         _asa841-k8.bin.extracted         _asa902-k8.bin.extracted      _asa916-4-k8.bin.extracted    _asa933-11-smp-k8.bin.extracted   _asav942.qcow2.extracted
_asa823-smp-k8.bin.extracted     _asa841-smp-k8.bin.extracted     _asa902-smp-k8.bin.extracted  _asa916-k8.bin.extracted      _asa933-7-smp-k8.bin.extracted    _asav952-204.qcow2.extracted
_asa824-4-k8.bin.extracted       _asa842-8-k8.bin.extracted       _asa903-k8.bin.extracted      _asa916-smp-k8.bin.extracted  _asa933-9-smp-k8.bin.extracted    _asav961.qcow2.extracted
_asa824-k8.bin.extracted         _asa842-k8.bin.extracted         _asa903-smp-k8.bin.extracted  _asa917-12-k8.bin.extracted   _asa933-smp-k8.bin.extracted      _asav962-2.qcow2.extracted
_asa824-smp-k8.bin.extracted     _asa842-smp-k8.bin.extracted     _asa904-38-k8.bin.extracted   _asa917-13-k8.bin.extracted   _asa941-13-smp-k8.bin.extracted   _asav962-7.qcow2.extracted
_asa825-13-k8.bin.extracted      _asa843-8-k8.bin.extracted       _asa904-39-k8.bin.extracted   _asa917-4-k8.bin.extracted    _asa941-smp-k8.bin.extracted      _asav962.qcow2.extracted
_asa825-22-k8.bin.extracted      _asa843-k8.bin.extracted         _asa904-40-k8.bin.extracted   _asa917-6-k8.bin.extracted    _asa942-11-smp-k8.bin.extracted   _asav971.qcow2.extracted
_asa825-26-k8.bin.extracted      _asa843-smp-k8.bin.extracted     _asa904-42-k8.bin.extracted   _asa917-9-k8.bin.extracted    _asa942-6-smp-k8.bin.extracted
_asa825-33-k8.bin.extracted      _asa844-1-k8.bin.extracted       _asa904-5-k8.bin.extracted    _asa917-k8.bin.extracted      _asa942-smp-k8.bin.extracted
_asa825-41-k8.bin.extracted      _asa844-1-smp-k8.bin.extracted   _asa904-k8.bin.extracted      _asa921-k8.bin.extracted      _asa943-12-smp-k8.bin.extracted
_asa825-46-k8.bin.extracted      _asa844-3-k8.bin.extracted       _asa904-smp-k8.bin.extracted  _asa921-smp-k8.bin.extracted  _asa943-smp-k8.bin.extracted
fw$ info.sh --save-result --db-name /path/to/asafw/asadb.json
```

A database with already a bunch of firmware version is provided in the repo as
`asadb.json`.

If you simply want to list the mitigations, you simply go to the root folder 
containing all the extracted firmware and use it without any 
argument:

```
$ info.sh
```

## info.py

The following script is used by `info.sh` to fill a json database.

```
$ info.py -h
usage: info.py [-h] [-l] [-u UPDATE_INFO] [-i BIN_NAME] [-v VERBOSE]
               [-d DBNAME]

optional arguments:
  -h, --help      show this help message and exit
  -l              List migitations in all firmware versions
  -u UPDATE_INFO  Output from info.sh to update db
  -i BIN_NAME     firmware bin name to update or display
  -v VERBOSE      display more info
  -d DBNAME       json database name to read/list info from
```

Outside of its use by `info.sh`, its main interest is using the following 
command to display the summary of mitigations:

```
asafw$ info.py -l asadbg.json
```

Note that `info.py -l` can also be used to get the index (first column) of
a specific version in case it is required (e.g. for `lina.py`).

# Mitigation summary

Below is a copy of the output of `info.py -l asadbg.json`, formatted correctly 
for markdown:


| ID  | Version   |Arch|ASLR| NX |PIE|Can|RELRO|Sym|Strip|    Linux | Glibc | Heap allocator | Firmware                  |
|-----|-----------|----|----|----|---|---|-----|---|-----|----------|-------|----------------|---------------------------
| 000 |     8.0.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |             asa802-k8.bin |
| 001 |     8.0.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |             asa803-k8.bin |
| 002 |  8.0.4.16 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |          asa804-16-k8.bin |
| 003 |     8.0.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |             asa804-k8.bin |
| 004 |  8.0.5.23 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |          asa805-23-k8.bin |
| 005 |  8.0.5.28 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |          asa805-28-k8.bin |
| 006 |  8.0.5.31 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |          asa805-31-k8.bin |
| 007 |     8.0.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.6.x |             asa805-k8.bin |
| 008 |     8.1.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |         asa811-smp-k8.bin |
| 009 |  8.1.2.23 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |      asa812-23-smp-k8.bin |
| 010 |  8.1.2.49 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |      asa812-49-smp-k8.bin |
| 011 |  8.1.2.50 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |      asa812-50-smp-k8.bin |
| 012 |  8.1.2.55 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |      asa812-55-smp-k8.bin |
| 013 |  8.1.2.56 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |      asa812-56-smp-k8.bin |
| 014 |     8.1.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |         asa812-smp-k8.bin |
| 015 |     8.2.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |             asa821-k8.bin |
| 016 |     8.2.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |             asa822-k8.bin |
| 017 |     8.2.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.17.8 | 2.3.2 | dlmalloc 2.8.3 |         asa822-smp-k8.bin |
| 018 |     8.2.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |             asa823-k8.bin |
| 019 |     8.2.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |         asa823-smp-k8.bin |
| 020 |   8.2.4.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |           asa824-4-k8.bin |
| 021 |     8.2.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |             asa824-k8.bin |
| 022 |     8.2.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |         asa824-smp-k8.bin |
| 023 |  8.2.5.13 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-13-k8.bin |
| 024 |  8.2.5.22 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-22-k8.bin |
| 025 |  8.2.5.26 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-26-k8.bin |
| 026 |  8.2.5.33 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-33-k8.bin |
| 027 |  8.2.5.41 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-41-k8.bin |
| 028 |  8.2.5.46 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-46-k8.bin |
| 029 |  8.2.5.51 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-51-k8.bin |
| 030 |  8.2.5.52 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-52-k8.bin |
| 031 |  8.2.5.57 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-57-k8.bin |
| 032 |  8.2.5.59 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa825-59-k8.bin |
| 033 |     8.2.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |             asa825-k8.bin |
| 034 |     8.2.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |         asa825-smp-k8.bin |
| 035 |     8.3.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |             asa831-k8.bin |
| 036 |     8.3.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |         asa831-smp-k8.bin |
| 037 |  8.3.2.13 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa832-13-k8.bin |
| 038 |  8.3.2.25 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa832-25-k8.bin |
| 039 |  8.3.2.39 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa832-39-k8.bin |
| 040 |   8.3.2.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |           asa832-4-k8.bin |
| 041 |  8.3.2.40 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa832-40-k8.bin |
| 042 |  8.3.2.44 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |          asa832-44-k8.bin |
| 043 |  8.3.2.44 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |      asa832-44-smp-k8.bin |
| 044 |     8.3.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |             asa832-k8.bin |
| 045 |     8.3.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 | 2.3.2 | dlmalloc 2.8.3 |         asa832-smp-k8.bin |
| 046 |  8.4.1.11 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa841-11-k8.bin |
| 047 |     8.4.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa841-k8.bin |
| 048 |     8.4.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa841-smp-k8.bin |
| 049 |   8.4.2.8 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa842-8-k8.bin |
| 050 |     8.4.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa842-k8.bin |
| 051 |     8.4.2 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa842-smp-k8.bin |
| 052 |   8.4.3.8 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa843-8-k8.bin |
| 053 |     8.4.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa843-k8.bin |
| 054 |     8.4.3 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa843-smp-k8.bin |
| 055 |   8.4.4.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa844-1-k8.bin |
| 056 |   8.4.4.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |       asa844-1-smp-k8.bin |
| 057 |   8.4.4.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa844-3-k8.bin |
| 058 |   8.4.4.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa844-5-k8.bin |
| 059 |   8.4.4.9 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa844-9-k8.bin |
| 060 |     8.4.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa844-k8.bin |
| 061 |     8.4.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa845-k8.bin |
| 062 |     8.4.5 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa845-smp-k8.bin |
| 063 |   8.4.6.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa846-5-k8.bin |
| 064 |     8.4.6 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa846-k8.bin |
| 065 |     8.4.6 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa846-smp-k8.bin |
| 066 |  8.4.7.15 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-15-k8.bin |
| 067 |  8.4.7.26 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-26-k8.bin |
| 068 |  8.4.7.28 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-28-k8.bin |
| 069 |  8.4.7.29 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-29-k8.bin |
| 070 |  8.4.7.30 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-30-k8.bin |
| 071 |  8.4.7.31 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa847-31-k8.bin |
| 072 |     8.4.7 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa847-k8.bin |
| 073 |     8.4.7 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa847-smp-k8.bin |
| 074 |     8.6.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa861-smp-k8.bin |
| 075 |     9.0.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa901-k8.bin |
| 076 |     9.0.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa902-k8.bin |
| 077 |     9.0.2 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa902-smp-k8.bin |
| 078 |     9.0.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa903-k8.bin |
| 079 |     9.0.3 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa903-smp-k8.bin |
| 080 |  9.0.4.38 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa904-38-k8.bin |
| 081 |  9.0.4.39 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa904-39-k8.bin |
| 082 |  9.0.4.40 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa904-40-k8.bin |
| 083 |  9.0.4.42 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa904-42-k8.bin |
| 084 |   9.0.4.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa904-5-k8.bin |
| 085 |     9.0.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa904-k8.bin |
| 086 |     9.0.4 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa904-smp-k8.bin |
| 087 |   9.1.1.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa911-4-k8.bin |
| 088 |     9.1.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa911-k8.bin |
| 089 |     9.1.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa911-smp-k8.bin |
| 090 |     9.1.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa912-k8.bin |
| 091 |     9.1.2 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa912-smp-k8.bin |
| 092 |     9.1.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa913-k8.bin |
| 093 |     9.1.3 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa913-smp-k8.bin |
| 094 |   9.1.4.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa914-5-k8.bin |
| 095 |     9.1.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa914-k8.bin |
| 096 |     9.1.4 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa914-smp-k8.bin |
| 097 |  9.1.5.12 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa915-12-k8.bin |
| 098 |  9.1.5.16 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa915-16-k8.bin |
| 099 |  9.1.5.19 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa915-19-k8.bin |
| 100 |  9.1.5.21 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa915-21-k8.bin |
| 101 |     9.1.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa915-k8.bin |
| 102 |     9.1.5 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa915-smp-k8.bin |
| 103 |  9.1.6.10 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa916-10-k8.bin |
| 104 |  9.1.6.11 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa916-11-k8.bin |
| 105 |   9.1.6.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa916-4-k8.bin |
| 106 |     9.1.6 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa916-k8.bin |
| 107 |     9.1.6 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa916-smp-k8.bin |
| 108 |  9.1.7.12 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa917-12-k8.bin |
| 109 |  9.1.7.13 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa917-13-k8.bin |
| 110 |   9.1.7.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa917-4-k8.bin |
| 111 |   9.1.7.6 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa917-6-k8.bin |
| 112 |   9.1.7.9 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa917-9-k8.bin |
| 113 |     9.1.7 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa917-k8.bin |
| 114 |     9.2.1 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa921-k8.bin |
| 115 |     9.2.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa921-smp-k8.bin |
| 116 |   9.2.2.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa922-4-k8.bin |
| 117 |   9.2.2.4 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |       asa922-4-smp-k8.bin |
| 118 |     9.2.2 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa922-k8.bin |
| 119 |     9.2.3 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa923-k8.bin |
| 120 |     9.2.3 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa923-smp-k8.bin |
| 121 |  9.2.4.10 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa924-10-k8.bin |
| 122 |  9.2.4.13 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |      asa924-13-smp-k8.bin |
| 123 |  9.2.4.14 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa924-14-k8.bin |
| 124 |  9.2.4.18 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |          asa924-18-k8.bin |
| 125 |   9.2.4.5 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa924-5-k8.bin |
| 126 |   9.2.4.5 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |       asa924-5-smp-k8.bin |
| 127 |   9.2.4.8 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |           asa924-8-k8.bin |
| 128 |   9.2.4.8 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |       asa924-8-smp-k8.bin |
| 129 |     9.2.4 | 32 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |             asa924-k8.bin |
| 130 |     9.2.4 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa924-smp-k8.bin |
| 131 |     9.3.1 | 64 |  N |  N | N | N |   N | N |  N  | 2.6.29.6 |   2.9 | dlmalloc 2.8.3 |         asa931-smp-k8.bin |
| 132 | 9.3.2.200 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |     asa932-200-smp-k8.bin |
| 133 |     9.3.2 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |         asa932-smp-k8.bin |
| 134 |  9.3.3.11 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |      asa933-11-smp-k8.bin |
| 135 |   9.3.3.7 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |       asa933-7-smp-k8.bin |
| 136 |   9.3.3.9 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |       asa933-9-smp-k8.bin |
| 137 |     9.3.3 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |         asa933-smp-k8.bin |
| 138 |  9.4.1.13 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |      asa941-13-smp-k8.bin |
| 139 |     9.4.1 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |         asa941-smp-k8.bin |
| 140 |  9.4.2.11 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |      asa942-11-smp-k8.bin |
| 141 |   9.4.2.6 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |       asa942-6-smp-k8.bin |
| 142 |     9.4.2 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |         asa942-smp-k8.bin |
| 143 |  9.4.3.12 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |      asa943-12-smp-k8.bin |
| 144 |     9.4.3 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |         asa943-smp-k8.bin |
| 145 |     9.4.4 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |         asa944-smp-k8.bin |
| 146 |     9.5.1 | 64 |  Y |  N | Y | N |   N | N |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa951-smp-k8.bin |
| 147 |     9.5.2 | 64 |  Y |  N | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa952-smp-k8.bin |
| 148 |     9.5.3 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa953-smp-k8.bin |
| 149 |  9.6.1.10 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |      asa961-10-smp-k8.bin |
| 150 |     9.6.1 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa961-smp-k8.bin |
| 151 |   9.6.2.3 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |       asa962-3-smp-k8.bin |
| 152 |     9.6.2 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa962-smp-k8.bin |
| 153 |     9.7.1 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asa971-smp-k8.bin |
| 154 | 9.3.2.200 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |         asav932-200.qcow2 |
| 155 |  9.3.3.10 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |          asav933-10.qcow2 |
| 156 |  9.3.3.11 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |          asav933-11.qcow2 |
| 157 |   9.3.3.9 | 64 |  N |  Y | N | N |   N | N |  N  |  3.10.19 |  2.18 |   ptmalloc 2.x |           asav933-9.qcow2 |
| 158 |  9.4.1.13 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |          asav941-13.qcow2 |
| 159 | 9.4.1.200 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |         asav941-200.qcow2 |
| 160 |   9.4.1.6 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |           asav941-6.qcow2 |
| 161 |     9.4.1 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |             asav941.qcow2 |
| 162 |   9.4.2.6 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |           asav942-6.qcow2 |
| 163 |     9.4.2 | 64 |  N |  N | N | N |   N | N |  N  |  3.10.55 |  2.18 |   ptmalloc 2.x |             asav942.qcow2 |
| 164 | 9.5.2.204 | 64 |  Y |  N | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |         asav952-204.qcow2 |
| 165 |     9.6.1 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |             asav961.qcow2 |
| 166 |   9.6.2.2 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |           asav962-2.qcow2 |
| 167 |   9.6.2.7 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |           asav962-7.qcow2 |
| 168 |     9.6.2 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |             asav962.qcow2 |
| 169 |     9.7.1 | 64 |  Y |  Y | Y | N |   N | Y |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |             asav971.qcow2 |
| 170 |   9.8.1.5 | 64 |  Y |  Y | Y | N |   N | N |  N  |  3.10.62 |  2.18 |   ptmalloc 2.x |           asav981-5.qcow2 |
| ID  | Version   |Arch|ASLR| NX |PIE|Can|RELRO|Sym|Strip|    Linux | Glibc | Heap allocator | Firmware                  |


# End-of-life ASA versions

To our knowledge there isn't any summary of ASA branches being End-of-life (EOL)
- though an official list of EOL devices is
[here](http://www.cisco.com/c/en/us/products/hw/tsd_products_support_end-of-sale_and_end-of-life_products_list.html).
Feel free to contact us if we are missing something.  However, it is possible
to use
[the](http://www.cisco.com/c/en/us/support/security/asa-5500-series-next-generation-firewalls/products-security-advisories-list.html)
[Cisco](http://www.cisco.com/c/en/us/support/docs/csa/cisco-sa-20160210-asa-ike.html)
[ASA](http://www.cisco.com/c/en/us/support/docs/csa/cisco-sa-20160517-asa-xml.html)
[advisories](http://www.cisco.com/c/en/us/support/docs/csa/cisco-sa-20170208-asa.html)
to deduce branch EOL status. Last update of this table is July 2017.

 Cisco ASA Branch  | Latest Update | End-of-life? | Notes                               |
------------------ | ------------- | ------------ |------------------------------------ |
 7.2               | <= Feb 2016   | Yes          |                                     |
 8.0               | <= Feb 2016   | Yes          |                                     |
 8.1               | <= Feb 2016   | Yes          |                                     |
 8.2               | <= Feb 2016   | Yes          | Exceptional patch for IKE heap overflow |
 8.3               | <= Feb 2016   | Yes          |                                     |
 8.4               | <= May 2016   | Yes          |                                     |
 8.5               | <= Feb 2016   | Yes          |                                     |
 8.6               | <= Feb 2016   | Yes          |                                     |
 8.7               | <= May 2016   | Yes          |                                     |
 9.0               | <= Feb 2017   | Yes          |                                     |
 9.1               |               | No           |                                     |
 9.2               |               | No           |                                     |
 9.3               | <= Feb 2017   | Yes          |                                     |
 9.4               |               | No           |                                     |
 9.5               |               | No           |                                     |
 9.6               |               | No           |                                     |
 9.7               |               | No           |                                     |
 9.8               |               | No           |                                     |
