#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"


# 执行自定义设置脚本
CUSTOM_SCRIPT="/etc/custom-settings.sh"
[ -f "$CUSTOM_SCRIPT" ] && sh "$CUSTOM_SCRIPT" >> $LOGFILE 2>&1

# 保存当前的IP地址（如果已设置）
CURRENT_IP=$(uci get network.lan.ipaddr 2>/dev/null)

# 清除所有 DHCP 相关配置
for opt in proto ipaddr netmask gateway dns ip6assign; do
    uci delete network.lan.$opt 2>/dev/null
done

# 设置静态 IP
uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.ip6assign='60'

# 恢复之前的IP地址或使用默认值
if [ -n "$CURRENT_IP" ]; then
    uci set network.lan.ipaddr="$CURRENT_IP"
else
    uci set network.lan.ipaddr='10.10.10.1'
fi

# 网桥设置
lan_section=$(uci show network | awk -F '[.=]' '/\.\@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
[ -n "$lan_section" ] && uci set network.lan.device="br-lan"

# PPPoE WAN 设置
[ "$enable_pppoe" = "yes" ] && {
    uci set network.wan=interface
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
    echo "PPPoE settings applied" >> $LOGFILE
}

# 提交网络配置
uci commit network
# 重新加载网络服务
/etc/init.d/network reload
# 等待网络服务启动
sleep 2
# 显示最终的IP配置
uci show network.lan >> $LOGFILE

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by leenkon"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

exit 0
