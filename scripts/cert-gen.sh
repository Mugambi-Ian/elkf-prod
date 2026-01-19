#!/bin/bash
set -e;

mkdir -p config/certs;

# Check if certificates already exist
if [ -f config/certs/instance/instance.crt ] && [ -f config/certs/instance/instance.key ] && [ -f config/certs/ca/ca.crt ]; then
  echo "Certificates found, checking expiration...";

  # Get certificate expiration date (format: notAfter=Mon Jan 15 12:00:00 2024 GMT)
  EXPIRY_STRING=$(openssl x509 -in config/certs/instance/instance.crt -noout -enddate | cut -d= -f2);

  # Convert to epoch (works in Linux containers)
  EXPIRY_EPOCH=$(date -d "$EXPIRY_STRING" +%s 2>/dev/null);

  if [ -n "$EXPIRY_EPOCH" ] && [ $EXPIRY_EPOCH -gt 0 ]; then
    CURRENT_EPOCH=$(date +%s);
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ));
    RENEWAL_THRESHOLD=30;

    if [ $DAYS_UNTIL_EXPIRY -lt $RENEWAL_THRESHOLD ]; then
      echo "Certificate expires in $DAYS_UNTIL_EXPIRY days (threshold: $RENEWAL_THRESHOLD days). Renewing...";
      # Backup old certificates
      mkdir -p config/certs/backup;
      cp -r config/certs/instance config/certs/ca config/certs/backup/ 2>/dev/null || true;
      # Remove old certificates to trigger regeneration
      rm -rf config/certs/instance config/certs/ca;
    else
      echo "Certificates are valid for $DAYS_UNTIL_EXPIRY more days. Skipping renewal.";
      # Ensure permissions are correct
      chown -R 1000:1000 config/certs;
      find config/certs -type d -exec chmod 750 {} \;
      find config/certs -type f -name "*.key" -exec chmod 600 {} \;
      find config/certs -type f -name "*.crt" -exec chmod 644 {} \;
      exit 0;
    fi;
  else
    echo "Could not parse certificate expiration date. Regenerating to be safe...";
    # Backup old certificates
    mkdir -p config/certs/backup;
    cp -r config/certs/instance config/certs/ca config/certs/backup/ 2>/dev/null || true;
    # Remove old certificates to trigger regeneration
    rm -rf config/certs/instance config/certs/ca;
  fi;
fi;

echo "Generating certificates...";
elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip;
unzip -o config/certs/ca.zip -d config/certs;
elasticsearch-certutil cert --silent --pem \
  --ca-cert config/certs/ca/ca.crt \
  --ca-key  config/certs/ca/ca.key \
  --dns elasticsearch --dns localhost \
  --ip 127.0.0.1 \
  -out config/certs/es.zip;
unzip -o config/certs/es.zip -d config/certs;
chown -R 1000:1000 config/certs;
find config/certs -type d -exec chmod 750 {} \;
find config/certs -type f -name "*.key" -exec chmod 600 {} \;
find config/certs -type f -name "*.crt" -exec chmod 644 {} \;
echo "Certificates generated successfully";
