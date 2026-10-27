# Ganeshup Backend API

TypeScript backend for the Ganeshup course management Flutter app with authentication, course sharing, and file handling capabilities.

## Features

- 🔐 **JWT Authentication** - Login, register, refresh tokens
- 📚 **Course Sharing** - Store and download complete course payloads  
- 📁 **File Management** - Handle Base64 images and audio files
- 🗄️ **PostgreSQL Database** - Prisma ORM with type safety
- 🐳 **Docker Ready** - Complete containerization with docker-compose
- 🛡️ **Security** - Rate limiting, CORS, helmet, input validation
- ✅ **Health Check** - Database connection monitoring

## API Endpoints

### Authentication (`/api/auth`)
- `POST /register` - User registration
- `POST /login` - User login
- `POST /refresh` - Refresh JWT token
- `POST /logout` - User logout
- `GET /me` - Get current user (protected)

### Health Check (`/api/health`)
- `GET /` - API health status

### Course Sharing (`/api/courses`)
- `POST /share` - Share course payload (protected)
- `GET /download/:token` - Download course by token
- `GET /my-courses` - List user's shared courses (protected)
- `DELETE /:id` - Delete shared course (protected)
- `GET /cleanup` - Clean up expired tokens (admin)

## Quick Start

### Option 1: Automated Setup (Recommended)

1. **Navigate to backend directory**
   ```bash
   cd backend
   ```

2. **Run setup script**
   ```bash
   ./setup.sh
   ```

3. **Choose your setup option:**
   - **Option 1**: Full stack with Docker (recommended for production)
   - **Option 2**: Database only (for local Node.js development)
   - **Option 3**: Local development setup with npm

### Option 2: Manual Docker Setup

1. **Create environment file**
   ```bash
   cp .env.example .env
   ```

2. **Pull Docker images (to avoid timeout)**
   ```bash
   docker pull postgres:15
   docker pull node:20-slim
   ```

3. **Start services**
   ```bash
   docker-compose up -d
   ```

4. **Run database migrations**
   ```bash
   docker-compose exec backend npx prisma migrate deploy
   ```

### Option 3: Database Only (Local Development)

1. **Start only database services**
   ```bash
   docker-compose -f docker-compose.dev.yml up -d
   ```

2. **Setup local environment**
   ```bash
   cp .env.example .env
   npm install
   npm run db:generate
   npm run db:migrate
   npm run dev
   ```

### Local Development

1. **Install dependencies**
   ```bash
   npm install
   ```

2. **Set up PostgreSQL database**
   ```bash
   # Using Docker
   docker run --name app-postgres -e POSTGRES_PASSWORD=password -e POSTGRES_DB=app_db -p 5432:5432 -d postgres:15

   # Or install PostgreSQL locally
   ```

3. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials
   ```

4. **Generate Prisma client**
   ```bash
   npm run db:generate
   ```

5. **Run migrations**
   ```bash
   npm run db:migrate
   ```

6. **Start development server**
   ```bash
   npm run dev
   ```

## Environment Variables

```env
# Database
DATABASE_URL="postgresql://postgres:password@localhost:5432/app_db"

# JWT
JWT_SECRET="your-super-secret-jwt-key-here"
JWT_EXPIRES_IN="7d"
JWT_REFRESH_EXPIRES_IN="30d"

# Server
PORT=3000
NODE_ENV="development"

# CORS
CORS_ORIGIN="http://localhost:3000"

# File uploads
MAX_FILE_SIZE="50MB"
UPLOAD_DIR="./uploads"
```

## Database Schema

The backend uses PostgreSQL with the following main tables:

- **users** - User accounts with email/password
- **shared_courses** - Shared course data with JSON payloads
- **download_tokens** - Secure tokens for course downloads
- **refresh_tokens** - JWT refresh token management

## Course Data Format

The API expects course data in the same format that the Flutter app generates:

```json
{
  "courseData": {
    "metadata": {
      "courseId": "uuid-string",
      "title": "Course Title",
      "createdAt": "2025-01-01T00:00:00Z",
      "version": "1.0",
      "appVersion": "1.0.0"
    },
    "courseInfo": {
      "text": "Course Title",
      "colorBack": 4294967295,
      "colorText": 4294967295,
      "colorPage": 4294967295,
      "idSubject": 1,
      "idRemind": 1,
      "nDocs": 2,
      "nRecords": 1,
      "uniqueKey": "uuid-string"
    },
    "content": {
      "images": [
        {
          "index": 0,
          "base64Data": "base64-image-data...",
          "filename": "image_0.jpg",
          "mimeType": "image/jpeg"
        }
      ],
      "audioFiles": [
        {
          "index": 0,
          "base64Data": "base64-audio-data...",
          "filename": "audio_0.m4a",
          "mimeType": "audio/m4a"
        }
      ],
      "drawings": {
        "layersJson": "[{\"points\":[...],\"color\":...,\"size\":...}]"
      }
    }
  }
}
```

## Scripts

- `npm run dev` - Start development server with hot reload
- `npm run build` - Build TypeScript to JavaScript
- `npm start` - Start production server
- `npm run db:generate` - Generate Prisma client
- `npm run db:push` - Push schema changes to database
- `npm run db:migrate` - Run database migrations
- `npm run db:studio` - Open Prisma Studio

## Security Features

- **JWT Authentication** with refresh tokens
- **Rate Limiting** - 100 requests/15min (5 for auth endpoints)
- **CORS Protection** - Configurable origins
- **Helmet** - Security headers
- **Input Validation** - Joi schema validation
- **Password Hashing** - bcrypt with 12 rounds
- **SQL Injection Prevention** - Prisma ORM

## File Management

- **Base64 Processing** - Converts and stores image/audio files
- **Organized Storage** - Files stored in `uploads/images/` and `uploads/audio/`
- **Cleanup Tasks** - Automatic cleanup of expired files
- **File Size Limits** - Configurable upload limits

## Deployment

The backend is production-ready with:

- **Docker multi-stage builds** for optimized images
- **Health checks** for container orchestration
- **Graceful shutdown** handling
- **Error logging** and monitoring
- **Database connection pooling**

## Integration with Flutter App

To integrate with the existing Flutter app:

1. **Replace the data sending function** in `lib/components/[your_component].dart`
2. **Update authentication** to use real API endpoints
3. **Add download functionality** for shared courses
4. **Handle network errors** and offline scenarios

Example Flutter integration:

```dart
// Replace mock sendData function
Future<void> sendData(String data) async {
  final response = await http.post(
    Uri.parse('https://api.yourdomain.com/api/courses/share'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    },
    body: data,
  );
  
  if (response.statusCode == 201) {
    final result = jsonDecode(response.body);
    print('Course shared with token: ${result['downloadToken']}');
  }
}
```

## Maintenance

The backend includes maintenance endpoints for:

- **Token cleanup** - Remove expired tokens and files
- **Health monitoring** - Database connection status
- **File cleanup** - Remove old uploaded files

Set up periodic tasks (cron jobs) to call:
- `GET /api/.../cleanup` - Clean expired tokens
- Database cleanup tasks

## Support

For issues or questions:
1. Check the logs: `docker-compose logs backend`
2. Verify health: `curl http://localhost:3000/api/health`
3. Check database: `npm run db:studio`

---

**Ready to use with your Ganeshup Flutter app!** 🚀