# Stage 1: Build / Verify
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
COPY src ./src

# Stage 2: Minimal Runtime Image
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080

COPY --from=builder /app ./

# Run as non-root user for container security best practices
USER node

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "src/server.js"]
