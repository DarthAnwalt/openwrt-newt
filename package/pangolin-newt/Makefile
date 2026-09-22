# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=pangolin-newt
PKG_VERSION:=1.17.0
PKG_RELEASE:=1

PKG_SOURCE:=newt-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/fosrl/newt/tar.gz/refs/tags/$(PKG_VERSION)?
PKG_HASH:=968fdbbdb784b84dde16479740b8e6f9d6da4173f0343f47b765632a5f3e391e
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
		GOFLAGS="-trimpath -buildvcs=false" \
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

define Package/pangolin-newt/postinst
#!/bin/sh
# APK preserves a pre-existing launcher in /etc and writes the packaged copy as
# .apk-new. Promote it only when the active file is recognisably the legacy
# launcher and UCI already contains complete credentials. User-customised
# package launchers remain untouched.
if [ -z "$${IPKG_INSTROOT}" ] && \
   [ -r /etc/init.d/newt ] && \
   [ -r /etc/init.d/newt.apk-new ] && \
   ! grep -Fq '/usr/libexec/newt-run' /etc/init.d/newt && \
   grep -Fq '/usr/libexec/newt-run' /etc/init.d/newt.apk-new && \
   [ -n "$$(uci -q get newt.main.endpoint 2>/dev/null)" ] && \
   [ -n "$$(uci -q get newt.main.id 2>/dev/null)" ] && \
   [ -n "$$(uci -q get newt.main.secret 2>/dev/null)" ]; then
	umask 077
	backup="/root/newt-launcher-migration-$$(date +%Y%m%d-%H%M%S)-$$$$"
	mkdir -m 0700 "$${backup}"
	cp -p /etc/init.d/newt "$${backup}/newt.legacy"
	cp -p /etc/init.d/newt.apk-new "$${backup}/newt.package"
	/etc/init.d/newt stop 2>/dev/null || true
	mv /etc/init.d/newt "$${backup}/newt.legacy.active"
	mv /etc/init.d/newt.apk-new /etc/init.d/newt
	chmod 0755 /etc/init.d/newt
	/etc/init.d/newt enable
	/etc/init.d/newt restart
	logger -t pangolin-newt "legacy launcher migrated; backup: $${backup}"
fi
exit 0
endef

$(eval $(call BuildPackage,pangolin-newt))
