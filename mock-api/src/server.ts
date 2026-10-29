import 'dotenv/config';
import http from 'http';
import { Pool } from 'pg';
/*
Removed to use AWS S3 and Secrets Manager
import fs from 'fs';
import path from 'path';
*/
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';


const PORT = Number(process.env.PORT) || 3000;

/* changed from 1.0.0-legacy to 2.0.0-cloud-native for modernization */
//const VERSION = process.env.APP_VERSION || 'v1.0.0-legacy';
const VERSION = process.env.APP_VERSION || 'v2.0.0-cloud-native';

/*
Removed to use AWS S3 and Secrets Manager
const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';

// Stateful storage bottleneck #1 -> TO-FIX
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(path.join(UPLOAD_DIR, 'images'), { recursive: true });
  fs.mkdirSync(path.join(UPLOAD_DIR, 'audio'), { recursive: true });
}
*/
const SECRET_ID = process.env.APP_SECRET_ID || 'prod/ganeshup/backend-env';

const awsConfig = {
  region: process.env.AWS_REGION || 'ca-central-1',
  endpoint: process.env.LOCALSTACK_ENDPOINT || 'http://localhost:4566',
  credentials: { accessKeyId: 'test', secretAccessKey: 'test' },
  forcePathStyle: true // param true for S3 LocalStack
};

const s3Client = new S3Client(awsConfig);
const secretsClient = new SecretsManagerClient(awsConfig);

/*
Removed hardcoded / .env connection string to fetch dynamically from AWS Secrets Manager (Bottleneck #4)
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://ganeshup_user:local_rds_password@localhost:5432/ganeshup_db'
});
*/
let pool: Pool;
let S3_BUCKET: string;

/* DATABASE_URL and S3_BUCKET_NAME both come from the secret created by terraform/main.tf */
async function initConfig() {
  const command = new GetSecretValueCommand({ SecretId: SECRET_ID });
  const response = await secretsClient.send(command);
  const secret = JSON.parse(response.SecretString || '{}');

  if (!secret.DATABASE_URL || !secret.S3_BUCKET_NAME) {
    throw new Error(`Secret ${SECRET_ID} is missing DATABASE_URL or S3_BUCKET_NAME`);
  }

  S3_BUCKET = secret.S3_BUCKET_NAME;
  pool = new Pool({ connectionString: secret.DATABASE_URL });
}

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

    req.on('end', async () => {
      try {
        const parsedData = JSON.parse(body);
        const images = parsedData?.courseData?.content?.images || [];

        /*
        Reworked to use AWS S3 for storage instead of local filesystem (Bottleneck #1)
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
        */
        const uploadUrls = await Promise.all(
          images.map(async (img: any, idx: number) => {
            const key = `images/image_${Date.now()}_${idx}.jpg`;
            const command = new PutObjectCommand({
              Bucket: S3_BUCKET,
              Key: key,
              ContentType: 'image/jpeg'
            });
            const presignedUrl = await getSignedUrl(s3Client, command, { expiresIn: 900 });
            return { index: idx, s3Key: key, uploadUrl: presignedUrl };
          })
        );
        res.writeHead(201);
        res.end(JSON.stringify({
          message: 'Presigned URLs generated successfully (Zero disk I/O)',
          downloadToken: 'tok_' + Math.random().toString(36).substring(2, 10),
          uploadUrls
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
  res.end(JSON.stringify({ error: 'Route not found in Ganesha To-Be API' }));
});

initConfig().then(() => {
  server.listen(PORT, () => {
    printServerStart();
  });
});

function printServerStart() {
    console.log(`[Ganesha To-Be API ${VERSION}] Listening on port ${PORT} (Storage: S3 Presigned URLs | Secrets: AWS Secrets Manager)`);
}