const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const app = express();
const PORT = 3000;

// Enable CORS for Flutter app
app.use(cors());
app.use(express.json());

// PostgreSQL connection pool (or use in-memory for dummy)
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'emails',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 20,
});

// Fallback to in-memory if PostgreSQL not available
let inMemoryEmails = [];
let useInMemory = false;

// Test connection
pool.query('SELECT NOW()')
  .then(() => console.log('Connected to PostgreSQL'))
  .catch(() => {
    console.log('PostgreSQL not available, using in-memory storage');
    useInMemory = true;
  });

// GET /emails - List emails with pagination
app.get('/emails', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 100;
    const offset = (page - 1) * limit;

    if (useInMemory) {
      const emails = inMemoryEmails.slice(offset, offset + limit);
      res.json({
        emails,
        total: inMemoryEmails.length,
        page,
        limit,
      });
    } else {
      const result = await pool.query(
        'SELECT id, "Message-ID", "From", "To", "Subject", "Received_at" FROM emails ORDER BY id ASC LIMIT $1 OFFSET $2',
        [limit, offset]
      );
      const countResult = await pool.query('SELECT COUNT(*) as total FROM emails');
      
      res.json({
        emails: result.rows,
        total: parseInt(countResult.rows[0].total),
        page,
        limit,
      });
    }
  } catch (error) {
    console.error('Error fetching emails:', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /emails/:messageId/body - Get email body by Message-ID
app.get('/emails/:messageId/body', async (req, res) => {
  try {
    const messageId = req.params.messageId;

    if (useInMemory) {
      const email = inMemoryEmails.find(e => e['Message-ID'] === messageId);
      if (!email) {
        return res.status(404).json({ error: 'Email not found' });
      }
      res.setHeader('Content-Type', 'text/plain');
      res.send(email.Body);
    } else {
      const result = await pool.query(
        'SELECT "Body" FROM emails WHERE "Message-ID" = $1',
        [messageId]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Email not found' });
      }
      res.setHeader('Content-Type', 'text/plain');
      res.send(result.rows[0].Body);
    }
  } catch (error) {
    console.error('Error fetching email body:', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /emails/count - Get total count
app.get('/emails/count', async (req, res) => {
  try {
    if (useInMemory) {
      res.json({ count: inMemoryEmails.length });
    } else {
      const result = await pool.query('SELECT COUNT(*) as count FROM emails');
      res.json({ count: parseInt(result.rows[0].count) });
    }
  } catch (error) {
    console.error('Error getting count:', error);
    res.status(500).json({ error: error.message });
  }
});

// Initialize in-memory storage if needed
if (useInMemory) {
  console.log('Initializing in-memory email storage...');
  // This will be populated by populate.js
}

app.listen(PORT, () => {
  console.log(`Email server running on http://localhost:${PORT}`);
  console.log(`Use POST /populate to generate dummy emails`);
});

// POST /populate - Populate dummy emails (for in-memory)
app.post('/populate', async (req, res) => {
  try {
    const count = parseInt(req.body.count) || 100000;
    console.log(`Populating ${count} emails...`);
    
    if (useInMemory) {
      inMemoryEmails = generateDummyEmails(count);
      res.json({ message: `Generated ${inMemoryEmails.length} emails in memory` });
    } else {
      // For PostgreSQL, use populate.js script
      res.json({ message: 'Use populate.js script for PostgreSQL' });
    }
  } catch (error) {
    console.error('Error populating:', error);
    res.status(500).json({ error: error.message });
  }
});

function generateDummyEmails(count) {
  const emails = [];
  const domains = ['example.com', 'test.com', 'demo.org', 'sample.net'];
  const subjects = [
    'Meeting Tomorrow',
    'Project Update',
    'Invoice #',
    'Weekly Report',
    'Action Required',
    'Follow Up',
    'Reminder',
    'Thank You',
  ];

  for (let i = 1; i <= count; i++) {
    const domain = domains[i % domains.length];
    const from = `user${i}@${domain}`;
    const to = `recipient${i}@${domain}`;
    const subject = `${subjects[i % subjects.length]} ${i}`;
    const messageId = `<msg-${i}-${Date.now()}@${domain}>`;
    const receivedAt = new Date(Date.now() - (count - i) * 60000).toISOString();
    const body = `This is the body of email ${i}.\n\nIt contains some content that will be stored on disk.\n\nGenerated at ${receivedAt}`;

    emails.push({
      id: i,
      'Message-ID': messageId,
      'From': from,
      'To': to,
      'Subject': subject,
      'Received_at': receivedAt,
      'Body': body,
    });
  }

  return emails;
}

