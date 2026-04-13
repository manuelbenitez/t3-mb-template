#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# t3-mb-template setup
# Run once after cloning. Personalizes the workspace for your project.
# ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  t3-mb-template setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Organization name ──────────────────────────────────────────
echo -e "${YELLOW}1. Organization name${NC}"
echo "   This replaces @acme everywhere in the codebase."
echo "   Use lowercase, no spaces (e.g. mycompany, johns-app)"
echo ""
read -r -p "   Org name [acme]: " ORG_NAME
ORG_NAME="${ORG_NAME:-acme}"

if [[ "$ORG_NAME" =~ [^a-zA-Z0-9_-] ]]; then
  echo -e "${RED}   Error: org name must only contain letters, numbers, hyphens, underscores.${NC}"
  exit 1
fi

echo ""

# ── 2. Project name ───────────────────────────────────────────────
echo -e "${YELLOW}2. Project name${NC}"
echo "   Sets the root package.json name (e.g. my-app)"
echo ""
read -r -p "   Project name [my-app]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-my-app}"
echo ""

# ── 3. MongoDB URI ────────────────────────────────────────────────
echo -e "${YELLOW}3. MongoDB URI${NC}"
echo "   Local example:  mongodb://localhost:27017/${PROJECT_NAME}"
echo "   Atlas example:  mongodb+srv://user:pass@cluster.mongodb.net/${PROJECT_NAME}"
echo ""
read -r -p "   MongoDB URI [mongodb://localhost:27017/${PROJECT_NAME}]: " MONGODB_URI
MONGODB_URI="${MONGODB_URI:-mongodb://localhost:27017/${PROJECT_NAME}}"

if [[ ! "$MONGODB_URI" =~ ^mongodb(\+srv)?:// ]]; then
  echo -e "${RED}   Error: MongoDB URI must start with mongodb:// or mongodb+srv://${NC}"
  exit 1
fi

echo ""

# ── 4. JWT secret ─────────────────────────────────────────────────
echo -e "${YELLOW}4. JWT secret${NC}"
echo "   Press Enter to auto-generate a secure 32-byte secret."
echo ""
read -r -p "   JWT secret [auto-generate]: " JWT_SECRET

if [[ -z "$JWT_SECRET" ]]; then
  JWT_SECRET=$(openssl rand -base64 32)
  echo -e "   ${GREEN}Generated: ${JWT_SECRET}${NC}"
elif [[ ${#JWT_SECRET} -lt 32 ]]; then
  echo -e "${RED}   Error: JWT secret must be at least 32 characters.${NC}"
  exit 1
fi

echo ""

# ── 5. Frontend URL ───────────────────────────────────────────────
echo -e "${YELLOW}5. Frontend URL (for CORS)${NC}"
echo ""
read -r -p "   Frontend URL [http://localhost:3000]: " FRONTEND_URL
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Replace @acme with org name ───────────────────────────────────
if [[ "$ORG_NAME" != "acme" ]]; then
  echo "→ Replacing @acme with @${ORG_NAME} in source files…"
  ESCAPED=$(printf '%s\n' "$ORG_NAME" | sed 's/[\/&]/\\&/g')
  find . -type f \( \
    -name "*.json" -o -name "*.ts" -o -name "*.tsx" \
    -o -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \
    -o -name "*.css" -o -name "*.md" \
  \) \
    ! -path "*/node_modules/*" \
    ! -path "*/.next/*" \
    ! -path "*/dist/*" \
    ! -path "*/.turbo/*" \
    ! -name "setup.sh" \
    -exec sed -i "s/@acme/@${ESCAPED}/g" {} +
  echo -e "  ${GREEN}Done.${NC}"
fi

# ── Update root package.json name ────────────────────────────────
echo "→ Setting project name to '${PROJECT_NAME}'…"
ESCAPED_PROJECT=$(printf '%s\n' "$PROJECT_NAME" | sed 's/[\/&]/\\&/g')
sed -i "s/\"name\": \"t3-mb-template\"/\"name\": \"${ESCAPED_PROJECT}\"/" package.json
echo -e "  ${GREEN}Done.${NC}"

# ── Write .env ────────────────────────────────────────────────────
echo "→ Writing .env…"
if [[ -f ".env" ]]; then
  echo "  .env already exists — backing up to .env.bak"
  cp .env .env.bak
fi

sed \
  -e "s|MONGODB_URI=mongodb://localhost:27017/myapp|MONGODB_URI=${MONGODB_URI}|" \
  -e "s|JWT_SECRET=change-me-use-openssl-rand-base64-32|JWT_SECRET=${JWT_SECRET}|" \
  -e "s|FRONTEND_URL=http://localhost:3000|FRONTEND_URL=${FRONTEND_URL}|" \
  -e "s|APP_NAME=My App|APP_NAME=${PROJECT_NAME}|" \
  .env.example > .env

echo -e "  ${GREEN}Done.${NC}"

# ── Install dependencies ──────────────────────────────────────────
echo "→ Installing dependencies (pnpm install)…"
pnpm install
echo -e "  ${GREEN}Done.${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Setup complete!${NC}"
echo ""
echo "  Start dev servers:"
echo "    pnpm dev"
echo ""
echo "  Or start individually:"
echo "    pnpm dev:next   → http://localhost:3000"
echo "    pnpm dev:api    → http://localhost:3001/api"
echo "                      http://localhost:3001/api/docs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
