#!/usr/bin/env bash
set -uo pipefail

# ============================================================
# Meek.io action handler
# ============================================================

COMMANDS_DIR="/meek-io/meek/commands"
SETTINGS_DIR="${COMMANDS_DIR}/settings"

VERSIONS_FILE="${SETTINGS_DIR}/versions.json"
VERSIONS_CACHE_DIR="${SETTINGS_DIR}/cache"

CREDENTIALS_FILE="${SETTINGS_DIR}/current-credentials.txt"
HOST_IP_FILE="${SETTINGS_DIR}/host-ip.txt"

ZIGBEE_CONTAINER="zigbee2mqtt"
NODE_RED_CONTAINER="node-red-node-red-1"
MOSQUITTO_CONTAINER="mosquitto"
MOSQUITTO_PASSWORD_FILE="/mosquitto/config/passwd"

# Fallback scan interval in seconds.
FALLBACK_SCAN_SECONDS="60"

# ============================================================
# Preparation
# ============================================================

mkdir -p "${COMMANDS_DIR}"
mkdir -p "${SETTINGS_DIR}"
mkdir -p "${VERSIONS_CACHE_DIR}"

touch "${CREDENTIALS_FILE}"
chmod 644 "${CREDENTIALS_FILE}"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# ============================================================
# Docker helpers
# ============================================================

docker_container_exists() {
    local container="$1"

    docker inspect "${container}" >/dev/null 2>&1
}

docker_label_version() {
    local container="$1"
    local label="$2"

    docker inspect "${container}" \
        --format "{{index .Config.Labels \"${label}\"}}" \
        2>/dev/null || true
}

docker_compose_service() {
    local container="$1"

    docker inspect "${container}" \
        --format '{{index .Config.Labels "com.docker.compose.service"}}' \
        2>/dev/null || true
}

docker_compose_project() {
    local container="$1"

    docker inspect "${container}" \
        --format '{{index .Config.Labels "com.docker.compose.project"}}' \
        2>/dev/null || true
}

docker_compose_file() {
    local container="$1"

    docker inspect "${container}" \
        --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' \
        2>/dev/null || true
}

docker_compose_directory() {
    local container="$1"

    docker inspect "${container}" \
        --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' \
        2>/dev/null || true
}

# ============================================================
# Host IP helper
# ============================================================

write_host_ip_file() {
    local host_ip=""

    host_ip="$(ip -4 addr show scope global \
        | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
        | head -n 1 || true)"

    if [[ -z "${host_ip}" ]]; then
        host_ip="$(hostname -I | awk '{print $1}')"
    fi

    if [[ -z "${host_ip}" ]]; then
        host_ip="Unknown"
    fi

    printf '%s' "${host_ip}" > "${HOST_IP_FILE}.tmp"
    mv "${HOST_IP_FILE}.tmp" "${HOST_IP_FILE}"
    chmod 644 "${HOST_IP_FILE}"

    log "Host IP updated: ${host_ip}"
}

# ============================================================
# Version helpers
# ============================================================

get_installed_version() {
    local container="$1"
    local version=""

    version="$(docker_label_version \
        "${container}" \
        "org.opencontainers.image.version")"

    if [[ -z "${version}" ]]; then
        version="$(docker_label_version \
            "${container}" \
            "org.label-schema.version")"
    fi

    if [[ -z "${version}" ]]; then
        version="Unknown"
    fi

    printf '%s' "${version}"
}

get_latest_github_version() {
    local repository="$1"
    local cache_file="${VERSIONS_CACHE_DIR}/${repository//\//_}.txt"
    local response=""
    local version=""

    if [[ -f "${cache_file}" ]]; then
        local cache_age

        cache_age="$(
            (
                date +%s
                stat -c %Y "${cache_file}"
            ) | paste -sd- | bc
        )"

        if (( cache_age < 3600 )); then
            cat "${cache_file}"
            return
        fi
    fi

    response="$(curl -fsSL \
        --max-time 10 \
        -H 'User-Agent: Meek-io-Action-Handler' \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${repository}/releases/latest" \
        2>/dev/null || true)"

    version="$(printf '%s' "${response}" \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -n 1 \
        | cut -d '"' -f 4 || true)"

    if [[ -z "${version}" ]]; then
        if [[ -f "${cache_file}" ]]; then
            cat "${cache_file}"
        else
            printf 'Unknown'
        fi

        return
    fi

    printf '%s' "${version}" > "${cache_file}"
    chmod 644 "${cache_file}"

    printf '%s' "${version}"
}

