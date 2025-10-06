# syntax=docker/dockerfile:1.7

FROM node:20-alpine AS base
WORKDIR /app
ENV NODE_ENV=production

FROM base AS deps
RUN apk add --no-cache libc6-compat
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts --no-audit --no-fund

FROM base AS deploy
USER node
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node . .
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["node","src/server.js"]
