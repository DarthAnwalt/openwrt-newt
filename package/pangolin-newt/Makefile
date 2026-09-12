# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=pangolin-newt
PKG_VERSION:=1.15.0
PKG_RELEASE:=1

PKG_SOURCE:=newt-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/fosrl/newt/tar.gz/refs/tags/$(PKG_VERSION)?
PKG_HASH:=f4261cbf7bfc6e7fa0c63673b6a53dd02df88d0615ae6a60643b976677a9e32b
PKG_BUILD_DIR:=$(BUILD_DIR)/newt-$(PKG_VERSION)

PKG_MAINTAINER:=openwrt-newt contributors
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/fosrl/newt

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/../feeds/packages/lang/golang/golang-package.mk

define Package/pangolin-newt
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Newt client for Pangolin
  URL:=https://github.com/fosrl/newt
  DEPENDS:=+ca-bundle +jsonfilter $(GO_ARCH_DEPENDS)
endef

define Package/pangolin-newt/description
 Newt is the user-space tunnel client for Pangolin. This package integrates
 it with OpenWrt procd and UCI and deliberately leaves upgrades to apk.
endef

define Package/pangolin-newt/conffiles
/etc/config/newt
endef

define Build/Compile
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/bin
	+$(GO_PKG_VARS) $(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) \
		VERSION="$(PKG_VERSION)" \
		local
endef

define Package/pangolin-newt/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/newt $(1)/usr/bin/newt
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/newt $(1)/etc/init.d/newt
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/newt $(1)/etc/config/newt
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/newt-run $(1)/usr/libexec/newt-run
	$(INSTALL_BIN) ./files/usr/libexec/newt-migrate $(1)/usr/libexec/newt-migrate
	$(INSTALL_DIR) $(1)/usr/share/licenses/newt
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/newt/LICENSE
endef

$(eval $(call BuildPackage,pangolin-newt))
