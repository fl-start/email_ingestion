const { Pool } = require('pg');
const fs = require('fs');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'emails',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
});

const COUNT = 100000;

async function createTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS emails (
      id BIGSERIAL PRIMARY KEY,
      "Message-ID" VARCHAR(255) UNIQUE NOT NULL,
      "From" VARCHAR(255) NOT NULL,
      "To" VARCHAR(255) NOT NULL,
      "Subject" VARCHAR(255) NOT NULL,
      "Received_at" TIMESTAMPTZ NOT NULL,
      "Body" TEXT NOT NULL
    )
  `);
  
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails("Message-ID");
    CREATE INDEX IF NOT EXISTS idx_emails_received_at ON emails("Received_at");
  `);
}

function generateEmail(i) {
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

  const domain = domains[i % domains.length];
  const from = `user${i}@${domain}`;
  const to = `recipient${i}@${domain}`;
  const subject = `${subjects[i % subjects.length]} ${i}`;
  const messageId = `<msg-${i}-${Date.now()}@${domain}>`;
  const receivedAt = new Date(Date.now() - (COUNT - i) * 60000).toISOString();
  const body = `This is the body of email ${i}.\n\nIt contains some content that will be stored on disk.\n\nGenerated at ${receivedAt}`;

  return {
    messageId,
    from,
    to,
    subject,
    receivedAt,
    body,
  };
}

async function populate() {
  try {
    console.log('Creating table...');
    await createTable();

    console.log(`Generating ${COUNT} emails...`);
    const batchSize = 1000;
    let inserted = 0;

    for (let i = 1; i <= COUNT; i += batchSize) {
      const batch = [];
      for (let j = i; j < Math.min(i + batchSize, COUNT + 1); j++) {
        const email = generateEmail(j);
        batch.push([
          email.messageId,
          email.from,
          email.to,
          email.subject,
          email.receivedAt,
          email.body,
        ]);
      }

      const values = batch.map((_, idx) => {
        const base = idx * 6;
        return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6})`;
      }).join(', ');

      const flatValues = batch.flat();
      const query = `
        INSERT INTO emails ("Message-ID", "From", "To", "Subject", "Received_at", "Body")
        VALUES ${values}
        ON CONFLICT ("Message-ID") DO NOTHING
      `;

      await pool.query(query, flatValues);
      inserted += batch.length;
      console.log(`Inserted ${inserted}/${COUNT} emails...`);
    }

    console.log(`Successfully populated ${COUNT} emails!`);
    process.exit(0);
  } catch (error) {
    console.error('Error populating:', error);
    process.exit(1);
  }
}

populate();

