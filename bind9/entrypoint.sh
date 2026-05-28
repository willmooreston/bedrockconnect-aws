#!/bin/bash
set -e

# Discover the public IP from EC2 instance metadata (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

echo "BedrockConnect bind9: redirecting featured servers to $PUBLIC_IP"

# Minecraft Bedrock featured server domains to redirect
DOMAINS=(
  "hivebedrock.network geo.hivebedrock.network"
  "inpvp.net play.inpvp.net"
  "lbsg.net mco.lbsg.net"
  "galaxite.net play.galaxite.net"
  "enchanted.gg play.enchanted.gg"
  "blossomcraft.org play.blossomcraft.org"
)

mkdir -p /var/cache/bind

# Write named.conf.options
cat > /etc/bind/named.conf.options <<EOF
options {
  directory "/var/cache/bind";
  recursion no;
  allow-query { any; };
  listen-on-v6 { none; };
};
EOF

# Write named.conf.local with a zone block per domain
: > /etc/bind/named.conf.local

for entry in "${DOMAINS[@]}"; do
  domain=$(echo "$entry" | awk '{print $1}')
  subdomain=$(echo "$entry" | awk '{print $2}')
  zonefile="/var/cache/bind/db.${domain}"

  cat >> /etc/bind/named.conf.local <<EOF
zone "${domain}" {
  type master;
  file "${zonefile}";
};
EOF

  cat > "$zonefile" <<EOF
\$TTL 60
@   IN  SOA ns1.${domain}. admin.${domain}. (
          1 ; serial
          60 ; refresh
          60 ; retry
          60 ; expire
          60 ; minimum TTL
        )
@         IN  NS   ns1.${domain}.
ns1       IN  A    ${PUBLIC_IP}
@         IN  A    ${PUBLIC_IP}
${subdomain%%.*}  IN  A    ${PUBLIC_IP}
EOF
done

exec named -g -u bind
