# Logger Stack

A production-ready, secure, and performant logging stack using the Elastic Stack (Elasticsearch, Logstash, Kibana) and Filebeat. This stack is orchestrated with Docker Compose and is designed with security and scalability in mind.

## Features

-   **Secure by Default**: End-to-end encryption with TLS for all components. Passwords and sensitive configurations are managed via environment variables.
-   **Performant**: Pre-configured resource limits for each service to ensure stable operation. These should be reviewed and adjusted based on your specific workload and host resources.
-   **Centralized Logging**: Filebeat ships logs from a designated volume, Logstash processes and enriches them, and Elasticsearch provides powerful indexing and search capabilities. Kibana offers a rich UI for visualization and analysis.
-   **Automated Setup**: Bootstrap service automatically configures passwords, API keys, index templates, and ILM policies on first run. Setup services are idempotent and skip if already configured.
-   **Low Latency**: Optimized for near real-time log visibility with 2-second index refresh intervals and optimized batch processing.
-   **Scalable**: Built on Docker, allowing for straightforward scaling and deployment across different environments.

## Requirements

-   Docker Engine
-   Docker Compose
-   `openssl` (for generating secure credentials)

---

## Deployment Instructions

### Step 1: Clone the Repository

```bash
git clone <your-repository-url>
cd logger-stack
```

### Step 2: Configure Environment Variables

Create a `.env` file from the provided example:

```bash
cp .env.example .env
```

Edit the `.env` file and populate it with secure passwords. Use the following command to generate secure passwords:

```bash
openssl rand -hex 16
```

Your `.env` file should contain:

```ini
# .env
ELASTIC_PASSWORD=<generated-password>
KIBANA_SYSTEM_PASSWORD=<generated-password>
```

**Note**: 
- `ELASTIC_PASSWORD`: Password for the `elastic` superuser account
- `KIBANA_SYSTEM_PASSWORD`: Password for the `kibana_system` user (used by Kibana to connect to Elasticsearch)

### Step 3: Create External Log Volume

This stack is configured to ingest logs from a Docker named volume called `app-logs`. Create this volume before starting the stack. Your application containers should mount this volume to write their log files.

```bash
docker volume create app-logs
```

### Step 4: Launch the Stack

Launch the entire stack. The setup process is automated and idempotent:

1. The `cert_gen` service automatically generates TLS certificates for Elastic components (skips if certificates already exist)
2. The `es_bootstrap` service waits for Elasticsearch to be healthy, then automatically:
   - Sets the `kibana_system` user password
   - Creates a Logstash API key for secure log ingestion
   - Configures default index templates with compression and performance optimizations
   - Sets up Index Lifecycle Management (ILM) policies for automatic log rotation and retention
   - **Skips setup if already completed** (checks for existing templates, policies, and API keys)

```bash
docker compose up --build -d
```

Your Kibana instance will be available at `http://localhost:5601` once all services are healthy.

**Note**: 
- For production deployments, you may want to add an Nginx reverse proxy in front of Kibana for HTTPS termination. 
- You can safely restart the stack with `docker compose down` (without `-v`) and `docker compose up -d` without losing data or needing to reconfigure. Setup services will detect existing configuration and skip automatically.

---

## Architecture

The stack consists of the following services:

- **Elasticsearch**: Stores and indexes logs. Configured with TLS, security enabled, and optimized for low-memory environments (256MB heap). Uses 2-second refresh intervals for near real-time log visibility.
- **Kibana**: Web UI for log visualization and analysis. Exposed on port 5601.
- **Logstash**: Processes logs from Filebeat and sends them to Elasticsearch. Uses API key authentication. Optimized with small batch sizes (50 events) and low delay (10ms) for low latency.
- **Filebeat**: Collects logs from the `app-logs` volume and Docker containers, ships them to Logstash. Configured with 1-second flush intervals for fast log delivery.
- **cert_gen**: Certificate generation service. Idempotent - checks expiration and automatically renews if certificates expire within 30 days, otherwise skips if certificates are still valid.
- **es_bootstrap**: One-time setup service that configures passwords, API keys, index templates, and ILM policies. Idempotent - skips if setup is already complete.

All main services are configured with `restart: unless-stopped` to automatically restart on failure or system reboot.

## Maintenance & Security

### Resource Allocation

The CPU and memory limits in `docker-compose.yml` are set to reasonable defaults optimized for a 2GB droplet:
- Elasticsearch: 768MB limit, 256MB Java heap
- Kibana: 640MB limit, 400MB Node.js heap
- Logstash: 384MB limit, 128MB Java heap
- Filebeat: 128MB limit

Monitor your resource usage and adjust them according to your host's capacity and the stack's workload.

### Index Lifecycle Management (ILM)

Index Lifecycle Management is automatically configured by the `es_bootstrap` service with the following policy:
- **Hot phase**: Indices roll over at 2GB, 3 days, or 200k documents
- **Warm phase**: After 7 days, indices are force-merged, shrunk to 1 shard, and replicas removed
- **Delete phase**: Indices are deleted after 90 days

You can modify the ILM policy in the `es_bootstrap` service command in `docker-compose.yml` or manage it through Kibana's UI.

### Performance & Latency

The stack is optimized for low latency:
- **Index refresh interval**: 2 seconds (logs appear in Kibana within 2-3 seconds)
- **Logstash batch size**: 50 events with 10ms delay
- **Filebeat flush interval**: 1 second
- **Filebeat scan frequency**: 1 second

These settings ensure logs appear in Kibana quickly while maintaining lean resource usage. You can adjust these values in `docker-compose.yml` and `filebeat/filebeat.yml` if needed.

### Log Ingestion

Logs are ingested from:
1. The `app-logs` Docker volume: Place JSON log files in `/usr/local/var/log/*.log` (mounted from the volume)
2. Docker container logs: Filebeat automatically collects logs from all Docker containers

Logs are indexed with the pattern `{service-name}-{YYYY.MM.dd}` based on the `service.name` field in your log entries.

### Restarting the Stack

You can safely restart the stack without losing data:

```bash
docker compose down
docker compose up -d
```

**Important**: Do not use `docker compose down -v` unless you want to delete all volumes and lose all data. Without the `-v` flag:
- All data persists (Elasticsearch indices, certificates, API keys)
- Setup services (`cert_gen` and `es_bootstrap`) automatically detect existing configuration and skip
- The stack starts quickly without re-running setup steps

### Certificate Management

The TLS certificates generated by `cert_gen` have a **default validity period of 3 years (1095 days)**. 

**Automatic Renewal**: The `cert_gen` service automatically checks certificate expiration on startup and renews certificates if they expire within 30 days. This happens automatically when you run `docker compose up` - no manual intervention needed.

**To check certificate expiration manually:**
```bash
# Check via Elasticsearch API
curl -k -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_ssl/certificates

# Or check the certificate file directly
docker compose exec elasticsearch openssl x509 -in /usr/share/elasticsearch/config/certs/instance/instance.crt -noout -dates
```

**Manual renewal (if needed):**
If you need to force renewal before the 30-day threshold, you can delete the certificates from the `certs` volume and restart:
```bash
docker compose exec cert_gen rm -rf /usr/share/elasticsearch/config/certs/instance /usr/share/elasticsearch/config/certs/ca
docker compose up -d
```

**Custom validity period**: You can set a custom validity period by adding the `--days` parameter to the `elasticsearch-certutil` commands in `docker-compose.yml` (e.g., `--days 365` for 1 year).
