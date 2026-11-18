#!/usr/bin/env bash
# Photomunity sunucu hazırlığı — temiz bir Ubuntu 24.04 sunucuda root olarak bir kez çalıştırılır:
#   curl -fsSL https://raw.githubusercontent.com/<kullanıcı>/photomunity/main/deploy/setup-server.sh -o setup.sh
#   sudo bash setup.sh
# Yaptıkları: sistem güncellemesi, otomatik güvenlik güncellemeleri, güvenlik duvarı (22/80/443),
# 2 GB takas alanı (web derlemesi için), Docker, "deploy" kullanıcısı ve /opt/photomunity klasörü.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "root olarak çalıştırın (sudo)"; exit 1; fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl git ufw unattended-upgrades fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! id deploy >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" deploy
  usermod -aG docker deploy
  mkdir -p /home/deploy/.ssh
  # root'a eklenen SSH anahtarları deploy kullanıcısına da kopyalanır
  [[ -f /root/.ssh/authorized_keys ]] && cp /root/.ssh/authorized_keys /home/deploy/.ssh/
  chown -R deploy:deploy /home/deploy/.ssh && chmod 700 /home/deploy/.ssh
fi

mkdir -p /opt/photomunity && chown deploy:deploy /opt/photomunity

echo
echo "Hazır. Sonraki adımlar DEPLOY.md'de: deploy kullanıcısıyla depoyu /opt/photomunity'ye klonlayın,"
echo "deploy/.env dosyasını doldurun ve 'docker compose up -d --build' çalıştırın."