version_is_older() {
    local installed="$1"
    local latest="$2"

    installed="${installed#v}"
    latest="${latest#v}"

    if [[ ! "${installed}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        return 1
    fi

    if [[ ! "${latest}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        return 1
    fi

    [[ "$(
        printf '%s\n%s\n' \
            "${installed}" \
            "${latest}" \
            | sort -V \
            | head -n 1
    )" != "${installed}" ]]
}

write_versions_file() {
    local zigbee_installed
    local zigbee_latest
    local zigbee_update

    local node_red_installed
    local node_red_latest
    local node_red_update

    local temporary

    zigbee_installed="$(get_installed_version "${ZIGBEE_CONTAINER}")"
    zigbee_latest="$(get_latest_github_version "Koenkk/zigbee2mqtt")"

    node_red_installed="$(get_installed_version "${NODE_RED_CONTAINER}")"
    node_red_latest="$(get_latest_github_version "node-red/node-red")"

    if version_is_older "${zigbee_installed}" "${zigbee_latest}"; then
        zigbee_update="true"
    else
        zigbee_update="false"
    fi

    if version_is_older "${node_red_installed}" "${node_red_latest}"; then
        node_red_update="true"
    else
        node_red_update="false"
    fi

    temporary="${VERSIONS_FILE}.tmp"

    cat > "${temporary}" <<EOF
{
  "updated_at": "$(date -Is)",
  "zigbee2mqtt": {
    "installed": "${zigbee_installed}",
    "latest": "${zigbee_latest}",
    "update_available": ${zigbee_update}
  },
  "node-red": {
    "installed": "${node_red_installed}",
    "latest": "${node_red_latest}",
    "update_available": ${node_red_update}
  }
}
EOF

    mv "${temporary}" "${VERSIONS_FILE}"
    chmod 644 "${VERSIONS_FILE}"

    write_host_ip_file

    log "Version information updated:"
    log "  Zigbee2MQTT: installed=${zigbee_installed}, latest=${zigbee_latest}"
    log "  Node-RED: installed=${node_red_installed}, latest=${node_red_latest}"
}

# ============================================================
# Service actions
# ============================================================

run_service_action() {
    local service="$1"
    local action="$2"
    local container=""

    case "${service}" in
        Zigbee2MQTT)
            container="${ZIGBEE_CONTAINER}"
            ;;
        Node-RED)
            container="${NODE_RED_CONTAINER}"
            ;;
        *)
            log "Unknown service: ${service}"
            return
            ;;
    esac

    if ! docker_container_exists "${container}"; then
        log "Container not found: ${container}"
        return
    fi

    case "${action}" in
        Start)
            log "Starting ${container}"
            docker start "${container}" || log "Failed to start ${container}"
            ;;

        Stop)
            log "Stopping ${container}"
            docker stop "${container}" || log "Failed to stop ${container}"
            ;;

        Restart)
            log "Restarting ${container}"
            docker restart "${container}" || log "Failed to restart ${container}"
            ;;

        Update)
            local compose_service
            local compose_project
            local compose_file
            local compose_directory

            compose_service="$(docker_compose_service "${container}")"
            compose_project="$(docker_compose_project "${container}")"
            compose_file="$(docker_compose_file "${container}")"
            compose_directory="$(docker_compose_directory "${container}")"

            if [[ -z "${compose_service}" || -z "${compose_project}" || -z "${compose_file}" || -z "${compose_directory}" ]]; then
                log "Unable to determine Docker Compose details for ${container}"
                log "Update skipped"
                return
            fi

            log "Updating ${container} using Docker Compose"

            docker compose \
                -p "${compose_project}" \
                --project-directory "${compose_directory}" \
                -f "${compose_file}" \
                pull "${compose_service}" \
                || log "Failed to pull ${compose_service}"

            docker compose \
                -p "${compose_project}" \
                --project-directory "${compose_directory}" \
                -f "${compose_file}" \
                up -d "${compose_service}" \
                || log "Failed to recreate ${compose_service}"
            ;;

        *)
            log "Unknown action for ${service}: ${action}"
            ;;
    esac

    write_versions_file
}

# ============================================================
# Mosquitto user management
# ============================================================

