# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zt
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=DarthAnwalt

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-zt
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for the official OpenWrt ZeroTier package
  DEPENDS:=+luci-base +zerotier
  CONFLICTS:=luci-app-zerotier
  # OpenWrt 25.12 records CONFLICTS in package metadata but its APK mkpkg
  # rule does not emit that field. APK v3 represents conflicts as a negated
  # runtime dependency, so keep both forms until the SDK rule is fixed.
  EXTRA_DEPENDS:=!luci-app-zerotier
  PKGARCH:=all
endef

define Package/luci-app-zt/description
	A modern JavaScript LuCI interface for the official OpenWrt ZeroTier
	package, including UCI network management, runtime status, service controls
	and independent APK updates for ZeroTier and this LuCI application.
endef

define Build/Compile
endef

define Package/luci-app-zt/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/zt
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/zt/overview.js \
		$(1)/www/luci-static/resources/view/zt/overview.js
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/luci-app-zt-update \
		$(1)/etc/init.d/luci-app-zt-update
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./root/usr/libexec/luci-app-zt-update \
		$(1)/usr/libexec/luci-app-zt-update
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-zt.json \
		$(1)/usr/share/luci/menu.d/luci-app-zt.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-zt.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-zt.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./root/usr/share/rpcd/ucode/luci-app-zt.uc \
		$(1)/usr/share/rpcd/ucode/luci-app-zt.uc
endef

define Package/luci-app-zt/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,luci-app-zt))
