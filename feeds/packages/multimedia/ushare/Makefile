#
# Copyright (C) 2008-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ushare
PKG_VERSION:=1.1a
PKG_RELEASE:=4

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=http://ushare.geexbox.org/releases/
PKG_MD5SUM:=5bbcdbf1ff85a9710fa3d4e82ccaa251

PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/ushare
 SECTION:=multimedia
 CATEGORY:=Multimedia
 TITLE:= UPnP A/V & DLNA Media Server
 URL:=http://ushare.geexbox.org/
 DEPENDS:=+libdlna +libupnp +libffmpeg
endef

define Package/ushare/description
 uShare is a UPnP (TM) A/V & DLNA Media Server. It implements the server 
 component that provides UPnP media devices with information on available 
 multimedia files.
endef

MAKE_INSTALL_FLAGS+= \
	INSTALL="install" \

define Build/Configure
	$(SED) 's|#define DEFAULT_USHARE_NAME       "uShare"|#define DEFAULT_USHARE_NAME       "TL-WR1043ND"|' $(PKG_BUILD_DIR)/src/cfgparser.h
	$(SED) 's|GeeXboX Team|TP-LINK|' $(PKG_BUILD_DIR)/src/ushare.c
	$(SED) 's|ushare.geexbox.org|www.tp-link.com|' $(PKG_BUILD_DIR)/src/ushare.c
	$(SED) 's|uShare : DLNA Media Server|TL-WR1043ND : DLNA Media Server|' $(PKG_BUILD_DIR)/src/ushare.c
	$(SED) 's|USHARE-01|TL-WR1043ND|' $(PKG_BUILD_DIR)/src/ushare.c
	$(SED) 's|GeeXboX Team|TP-LINK|' $(PKG_BUILD_DIR)/src/ushare.h
	$(SED) 's|ushare.geexbox.org|www.tp-link.com|' $(PKG_BUILD_DIR)/src/ushare.h
	$(SED) 's|uShare : DLNA Media Server|TL-WR1043ND : DLNA Media Server|' $(PKG_BUILD_DIR)/src/ushare.h
	# this is *NOT* GNU configure
	( cd $(PKG_BUILD_DIR); \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) -Wl,-rpath-link=$(STAGING_DIR)/usr/lib" \
		PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig" \
		PKG_CONFIG_LIBDIR="$(STAGING_DIR)/usr/lib/pkgconfig" \
		./configure \
		--cross-compile \
		--cross-prefix="$(TARGET_CROSS)" \
		--prefix="/usr" \
		--sysconfdir="/etc" \
		--enable-dlna \
		--disable-debug \
	)
endef

define Package/ushare/conffiles
/etc/config/ushare
/etc/ushare.conf
endef

define Package/ushare/install
	$(INSTALL_DIR) $(1)/etc
	$(CP) $(PKG_INSTALL_DIR)/etc/ushare.conf $(1)/etc/
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/ushare $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/$(PKG_NAME).config $(1)/etc/config/$(PKG_NAME)
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/$(PKG_NAME).init $(1)/etc/init.d/$(PKG_NAME)
endef

$(eval $(call BuildPackage,ushare))
