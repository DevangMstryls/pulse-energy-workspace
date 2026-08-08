#!/usr/bin/env bash
# Adapter: docker — Docker CLI; daemon runs via colima on this machine.
# Capabilities: status only (start/stop go through colima).

docker_load() {
  SERVICE_DISPLAY_NAME="Docker"
  SERVICE_DESCRIPTION="Docker CLI (daemon managed by colima — use colima adapter to start/stop)"
  CAPABILITIES=(status)
}

docker_status() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  if docker info >/dev/null 2>&1; then
    echo "running"
  else
    echo "stopped"
  fi
}

docker_info() {
  command -v docker >/dev/null 2>&1 || { echo "  docker binary not found"; return; }
  printf '  Version : %s\n' "$(docker --version 2>/dev/null)"
  if docker info >/dev/null 2>&1; then
    printf '  Containers: %s (running: %s)\n' \
      "$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')" \
      "$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    printf '  Images    : %s\n' "$(docker images -aq 2>/dev/null | wc -l | tr -d ' ')"
  fi
}