add_mosquitto_user() {
    local command_file="$1"
    local username=""
    local password=""

    username="$(sed -n '1p' "${command_file}")"
    password="$(sed -n '2p' "${command_file}")"

    username="${username//$'\r'/}"
    password="${password//$'\r'/}"

    if [[ -z "${username}" || -z "${password}" ]]; then
        log "Mosquitto-AddUser: missing username or password"
        return
    fi

    if ! docker_container_exists "${MOSQUITTO_CONTAINER}"; then
        log "Mosquitto container not found: ${MOSQUITTO_CONTAINER}"
        return
    fi

    log "Replacing Mosquitto credentials with user: ${username}"

    if ! docker exec "${MOSQUITTO_CONTAINER}" \
        mosquitto_passwd -b -c \
        "${MOSQUITTO_PASSWORD_FILE}" \
        "${username}" \
        "${password}"; then
        log "Failed to update Mosquitto password file"
        return
    fi

    if ! docker restart "${MOSQUITTO_CONTAINER}"; then
        log "Failed to restart Mosquitto"
        return
    fi

    printf 'username=%s\npassword=%s\n' \
        "${username}" \
        "${password}" \
        > "${CREDENTIALS_FILE}.tmp"

    mv "${CREDENTIALS_FILE}.tmp" "${CREDENTIALS_FILE}"
    chmod 644 "${CREDENTIALS_FILE}"

    log "Mosquitto credentials updated"
}

# ============================================================
# Command processing
# ============================================================

process_command_file() {
    local command_file="$1"
    local command_name
    local service=""
    local action=""

    # Ignore files that disappeared before processing.
    [[ -f "${command_file}" ]] || return

    command_name="$(basename "${command_file}")"

    log "Processing command: ${command_name}"

    case "${command_name}" in
        System-Reboot)
            log "Reboot requested"
            rm -f "${command_file}"
            sync
            sleep 2
            reboot
            ;;

        System-Update)
            log "System update requested"
            rm -f "${command_file}"
            # Add your supported host update command here.
            ;;

        Zigbee2MQTT-Start|Zigbee2MQTT-Stop|Zigbee2MQTT-Restart|Zigbee2MQTT-Update)
            service="Zigbee2MQTT"
            action="${command_name#Zigbee2MQTT-}"
            rm -f "${command_file}"
            run_service_action "${service}" "${action}"
            ;;

        Node-RED-Start|Node-RED-Stop|Node-RED-Restart|Node-RED-Update)
            service="Node-RED"
            action="${command_name#Node-RED-}"
            rm -f "${command_file}"
            run_service_action "${service}" "${action}"
            ;;

        Mosquitto-AddUser)
            add_mosquitto_user "${command_file}"
            rm -f "${command_file}"
            ;;

        *)
            log "Ignoring unknown command: ${command_name}"
            rm -f "${command_file}"
            ;;
    esac
}

process_commands() {
    local command_file

    shopt -s nullglob

    for command_file in "${COMMANDS_DIR}"/*; do
        [[ -f "${command_file}" ]] || continue

        # Ignore hidden temporary files.
        [[ "$(basename "${command_file}")" == .* ]] && continue

        process_command_file "${command_file}"
    done

    shopt -u nullglob
}

# ============================================================
# Main loop: immediate inotify processing
# ============================================================

log "Meek.io action handler started"

# Process commands left behind before a restart.
process_commands

# Refresh versions and host IP at startup.
write_versions_file

LAST_VERSION_UPDATE="$(date +%s)"
LAST_FALLBACK_SCAN="$(date +%s)"

while true; do
    event_file="$(inotifywait -q \
        -e close_write,moved_to,create \
        --format '%w%f' \
        "${COMMANDS_DIR}")"

    if [[ -f "${event_file}" ]] && [[ "$(basename "${event_file}")" != .* ]]; then
        process_command_file "${event_file}"
    fi

    now="$(date +%s)"

    # Fallback scan protects against a missed filesystem event.
    if (( now - LAST_FALLBACK_SCAN >= FALLBACK_SCAN_SECONDS )); then
        process_commands
        LAST_FALLBACK_SCAN="${now}"
    fi

    # Refresh version information at most once per hour.
    if (( now - LAST_VERSION_UPDATE >= 3600 )); then
        write_versions_file
        LAST_VERSION_UPDATE="${now}"
    fi
done
