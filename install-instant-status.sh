#!/usr/bin/env bash
# Ubuntu 22

# Accepts three optional flags:
# [v] - Install a custom version of Instant Status, defaults to 'master' This script is only guaranteed to work
#       with the latest major release
# [r] - Custom git remote for Instant Status, defaults to the main repo (https://github.com/instant-status/instant-status)
# [p] - a prefix for Parameter Store, used to fetch configs (`appConfig`, `apiConfig`, `env`) securely, defaults to
#       interactively editing example configs. Regardless of approach, config files inform the application build, and
#       should be considered as 'baked into' any image. If values change, a fresh install/image is recommended.
# e.g. /tmp/install-instant-status.sh -v 'v3.2.1' -r 'https://github.com/instant-status/instant-status.git'
# e.g. /tmp/install-instant-status.sh -p '/InstantStatus/app/dev'

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

OUTPUT_LOG="/tmp/log.txt"
workingDirectory='/home/ubuntu'

VERSION='master'
REMOTE='https://github.com/instant-status/instant-status.git'
PARAMETERSTORE_PREFIX=false

while getopts 'v:r:p:' flag; do
  case "${flag}" in
  v) VERSION="${OPTARG}" ;;
  r) REMOTE="${OPTARG}" ;;
  p) PARAMETERSTORE_PREFIX="${OPTARG}" ;;
  *)
    echo 'Unsupported flag'
    ;;
  esac
done

echo "$VERSION -- $REMOTE -- $PARAMETERSTORE_PREFIX"

function output_log() {
  if [[ "$3" == "echoAsWell" ]]; then
    echo "[$(date -u)] $1"
  fi
  echo "[$(date -u)] $1" >>"$2"
}

# ADD SWAP
echo "Making swap..."
sudo fallocate -l 2G /var/swap1 && sudo chmod 600 /var/swap1 && sudo mkswap /var/swap1 && sudo swapon /var/swap1 && sudo su - root -c "echo '/var/swap1 none swap sw 0 0' >> /etc/fstab;"

output_log "[INSTANTSTATUS] Starting Install..." "$OUTPUT_LOG" "echoAsWell"

# CREATING instantstatus USER #
output_log "[USER] Creating and Configuring instantstatus User..." "$OUTPUT_LOG" "echoAsWell"
sudo groupadd instantstatus >>"$OUTPUT_LOG" 2>&1
sudo useradd -g instantstatus instantstatus -s /bin/bash -d /usr/local/instantstatus >>"$OUTPUT_LOG" 2>&1
sudo mkdir -p /usr/local/instantstatus/ >>"$OUTPUT_LOG" 2>&1
sudo chown instantstatus: /usr/local/instantstatus/ >>"$OUTPUT_LOG" 2>&1
sudo cp /home/ubuntu/.bashrc /usr/local/instantstatus/.bashrc >>"$OUTPUT_LOG" 2>&1 && sudo chown instantstatus: /usr/local/instantstatus/.bashrc >>"$OUTPUT_LOG" 2>&1
sudo cp /home/ubuntu/.profile /usr/local/instantstatus/.profile >>"$OUTPUT_LOG" 2>&1 && sudo chown instantstatus: /usr/local/instantstatus/.profile >>"$OUTPUT_LOG" 2>&1
output_log "[USER] ...finished Creating and Configuring instantstatus User" "$OUTPUT_LOG" "echoAsWell"

# INSTALLING NVM, NODE #
output_log "[NVM, NODE] Installing NVM and Node..." "$OUTPUT_LOG" "echoAsWell"
sudo su - instantstatus -c 'wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash' >>"$OUTPUT_LOG" 2>&1
sudo su - instantstatus -c 'source /usr/local/instantstatus/.nvm/nvm.sh && nvm install 16' >>"$OUTPUT_LOG" 2>&1
output_log "[NVM, NODE] ...finished Installing NVM and Node" "$OUTPUT_LOG" "echoAsWell"

# INSTALLING PM2 #
output_log "[PM2] Installing PM2..." "$OUTPUT_LOG" "echoAsWell"
sudo su - instantstatus -c 'source /usr/local/instantstatus/.nvm/nvm.sh && npm install -g pm2 && pm2 install pm2-logrotate && pm2 set pm2-logrotate:compress true' >>"$OUTPUT_LOG" 2>&1
output_log "[PM2] ...finished Installing PM2" "$OUTPUT_LOG" "echoAsWell"

# INSTALLING NGINX, JQ #
output_log "[APT] Installing NGINX, JQ..." "$OUTPUT_LOG" "echoAsWell"
wget -O- https://nginx.org/keys/nginx_signing.key | sudo apt-key add - >>"$OUTPUT_LOG" 2>&1
echo "deb https://nginx.org/packages/ubuntu/ $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/Nginx.list >>"$OUTPUT_LOG" 2>&1
sudo apt update >>"$OUTPUT_LOG" 2>&1
sudo apt install -qq -y nginx jq >>"$OUTPUT_LOG" 2>&1
sudo mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
sudo service nginx restart
output_log "[APT] ...finished Installing NGINX, JQ" "$OUTPUT_LOG" "echoAsWell"

