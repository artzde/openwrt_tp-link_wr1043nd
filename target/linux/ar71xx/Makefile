#
# Copyright (C) 2008-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

ARCH:=mips
BOARD:=ar71xx
BOARDNAME:=Atheros AR7xxx/AR9xxx
FEATURES:=squashfs jffs2 targz mips16
CFLAGS:=-Os -pipe -march=24kc -mno-mips16 -mno-branch-likely -fno-caller-saves -mplt -mgp32 -msym32
SUBTARGETS:=generic nand

LINUX_VERSION:=3.3.8

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	kmod-gpio-button-hotplug kmod-ath9k kmod-wdt-ath79 swconfig \
	kmod-leds-gpio kmod-ledtrig-default-on kmod-ledtrig-netdev \
	wpad

define Target/Description
	Build firmware images for Atheros AR7xxx/AR9xxx based boards.
endef

$(eval $(call BuildTarget))
