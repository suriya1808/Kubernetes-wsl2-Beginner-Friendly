#stage 1 - Build
# ==========================
FROM node:22-alpine AS builder

# Create app directory
WORKDIR /app

# Copy package files first (leverages Docker layer caching)
COPY package*.json ./

# Install all dependencies (including dev dependencies)
RUN npm ci

# Copy source code
COPY . .

# Compile TypeScript
RUN npm run build


# ==========================
# Stage 2 - Production
# ==========================
FROM node:22-alpine

# Create app directory
WORKDIR /app

# Production environment
ENV NODE_ENV=production

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --omit=dev

# Copy compiled application
COPY --from=builder /app/dist ./dist

# Copy uploads directory
COPY --from=builder /app/uploads ./uploads

# Application listens on port 3001
EXPOSE 3001

# Start application
CMD ["npm", "start"]
