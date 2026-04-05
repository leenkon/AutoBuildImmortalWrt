#!/bin/bash
# Log file for debugging
# 目前暂不支持第三方软件apk 待后续开发 仓库内可以集成
source shell/custom-packages.sh
#echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

# 创建自定义设置脚本，直接设置 UCI 配置
cat << 'EOF' > /home/build/immortalwrt/files/etc/custom-settings.sh
#!/bin/sh
[ -n "${CUSTOM_ROUTER_IP}" ] && uci set network.lan.ipaddr="${CUSTOM_ROUTER_IP}"

[ -n "${CUSTOM_HOSTNAME_VAL}" ] && uci set system.@system[0].hostname="${CUSTOM_HOSTNAME_VAL}"

# PPPoE settings
[ "${ENABLE_PPPOE}" = "yes" ] && [ -n "${PPPOE_ACCOUNT}" ] && [ -n "${PPPOE_PASSWORD}" ] && {
    uci set network.wan=interface
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="${PPPOE_ACCOUNT}"
    uci set network.wan.password="${PPPOE_PASSWORD}"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
}

uci commit
EOF

chmod +x /home/build/immortalwrt/files/etc/custom-settings.sh

# 替换环境变量
sed -i "s|\${CUSTOM_ROUTER_IP}|${CUSTOM_ROUTER_IP}|g; s|\${CUSTOM_HOSTNAME_VAL}|${CUSTOM_HOSTNAME_VAL}|g; s|\${ENABLE_PPPOE}|${ENABLE_PPPOE}|g; s|\${PPPOE_ACCOUNT}|${PPPOE_ACCOUNT}|g; s|\${PPPOE_PASSWORD}|${PPPOE_PASSWORD}|g" /home/build/immortalwrt/files/etc/custom-settings.sh

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= imm仓库内的插件==============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
#24.10
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES xray-core hysteria luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"

# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件 暂时注释
#PACKAGES="$PACKAGES $CUSTOM_PACKAGES"


# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
