# ---------- Builder ----------
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

RUN npm run build

# ---------- Runner ----------
FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Copy only if your project has a public folder
#COPY --from=builder /app/public ./public

EXPOSE 3000

CMD ["node", "server.js"]
