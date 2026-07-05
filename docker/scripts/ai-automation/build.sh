source /media/docker/scripts/.env
source /media/docker/secrets/.env.secrets

docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets down
docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets up -d
docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets down
sudo chown -R ${PUID}:${PGID} ${CONFIG}/n8n/
sudo chown -R ${PUID}:${PGID} ${CONFIG}/open-webui
docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets up -d

# Wait for startup
sleep 60

# Configure with static IPs
docker exec ts-n8n tailscale serve --bg --https 443 http://localhost:5678
docker exec ts-open-webui tailscale serve --bg --https 443 http://localhost:8080

# Verify
docker exec ts-n8n tailscale serve status
docker exec ts-open-webui tailscale serve status
