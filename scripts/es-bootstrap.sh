#!/bin/sh
set -e;

echo "Waiting for Elasticsearch...";
until curl -sk -u elastic:${ELASTIC_PASSWORD} https://elasticsearch:9200/_cluster/health >/dev/null 2>&1; do
  echo "Elasticsearch not ready, waiting...";
  sleep 2;
done;

# Check if bootstrap is already complete
TEMPLATE_EXISTS=$(curl -sk -u elastic:${ELASTIC_PASSWORD} -o /dev/null -w "%{http_code}" https://elasticsearch:9200/_index_template/logs-default-template);
ILM_EXISTS=$(curl -sk -u elastic:${ELASTIC_PASSWORD} -o /dev/null -w "%{http_code}" https://elasticsearch:9200/_ilm/policy/logs-policy);
API_KEY_EXISTS=$([ -f /secrets/logstash_api_key ] && echo "yes" || echo "no");

if [ "$TEMPLATE_EXISTS" = "200" ] && [ "$ILM_EXISTS" = "200" ] && [ "$API_KEY_EXISTS" = "yes" ]; then
  echo "Bootstrap already completed, skipping setup...";
  exit 0;
fi;

echo "Running bootstrap setup...";

echo "Setting kibana_system password...";
RESPONSE=$(curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X POST https://elasticsearch:9200/_security/user/kibana_system/_password \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}");

# Password update is idempotent - ignore errors if already set
if echo "$RESPONSE" | grep -q "\"error\"" && ! echo "$RESPONSE" | grep -q "validation_exception"; then
  echo "Warning: Password update response: $RESPONSE";
fi;

# Only create API key if it doesn't exist
if [ "$API_KEY_EXISTS" != "yes" ]; then
  echo "Creating Logstash API key...";
  API_KEY=$(curl -sk -u elastic:${ELASTIC_PASSWORD} \
    -X POST https://elasticsearch:9200/_security/api_key \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"logstash-ingest\",
      \"role_descriptors\": {
        \"logstash_writer\": {
          \"cluster\": [\"monitor\", \"manage_index_templates\", \"manage_ilm\"],
          \"index\": [{
            \"names\": [\"logs-*\", \"filebeat-*\"],
            \"privileges\": [\"create_index\", \"create\", \"write\", \"manage\"]
          }]
        }
      }
    }" | sed -n "s/.*\"encoded\":\"\\([^\"]*\\)\".*/\\1/p");

  if [ -z "$API_KEY" ]; then
    echo "Failed to create API key";
    exit 1;
  fi;

  echo "$API_KEY" > /secrets/logstash_api_key;
  chmod 600 /secrets/logstash_api_key;
  echo "API key created successfully";
else
  echo "API key already exists, skipping creation...";
fi;

# Update index template (idempotent)
if [ "$TEMPLATE_EXISTS" != "200" ]; then
  echo "Setting default index template for compression and performance...";
else
  echo "Updating index template...";
fi;
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X PUT "https://elasticsearch:9200/_index_template/logs-default-template" \
  -H "Content-Type: application/json" \
  -d "{
    \"index_patterns\": [\"logs-*\", \"filebeat-*\"],
    \"priority\": 200,
    \"template\": {
      \"settings\": {
        \"index.codec\": \"best_compression\",
        \"index.merge.policy.max_merged_segment\": \"2gb\",
        \"index.refresh_interval\": \"2s\",
        \"index.number_of_shards\": 1,
        \"index.number_of_replicas\": 0
      }
    }
  }" >/dev/null 2>&1;

# Update ILM policy (idempotent)
if [ "$ILM_EXISTS" != "200" ]; then
  echo "Setting up index lifecycle policy...";
else
  echo "Updating index lifecycle policy...";
fi;
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X PUT "https://elasticsearch:9200/_ilm/policy/logs-policy" \
  -H "Content-Type: application/json" \
  -d "{
    \"policy\": {
      \"phases\": {
        \"hot\": {
          \"actions\": {
            \"rollover\": {
              \"max_size\": \"2gb\",
              \"max_age\": \"3d\",
              \"max_docs\": 200000
            },
            \"set_priority\": {
              \"priority\": 100
            }
          }
        },
        \"warm\": {
          \"min_age\": \"7d\",
          \"actions\": {
            \"set_priority\": {
              \"priority\": 50
            },
            \"forcemerge\": {
              \"max_num_segments\": 1
            },
            \"shrink\": {
              \"number_of_shards\": 1
            },
            \"allocate\": {
              \"number_of_replicas\": 0
            }
          }
        },
        \"delete\": {
          \"min_age\": \"90d\",
          \"actions\": {
            \"delete\": {}
          }
        }
      }
    }
  }" >/dev/null 2>&1;

echo "Bootstrap completed successfully";