# CREATING APP STRUCTURE #
output_log "[APP] Creating Directory Structure..." "$OUTPUT_LOG" "echoAsWell"
sudo su - instantstatus -c 'mkdir -p /usr/local/instantstatus/releases' >>"$OUTPUT_LOG" 2>&1
sudo su - instantstatus -c 'ln -s /usr/local/instantstatus/releases/default current' >>"$OUTPUT_LOG" 2>&1
output_log "[APP] ...finished Creating Directory Structure" "$OUTPUT_LOG" "echoAsWell"

# INSTALLING APP #
output_log "[APP] Installing App..." "$OUTPUT_LOG" "echoAsWell"
sudo su - instantstatus -c 'cd /usr/local/instantstatus/releases && git clone "'"$REMOTE"'" -b "'"$VERSION"'" default'

sudo su - instantstatus -c 'cp /usr/local/instantstatus/current/ui/example.appConfig.ts /usr/local/instantstatus/current/ui/appConfig.ts'
sudo su - instantstatus -c 'cp /usr/local/instantstatus/current/is-config/src/example.apiConfig.ts /usr/local/instantstatus/current/is-config/src/apiConfig.ts'
sudo su - instantstatus -c 'cp /usr/local/instantstatus/current/is-config/.example.env /usr/local/instantstatus/current/is-config/.env'

if [[ "$PARAMETERSTORE_PREFIX" != 'false' ]]; then
  # INSTALLING AWSCLI #
  output_log "[APT] Installing AWSCLI..." "$OUTPUT_LOG" "echoAsWell"
  sudo apt install -qq -y python3-pip python3 >>"$OUTPUT_LOG" 2>&1
  sudo pip3 install awscli >>"$OUTPUT_LOG" 2>&1
  output_log "[APT] ...finished Installing AWSCLI" "$OUTPUT_LOG" "echoAsWell"

  aws ssm get-parameter --name "$PARAMETERSTORE_PREFIX/appConfig" --with-decryption --region eu-west-2 | jq -r '.Parameter.Value' | sudo tee /usr/local/instantstatus/current/ui/appConfig.ts >/dev/null 2>&1
  aws ssm get-parameter --name "$PARAMETERSTORE_PREFIX/apiConfig" --with-decryption --region eu-west-2 | jq -r '.Parameter.Value' | sudo tee /usr/local/instantstatus/current/is-config/src/apiConfig.ts >/dev/null 2>&1
  aws ssm get-parameter --name "$PARAMETERSTORE_PREFIX/env" --with-decryption --region eu-west-2 | jq -r '.Parameter.Value' | sudo tee /usr/local/instantstatus/current/is-config/.env >/dev/null 2>&1
else
  sudo su - instantstatus -c 'vim /usr/local/instantstatus/current/ui/appConfig.ts; vim /usr/local/instantstatus/current/is-config/src/apiConfig.ts; vim /usr/local/instantstatus/current/is-config/.env'
fi

sudo su - instantstatus -c 'source /usr/local/instantstatus/.nvm/nvm.sh && cd /usr/local/instantstatus/releases/default && npm run ci && npm run build'

output_log "[APP] ...finished Installing App" "$OUTPUT_LOG" "echoAsWell"

sudo cp /usr/local/instantstatus/current/tooling/nginx.conf.example /etc/nginx/conf.d/instantstatus.conf

sudo tee /etc/nginx/nginx.conf <<'EOF' >/dev/null 2>&1

user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user $hostname [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for" "$host" $request_time';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    gzip  on;
    gzip_types
        text/css
        text/xml
        text/plain
        text/javascript
        application/javascript
        application/json
        application/x-javascript
        application/xml
        application/xml+rss
        application/xhtml+xml
        application/x-font-ttf
        application/x-font-opentype
        application/vnd.ms-fontobject
        image/svg+xml
        image/x-icon
        application/rss+xml
        application/atom_xml;

    types_hash_max_size 2048;

    include /etc/nginx/conf.d/*.conf;
}
EOF
sudo service nginx restart

sudo su - instantstatus -c 'cp /usr/local/instantstatus/current/tooling/app.json /usr/local/instantstatus/app.json && source /usr/local/instantstatus/.nvm/nvm.sh && pm2 start /usr/local/instantstatus/app.json && pm2 save'
echo 'cd /usr/local/instantstatus/current' | sudo tee -a /usr/local/instantstatus/.bashrc >/dev/null 2>&1

output_log "[APP] MISC Tasks..." "$OUTPUT_LOG" "echoAsWell"
sudo vim /root/.ssh/authorized_keys
echo -n >/home/ubuntu/.ssh/authorized_keys
output_log "[APP] ...finished MISC Tasks" "$OUTPUT_LOG" "echoAsWell"

nodeVersion=$(ls /usr/local/instantstatus/.nvm/versions/node/)
sudo env PATH=$PATH:/usr/local/instantstatus/.nvm/versions/node/"$nodeVersion"/bin /usr/local/instantstatus/.nvm/versions/node/"$nodeVersion"/lib/node_modules/pm2/bin/pm2 startup systemd -u instantstatus --hp /usr/local/instantstatus
