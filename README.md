# ELK Logging Stack

Elasticsearch, Logstash, and Kibana stack for centralized Docker container logging.

## Quick Start

1. **Generate passwords:**
```bash
openssl rand -hex 16
```

2. **Create `.env` file:**
```ini
ELASTIC_PASSWORD=your-password-here
KIBANA_SYSTEM_PASSWORD=your-password-here
KIBANA_ENCRYPTION_KEY=your-32-char-key-here
```

3. **Start the stack:**
```bash
docker-compose up -d
```

4. **Access Kibana:**  
   Open `http://localhost:5601`  
   Login: `elastic` / `<ELASTIC_PASSWORD>`

## What It Does

- Collects logs from all Docker containers on the host
- Parses JSON logs and indexes them in Elasticsearch
- Multi-line stack traces stay in one document (no splitting)
- View and search logs in Kibana

## Index Pattern

Logs are stored as: `app-logs-{container-name}-{YYYY.MM.dd}`

## Requirements

- Docker
- Docker Compose

## Configuration

Your application should log to stdout in JSON format. The stack will automatically collect and index these logs.

Docker will rotate logs automatically (10MB × 3 files per container).