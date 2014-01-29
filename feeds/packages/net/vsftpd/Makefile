#
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=vsftpd
PKG_VERSION:=3.0.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://security.appspot.com/downloads/
PKG_MD5SUM:=8b00c749719089401315bd3c44dddbb2

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(BUILD_VARIANT)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/vsftpd
  SUBMENU:=File Transfer
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A fast and secure FTP server
  URL:=http://vsftpd.beasts.org/
  VARIANT:=notls
  TITLE+= (no TLS)
  MAINTAINER:=Cezary Jackiewicz <cezary@eko.one.pl>
endef

define Package/vsftpd-tls
  SUBMENU:=File Transfer
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A fast and secure FTP server
  URL:=http://vsftpd.beasts.org/
  VARIANT:=tls
  TITLE+= (TLS)
  MAINTAINER:=Cezary Jackiewicz <cezary@eko.one.pl>
  DEPENDS+=+libopenssl
endef

define Package/vsftpd/conffiles
/etc/vsftpd.conf
endef

Package/vsftpd-tls/conffiles=$(Package/vsftpd/conffiles)

ifeq ($(BUILD_VARIANT),notls)
  define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		vsftpd
  endef
endif

ifeq ($(BUILD_VARIANT),tls)
  define Build/Compile
	$(SED) 's/#undef VSF_BUILD_SSL/#define VSF_BUILD_SSL/' $(PKG_BUILD_DIR)/builddefs.h
	$(SED) 's/LIBS	=	-lcrypt -lnsl/LIBS	=	-lcrypt -lnsl -lssl -lcrypto/' $(PKG_BUILD_DIR)/Makefile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		vsftpd
  endef
endif

define Package/vsftpd/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(PKG_NAME) $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_CONF) ./files/$(PKG_NAME).conf $(1)/etc/$(PKG_NAME).conf
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/$(PKG_NAME).init $(1)/etc/init.d/$(PKG_NAME)
endef

Package/vsftpd-tls/install=$(Package/vsftpd/install)

$(eval $(call BuildPackage,vsftpd))
$(eval $(call BuildPackage,vsftpd-tls))
