#! /bin/bash
md5sum bin/ar71xx/openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-*.bin > bin/ar71xx/md5sum.txt || { echo 'md5sum is not installed' exit 1;}