#!/bin/bash
# REALITY相关默认设置
port=443
fingerprint="chrome"
spiderx=""
domains=("www.mitsubishi.com" "updates.cdn-apple.com" "gadebate.un.org" "www.cdnetworks.com" "news.un.org" "api.datapacket.com" 
         "yelp.com" "concert.io" "jstor.org" "www.cisco.com" "s0.awsstatic.com" "d1.awsstatic.com" "www.python.org" 
         "www.cosmopolitan.com" "archive.cloudera.com" "www.shopjapan.co.jp" "www.boots.com" "download-installer.cdn.mozilla.net")

# 获取UUID和HOST
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
export HOST=${HOST:-$(curl ipv4.ip.sb)}

hysni=$(curl -s ipv6.ip.sb || curl -s ipv4.ip.sb)
hysni="$(echo $hysni | sed 's/:/-/g' | sed 's/\./-/g').sslip.io"

# 安装Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成SNI域名和vmess端口号
uuid_short=$(echo "$UUID" | head -c 8)
seed=$((16#$uuid_short))
vmessport=$(($seed % 8000 + 2000)) 
domain=${domains[$(($seed % 18))]}

# 生成私钥公钥
private_key=$(echo -n ${UUID} | md5sum | head -c 32 | base64 -w 0 | tr '+/' '-_' | tr -d '=')
tmp_key=$(echo -n ${private_key} | xargs xray x25519 -i)
private_key=$(echo ${tmp_key} | awk '{print $3}')
public_key=$(echo ${tmp_key} | awk '{print $6}')

# 打开BBR
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
sysctl -p 

# 配置config.json
cat > /usr/local/etc/xray/config.json <<-EOF
{ 
  "log": {
    "access": "none",
    "error": "/var/log/xray/error.log",
    "loglevel": "error"
  },
  "inbounds": [
    {
        "listen": "0.0.0.0",
        "port": ${vmessport},
        "protocol": "vmess",
        "settings": {
            "clients": [
                {
                    "id": "${UUID}"
                }
            ]
        },
        "streamSettings": {
            "network": "tcp"
        }
    },
    {
      "listen": "0.0.0.0",
      "port": ${port},    
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",   
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${domain}:443",    
          "xver": 0,
          "serverNames": ["${domain}"], 
          "privateKey": "${private_key}",  
          "shortIds": [""] 
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "dns": {
    "servers": [
      "8.8.8.8",
      "8.8.4.4",
      "2001:4860:4860::8888",
      "2606:4700:4700::1111",
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF

# 重启 Xray
service xray restart

# hy2
bash <(curl -fsSL https://get.hy2.sh/)

cat > /etc/hysteria/config.yaml <<-EOF
listen: :1443

acme:
  domains:
    - ${hysni}
  email: your@${hysni}
  ca: zerossl

auth:
  type: password
  password: ${UUID}
  
EOF

# mport
iptables -t nat -A PREROUTING -i eth0 -p udp --dport 10000:15000 -j DNAT --to-destination :1443
ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 10000:15000 -j DNAT --to-destination :1443

systemctl restart hysteria-server
systemctl enable hysteria-server

# 链接生成
vless_reality_url="vless://${UUID}@${HOST}:${port}?flow=xtls-rprx-vision&encryption=none&type=tcp&security=reality&sni=${domain}&fp=${fingerprint}&pbk=${public_key}&sid=${shortid}&spx=${spiderx}&#Reality_${HOST}_$(date +%H%M)"
temp_url='{"add":"IP","aid":"0","alpn":"","fp":"","host":"","id":"UUID","net":"tcp","path":"","port":"VMESSPORT","ps":"Vmess_IP_TIME","scy":"auto","sni":"","tls":"","type":"","v":"2"}'
o_vmess_url=$(sed -e "s/IP/${HOST}/g" \
                   -e "s/UUID/${UUID}/g" \
                   -e "s/VMESSPORT/${vmessport}/g" \
                   -e "s/TIME/$(date +%H%M)/g" <<< "${temp_url}")
vmess_url=$(echo -n "${o_vmess_url}" | base64 -w 0)
hy_url="hy2://${UUID}@${HOST}:1443?sni=${hysni}"

# 节点信息保存到文件中
echo "---------- VLESS Reality URL ----------" > ~/_xray_url_
echo $vless_reality_url >> ~/_xray_url_
echo  >> ~/_xray_url_
echo "---------- Vmess URL ----------" >> ~/_xray_url_
echo "${HOST}:${vmessport}" >> ~/_xray_url_
echo "vmess://${vmess_url}" >> ~/_xray_url_
echo >> ~/_xray_url_
echo "---------- HY2 URL ----------" >> ~/_xray_url_
echo $hy_url >> ~/_xray_url_
echo "hy2协议可选打开配置:" >> ~/_xray_url_
echo "端口跳跃10000-15000；上行/下行带宽依据客户端网络情况设置；正确设置可提高使用体验" >> ~/_xray_url_
echo >> ~/_xray_url_
echo "以上节点信息保存在 ~/_xray_url_ 中, 日后用 cat _xray_url_ 查看" >> ~/_xray_url_
echo >> ~/_xray_url_
echo "若你重装本机系统，可以使用下面的脚本恢复到相同配置" >> ~/_xray_url_
if [[ ${HOST} =~ \. && ${HOST} =~ [[:alpha:]] ]]; then
    insert="HOST=${HOST} "
fi
echo "${insert}UUID=${UUID} bash <(curl -L https://github.com/arcmosh/xray-hy2-muti/raw/main/install.sh)" >> ~/_xray_url_

#展示
echo
cat ~/_xray_url_
