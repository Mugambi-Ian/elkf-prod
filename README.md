# Logger Stack

A production-ready, secure, and performant logging stack using the Elastic Stack (Elasticsearch, Logstash, Kibana) and Filebeat. This stack is orchestrated with Docker Compose and is designed with security and scalability in mind.

## Features

-   **Secure by Default**: End-to-end encryption with TLS for all components. Passwords and sensitive configurations are managed via environment variables.
-   **Performant**: Pre-configured resource limits for each service to ensure stable operation. These should be reviewed and adjusted based on your specific workload and host resources.
-   **Centralized Logging**: Filebeat ships logs from a designated volume, Logstash processes and enriches them, and Elasticsearch provides powerful indexing and search capabilities. Kibana offers a rich UI for visualization and analysis.
-   **Automated Setup**: Bootstrap service automatically configures passwords, API keys, index templates, and ILM policies on first run.
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

Create a `.env` file in the project root with the following required environment variables. Use the following command to generate secure passwords:

```bash
openssl rand -hex 16
```

Your `.env` file should contain:

```ini
# .env
ELASTIC_PASSWORD=<generated-password>
KIBANA_SYSTEM_PASSWORD=<generated-password>
KIBANA_ENCRYPTION_KEY=<32-character-string-or-leave-default>
```

**Note**: 
- `ELASTIC_PASSWORD`: Password for the `elastic` superuser account
- `KIBANA_SYSTEM_PASSWORD`: Password for the `kibana_system` user (used by Kibana to connect to Elasticsearch)
- `KIBANA_ENCRYPTION_KEY`: Optional 32-character encryption key for Kibana (defaults to `changeme_32_character_string_here` if not set)

### Step 3: Create External Log Volume

This stack is configured to ingest logs from a Docker named volume called `app-logs`. Create this volume before starting the stack. Your application containers should mount this volume to write their log files.

```bash
docker volume create app-logs
```

### Step 4: Launch the Stack

Launch the entire stack. The setup process is automated:

1. The `cert_gen` service automatically generates TLS certificates for Elastic components
2. The `es_bootstrap` service waits for Elasticsearch to be healthy, then automatically:
   - Sets the `kibana_system` user password
   - Creates a Logstash API key for secure log ingestion
   - Configures default index templates with compression and performance optimizations
   - Sets up Index Lifecycle Management (ILM) policies for automatic log rotation and retention

```bash
docker compose up --build -d
```

Your Kibana instance will be available at `http://localhost:5601` once all services are healthy.

**Note**: For production deployments, you may want to add an Nginx reverse proxy in front of Kibana for HTTPS termination. The `nginx/nginx.conf` file is provided as a reference but is not currently integrated into the docker-compose setup.

---

## Architecture

The stack consists of the following services:

- **Elasticsearch**: Stores and indexes logs. Configured with TLS, security enabled, and optimized for low-memory environments (256MB heap).
- **Kibana**: Web UI for log visualization and analysis. Exposed on port 5601.
- **Logstash**: Processes logs from Filebeat and sends them to Elasticsearch. Uses API key authentication.
- **Filebeat**: Collects logs from the `app-logs` volume and Docker containers, ships them to Logstash.
- **es_bootstrap**: One-time setup service that configures passwords, API keys, index templates, and ILM policies.

## Maintenance & Security

### Resource Allocation

The CPU and memory limits in `docker-compose.yml` are set to reasonable defaults optimized for a 2GB droplet:
- Elasticsearch: 768MB limit, 256MB Java heap
- Kibana: 640MB limit, 400MB Node.js heap
- Logstash: 384MB limit, 128MB Java heap
- Filebeat: 128MB limit

Monitor your resource usage and adjust them according to your host's capacity and the stack's workload.

### Data Backup

For production data, it is critical to set up regular backups. Use the [Elasticsearch Snapshot and Restore](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-restore.html) functionality to back up your indices to a remote repository like S3, GCS, or Azure Blob Storage. The snapshot volume is already configured at `/usr/share/elasticsearch/snapshots`.

### Index Lifecycle Management (ILM)

Index Lifecycle Management is automatically configured by the `es_bootstrap` service with the following policy:
- **Hot phase**: Indices roll over at 2GB, 3 days, or 200k documents
- **Warm phase**: After 7 days, indices are force-merged, shrunk to 1 shard, and replicas removed
- **Delete phase**: Indices are deleted after 90 days

You can modify the ILM policy in the `es_bootstrap` service command in `docker-compose.yml` or manage it through Kibana's UI.

### Log Ingestion

Logs are ingested from:
1. The `app-logs` Docker volume: Place JSON log files in `/usr/local/var/log/*.log` (mounted from the volume)
2. Docker container logs: Filebeat automatically collects logs from all Docker containers

Logs are indexed with the pattern `{service-name}-{YYYY.MM.dd}` based on the `service.name` field in your log entries.
