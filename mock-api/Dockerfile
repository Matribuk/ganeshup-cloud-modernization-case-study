FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src/ ./src
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
RUN addgroup -g 1001 nodejs && adduser -u 1001 -G nodejs -S nodejs
COPY package*.json ./
RUN npm ci --only=production
COPY --from=builder /app/dist ./dist
USER nodejs
EXPOSE 3000
CMD ["node", "dist/server.js"]
