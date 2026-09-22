# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pangolin-newt
PKG_VERSION:=1.17.0
PKG_RELEASE:=1
LUCI_TITLE:=LuCI support for Pangolin Newt
LUCI_DEPENDS:=+luci-base +pangolin-newt
LUCI_PKGARCH:=all

PKG_LICENSE:=MIT

# This package is copied into an extracted SDK and therefore has no Git
# metadata there. Use the pinned SDK epoch instead of build-time file mtimes.
override PKG_SOURCE_DATE_EPOCH:=$(SOURCE_DATE_EPOCH)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
