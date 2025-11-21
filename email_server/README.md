# Email Server

NodeJS server providing dummy email data for testing.

## Setup

```bash
npm install
```

## Using PostgreSQL (optional)

```bash
# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=emails
export DB_USER=postgres
export DB_PASSWORD=postgres

# Populate database
npm run populate
```

## Using In-Memory (default)

```bash
# Start server
npm start

# In another terminal, populate in-memory data
curl -X POST http://localhost:3000/populate -H "Content-Type: application/json" -d '{"count": 100000}'
```

## API Endpoints

- `GET /emails?page=1&limit=100` - List emails with pagination
- `GET /emails/:messageId/body` - Get email body by Message-ID
- `GET /emails/count` - Get total email count
- `POST /populate` - Populate dummy emails (in-memory only)

