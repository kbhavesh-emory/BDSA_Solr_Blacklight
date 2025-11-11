#!/bin/bash

# ==============================
# SETTINGS (Modify if needed)
# ==============================
BACKEND_PORT=8081
FRONTEND_SERVICE="blacklight"
APP_DIR="/opt/bhavesh/dsa-search/etl"
APP_CMD="uvicorn app:app --host 0.0.0.0 --port $BACKEND_PORT"

echo "=============================="
echo "   🚀 Restarting System       "
echo "=============================="

# ==============================
# 1. Restart Frontend (Docker)
# ==============================
echo "🔄 Restarting frontend (Docker: $FRONTEND_SERVICE)..."
docker compose down --volumes $FRONTEND_SERVICE
docker compose up -d --build $FRONTEND_SERVICE
echo "✅ Frontend container restarted successfully!"

# ==============================
# 2. Restart Backend FastAPI (uvicorn)
# ==============================
echo "🔍 Checking if port $BACKEND_PORT is in use..."

# Find PID(s) using the backend port
PIDS=$(sudo lsof -t -i tcp:$BACKEND_PORT)

if [ -n "$PIDS" ]; then
  echo "⚠ Port $BACKEND_PORT is being used by PID(s): $PIDS"
  echo "🔫 Killing process..."
  sudo kill -9 $PIDS
  echo "✅ Freed port $BACKEND_PORT."
else
  echo "✅ Port $BACKEND_PORT is already free."
fi

# Start new FastAPI backend
echo "🚀 Starting FastAPI backend service..."
cd "$APP_DIR" || { echo "❌ ERROR: Cannot access $APP_DIR"; exit 1; }

# Run backend in background with logs
nohup $APP_CMD > etl_server.log 2>&1 &

echo "✅ Backend server started on port $BACKEND_PORT"
echo "📂 Log file: $APP_DIR/etl_server.log"

echo "=============================="
echo " ✅ Frontend + Backend Restarted!"
echo "=============================="
