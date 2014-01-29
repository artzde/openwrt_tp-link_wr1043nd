#! /bin/bash
directory=$HOME/openwrt/TL-WR1043ND/attitude_adjustment/build_dir/target-mips_uClibc-0.9.33.2/luci-0.11+svn9928/*
for file in $( find $directory -name '*.css' )
do
  echo $file
  java -jar yuicompressor-2.4.8pre.jar -o "$file-min.css" "$file"
  mv "$file-min.css" "$file"
done 
