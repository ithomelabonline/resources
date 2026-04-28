echo "alias docker-up='docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets up -d'" >> ~/.bashrc
echo "alias docker-down='docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets down'" >> ~/.bashrc
echo "alias docker-pull='docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets pull'" >> ~/.bashrc
echo "alias docker-logs='docker compose --env-file /media/docker/scripts/.env --env-file /media/docker/secrets/.env.secrets logs -f'" >> ~/.bashrc
source ~/.bashrc
