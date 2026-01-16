# Logger Stack

A production-ready, secure, and performant logging stack using the Elastic Stack (Elasticsearch, Logstash, Kibana), Filebeat, and Nginx as a reverse proxy. This stack is orchestrated with Docker Compose and is designed with security and scalability in mind.

## Features

-   **Secure by Default**: End-to-end encryption with TLS for all components. Passwords and sensitive configurations are managed via environment variables.
-   **Performant**: Pre-configured resource limits for each service to ensure stable operation. These should be reviewed and adjusted based on your specific workload and host resources.
-   **Centralized Logging**: Filebeat ships logs from a designated volume, Logstash processes and enriches them, and Elasticsearch provides powerful indexing and search capabilities. Kibana offers a rich UI for visualization and analysis.
-   **Scalable**: Built on Docker, allowing for straightforward scaling and deployment across different environments.

## Requirements

-   Docker Engine
-   Docker Compose
-   `openssl` (for generating secure credentials)
-   A publicly accessible server with a registered domain name pointing to it.

---

## Deployment Instructions

### Step 1: Clone the Repository

```bash
git clone <your-repository-url>
cd logger-stack
```

### Step 2: Configure Environment Variables

Create a `.env` file from the provided example file.

```bash
cp .env.example .env
```

Now, edit the `.env` file and populate it with secure credentials. Use the following command to generate each required password:

```bash
openssl rand -hex 16
```

Your completed `.env` file should look like this, but with your own generated values:

```ini
# .env
ELASTIC_PASSWORD=f2d1a3e...
KIBANA_SYSTEM_PASSWORD=e8b4c2a...
CERTS_PASSWORD=a9c3d1b...
KIBANA_DOMAIN=your-kibana.your-domain.com
```

### Step 3: Create External Log Volume

This stack is configured to ingest logs from a Docker named volume called `app-logs`. Create this volume before starting the stack. Your application containers should mount this volume to write their log files.

```bash
docker volume create app-logs
```

### Step 4: Generate Transport Layer Certificates

The communication between Elastic components (e.g., Elasticsearch and Logstash) is secured by TLS. We need to generate a self-signed certificate for the transport layer. This command runs a temporary container to generate the certificate file (`elastic-certificates.p12`) into a new Docker volume named `certs`.

```bash
docker compose --profile cert_gen run --rm cert_gen
```

### Step 5: Configure Nginx for Production HTTPS

The Nginx service is configured to act as a reverse proxy for Kibana and to handle production-grade TLS termination.

1.  **Obtain SSL Certificates**: For a production setup, you must use SSL certificates from a trusted Certificate Authority (CA) like Let's Encrypt. The `docker-compose.yml` file already sets up the required volumes (`certbot-webroot` and `certbot-certs`) for a Certbot integration.

    You can obtain a certificate by running a Certbot container like this (replace `your-email@example.com` and `your-kibana.your-domain.com`):

    ```bash
docker run -it --rm \
  -v "$(pwd)/certbot-certs:/etc/letsencrypt" \
  -v "$(pwd)/certbot-webroot:/var/www/certbot" \
  certbot/certbot certonly --webroot \
  --webroot-path /var/www/certbot \
  -m your-email@example.com --agree-tos -n \
  -d your-kibana.your-domain.com
    ```

2.  **Update Nginx Configuration**: Ensure your `nginx/nginx.conf` correctly references the generated SSL certificates and your `KIBANA_DOMAIN`. The provided configuration should work with the Certbot setup above.

### Step 6: Launch the Stack

With all configurations in place, launch the entire stack.

```bash
docker compose up --build -d
```

Your Kibana instance should now be available at `https://<your-kibana.your-domain.com>`.

---

## Maintenance & Security

### Resource Allocation

The CPU and memory limits in `docker-compose.yml` are set to reasonable defaults. Monitor your resource usage and adjust them according to your host's capacity and the stack's workload.

### Data Backup

For production data, it is critical to set up regular backups. Use the [Elasticsearch Snapshot and Restore](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-restore.html) functionality to back up your indices to a remote repository like S3, GCS, or Azure Blob Storage.

### Index Lifecycle Management (ILM)

To prevent storage issues and manage data retention, configure [Index Lifecycle Management (ILM)](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html) policies in Kibana. This allows you to automatically manage indices, moving them through different tiers (hot, warm, cold, delete) over time.
