# xray-hy2-muti

同时搭建 reality（443端口），裸vmess随机端口， hy2（53端口）。无需自备域名。支持重装系统后一键恢复服务。

hy2 在53端口跑是因为某些运营商对udp限流严重，443/QUIC也不太行
```
bash <(curl -L https://github.com/arcmosh/xray-hy2-muti/raw/main/install.sh)
```
