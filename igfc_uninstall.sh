#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "請使用 root 權限運行此腳本"
  echo "Please run this script with root privileges"
  exit
fi

systemctl stop infinirc-gpu-fan-control.service
systemctl disable infinirc-gpu-fan-control.service
rm /etc/systemd/system/infinirc-gpu-fan-control.service
systemctl daemon-reload

rm /usr/local/bin/infinirc_gpu_fan_control
rm /usr/local/src/infinirc_gpu_fan_control.c
rm /etc/infinirc_gpu_fan_control.conf
rm /etc/infinirc_gpu_fan_curve.json
rm /etc/infinirc_gpu_fan_curve.json.README

sed -i '/alias igfc/d' /etc/bash.bashrc

nvidia-smi -pm 0

echo "Infinirc GPU Fan Control 已成功卸載"
echo "Infinirc GPU Fan Control has been successfully uninstalled"
echo "請重新啟動以確保所有更改生效"
echo "Please reboot to ensure all changes take effect"