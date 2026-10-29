import http from 'http';
import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';

const PORT = Number(process.env.PORT) || 3000;
const VERSION = process.env.APP_VERSION || 'v1.0.0-legacy';
const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';

// Stateful storage bottleneck #1 -> TO-FIX
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(path.join(UPLOAD_DIR, 'images'), { recursive: true });
  fs.mkdirSync(path.join(UPLOAD_DIR, 'audio'), { recursive: true });
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://ganeshup_user:local_rds_password@localhost:5432/ganeshup_db'
});

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'GET' && req.url === '/api/health') {
    try {
      const dbCheck = await pool.query('SELECT NOW()');
      res.writeHead(200);
      res.end(JSON.stringify({
        status: 'ok',
        version: VERSION,
        database: 'connected',
        dbTime: dbCheck.rows[0].now,
        timestamp: new Date().toISOString()
      }));
    } catch (err: any) {
      res.writeHead(500);
      res.end(JSON.stringify({ status: 'error', database: err.message }));
    }
    return;
  }

  // Heavy 50MB Base64 payloads bottleneck #2 -> TO-FIX
  if (req.method === 'POST' && req.url === '/api/courses/share') {
    let body = '';

    req.on('data', chunk => {
      body += chunk;
    });

    req.on('end', () => {
      try {
        const parsedData = JSON.parse(body);

        const images = parsedData?.courseData?.content?.images || [];
        images.forEach((img: any, idx: number) => {
          if (img.base64Data) {
            const buffer = Buffer.from(img.base64Data, 'base64');
            fs.writeFileSync(path.join(UPLOAD_DIR, 'images', `image_${Date.now()}_${idx}.jpg`), buffer);
          }
        });

        res.writeHead(201);
        res.end(JSON.stringify({
          message: 'Course saved successfully on local disk and database',
          downloadToken: 'tok_' + Math.random().toString(36).substring(2, 10),
          filesStoredLocally: images.length
        }));
      } catch (err: any) {
        res.writeHead(400);
        res.end(JSON.stringify({ error: 'Invalid JSON payload', details: err.message }));
      }
    });
    return;
  }

  //
  // External Cron Calling HTTP Endpoint bottleneck #4 -> TO-FIX
  // AS-IS: GET /api/courses/cleanup was call by a cronjob was exposing sensible logic on REST API.
  //
  // if (req.method === 'GET' && req.url === '/api/courses/cleanup') {
  //   res.writeHead(200);
  //   res.end(JSON.stringify({ message: '[Legacy] Cleanup executed via HTTP GET' }));
  //     return;
  //   }
  // TO-BE MODERNIZATION (AWS):
  // Serverless decoupled : AWS EventBridge Scheduler -> AWS Lambda

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Route not found in Ganesha As-Is API' }));
});

server.listen(PORT, () => {
  printServerStart();
});

function printServerStart() {
  console.log(`[Ganesha As-Is API ${VERSION}] Listening on port ${PORT} (Storage: local path ${UPLOAD_DIR})`);
}