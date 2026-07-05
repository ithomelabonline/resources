docker compose down
mkdir /media/docker/configs/dsm
sudo chown -R ubuntu:docker /media/docker/configs/dsm
wget -O /media/docker/configs/dsm/DSM_VirtualDSM_72806.pat "https://global.synologydownload.com/download/DSM/release/7.2.2/72806/DSM_VirtualDSM_72806.pat"
sudo chown -R ubuntu:docker /media/docker/configs/dsm
set -a
source /media/docker/scripts/.env
source /media/docker/secrets/.env.secrets
set +a
docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets up -d
#docker-up
sleep 15
docker exec ts-dsm tailscale serve -bg http://172.20.9.1:5000
