docker compose down
docker compose up -d

# Wait for startup
sleep 10

# Configure with static IPs
docker exec ts-portainer tailscale serve --bg --https 443 http://172.20.1.10:9000
docker exec ts-ittools tailscale serve --bg --https 443 http://172.20.2.10:80
docker exec ts-syncthing tailscale serve --bg --https 443 http://172.20.3.10:8384

# Verify
docker exec ts-portainer tailscale serve status
docker exec ts-ittools tailscale serve status
docker exec ts-syncthing tailscale serve status
