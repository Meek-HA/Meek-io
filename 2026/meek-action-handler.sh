#!/usr/bin/env bash
set -uo pipefail
umask 077

# ============================================================
# Meek.io action handler
# ============================================================

COMMANDS_DIR="/meek-io/meek/commands"
SETTINGS_DIR="${COMMANDS_DIR}/settings"

VERSIONS_FILE="${SETTINGS_DIR}/versions.json"
VERSIONS_CACHE_DIR="${SETTINGS_DIR}/cache"

CREDENTIALS_FILE="${SETTINGS_DIR}/current-credentials.txt"
HOST_IP_FILE="${SETTINGS_DIR}/host-ip.txt"
LOCK_FILE="/var/lock/meek-action-handler.lock"

# File mode for the credentials file. Use 644 only if another user
# (e.g. a web UI) must read it.
CREDENTIALS_MODE="600"

ZIGBEE_CONTAINER="zigbee2mqtt"
NODE_RED_CONTAINER="node-red-node-red-1"
HOME_ASSISTANT_CONTAINER="homeassistant"
MOSQUITTO_CONTAINER="mosquitto"
MOSQUITTO_PASSWORD_FILE="/mosquitto/config/passwd"

NODE_RED_SETTINGS_FILE="/meek-io/node-red/settings.js"
NODE_RED_AUTH_FILE="/meek-io/node-red/admin-auth.js"

ZIGBEE_CONFIG_FILE="/meek-io/zigbee2mqtt/configuration.yaml"

CHECK_INTERVAL_SECONDS="5"
VERSION_REFRESH_SECONDS="3600"

# ============================================================
# Preparation
# ============================================================

mkdir -p "${COMMANDS_DIR}"
mkdir -p "${SETTINGS_DIR}"
mkdir -p "${VERSIONS_CACHE_DIR}"

touch "${CREDENTIALS_FILE}"
chmod "${CREDENTIALS_MODE}" "${CREDENTIALS_FILE}"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# Only one instance at a time
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    log "Another instance is already running, exiting"
    exit 1
fi

# Log every line of a multi-line string with a prefix
log_block() {
    local prefix="$1"
    local text="$2"
    local line

    while IFS= read -r line; do
        [[ -n "${line}" ]] && log "  ${prefix}: ${line}"
    done <<< "${text}"
}

# ============================================================
# Input validation
# ============================================================

valid_username() {
    [[ "$1" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]
}

valid_token() {
    [[ "$1" =~ ^[A-Za-z0-9._-]{1,128}$ ]]
}

# Overwrite a file's contents while keeping its inode, so single-file
# bind mounts inside containers keep seeing the update.
write_in_place() {
    local source="$1"
    local target="$2"

    cat "${source}" > "${target}"
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
    docker inspect "$1" \
        --format '{{index .Config.Labels "com.docker.compose.service"}}' \
        2>/dev/null || true
}

docker_compose_project() {
    docker inspect "$1" \
        --format '{{index .Config.Labels "com.docker.compose.project"}}' \
        2>/dev/null || true
}

docker_compose_file() {
    docker inspect "$1" \
        --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' \
        2>/dev/null || true
}

docker_compose_directory() {
    docker inspect "$1" \
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

    if [[ -z "${version}" && "${container}" == "${HOME_ASSISTANT_CONTAINER}" ]]; then
        version="$(docker exec "${container}" python3 -c \
            'from homeassistant.const import __version__; print(__version__)' \
            2>/dev/null || true)"
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

        cache_age="$(( $(date +%s) - $(stat -c %Y "${cache_file}") ))"

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

clear_version_cache() {
    rm -f "${VERSIONS_CACHE_DIR}"/*.txt 2>/dev/null || true
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
    local zigbee_installed zigbee_latest zigbee_update
    local node_red_installed node_red_latest node_red_update
    local home_assistant_installed home_assistant_latest home_assistant_update
    local temporary

    zigbee_installed="$(get_installed_version "${ZIGBEE_CONTAINER}")"
    zigbee_latest="$(get_latest_github_version "Koenkk/zigbee2mqtt")"

    node_red_installed="$(get_installed_version "${NODE_RED_CONTAINER}")"
    node_red_latest="$(get_latest_github_version "node-red/node-red")"

    home_assistant_installed="$(get_installed_version "${HOME_ASSISTANT_CONTAINER}")"
    home_assistant_latest="$(get_latest_github_version "home-assistant/core")"

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

    if version_is_older "${home_assistant_installed}" "${home_assistant_latest}"; then
        home_assistant_update="true"
    else
        home_assistant_update="false"
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
  },
  "home-assistant": {
    "installed": "${home_assistant_installed}",
    "latest": "${home_assistant_latest}",
    "update_available": ${home_assistant_update}
  }
}
EOF

    mv "${temporary}" "${VERSIONS_FILE}"
    chmod 644 "${VERSIONS_FILE}"

    write_host_ip_file

    log "Version information updated:"
    log "  Zigbee2MQTT: installed=${zigbee_installed}, latest=${zigbee_latest}"
    log "  Node-RED: installed=${node_red_installed}, latest=${node_red_latest}"
    log "  Home Assistant: installed=${home_assistant_installed}, latest=${home_assistant_latest}"
}

# ============================================================
# Container update (Docker Compose)
# ============================================================

# Portainer stores stacks under /data/compose/<id>/ INSIDE its own container.
# The compose labels keep that path, which doesn't exist on the host.
# Map it to the Portainer data volume on the host.
resolve_host_path() {
    local path="$1"
    local portainer_container=""
    local source=""
    local candidate=""

    if [[ -e "${path}" ]]; then
        printf '%s' "${path}"
        return
    fi

    if [[ "${path}" == /data/* ]]; then
        portainer_container="$(docker ps -a --format '{{.Names}}' \
            | grep -i portainer | head -n 1 || true)"

        if [[ -n "${portainer_container}" ]]; then
            source="$(docker inspect "${portainer_container}" \
                --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' \
                2>/dev/null || true)"

            candidate="${source}${path#/data}"

            if [[ -n "${source}" && -e "${candidate}" ]]; then
                printf '%s' "${candidate}"
                return
            fi
        fi

        for candidate in /var/lib/docker/volumes/*/_data"${path#/data}"; do
            if [[ -e "${candidate}" ]]; then
                printf '%s' "${candidate}"
                return
            fi
        done
    fi

    printf '%s' "${path}"
}

update_container() {
    local container="$1"

    local compose_service compose_project compose_files compose_directory
    local image_ref before after output rc f
    local -a compose_args=()
    local -a files=()

    compose_service="$(docker_compose_service "${container}")"
    compose_project="$(docker_compose_project "${container}")"
    compose_files="$(docker_compose_file "${container}")"
    compose_directory="$(docker_compose_directory "${container}")"

    if [[ -z "${compose_service}" || -z "${compose_project}" || -z "${compose_files}" ]]; then
        log "${container} is not managed by Docker Compose, update skipped"
        return
    fi

    # The label can hold several compose files, separated by commas
    IFS=',' read -ra files <<< "${compose_files}"
    for f in "${files[@]}"; do
        f="$(resolve_host_path "${f}")"

        if [[ ! -f "${f}" ]]; then
            log "Compose file not found on host: ${f}"
            log "Update skipped (for Portainer stacks, update from the Portainer UI instead)"
            return
        fi

        compose_args+=(-f "${f}")
    done

    # Use the resolved directory of the first compose file, so relative
    # paths such as stack.env or .env resolve correctly.
    compose_directory="$(dirname "${compose_args[1]}")"
    compose_args+=(--project-directory "${compose_directory}")

    image_ref="$(docker inspect "${container}" --format '{{.Config.Image}}')"
    before="$(docker inspect "${container}" --format '{{.Image}}')"

    log "Updating ${container} (image: ${image_ref})"

    output="$(docker compose -p "${compose_project}" "${compose_args[@]}" \
        pull "${compose_service}" 2>&1)"
    rc=$?
    log_block "pull" "${output}"

    if (( rc != 0 )); then
        log "Pull failed for ${compose_service} (exit ${rc}), update aborted"
        return
    fi

    output="$(docker compose -p "${compose_project}" "${compose_args[@]}" \
        up -d "${compose_service}" 2>&1)"
    rc=$?
    log_block "up" "${output}"

    if (( rc != 0 )); then
        log "Failed to recreate ${compose_service} (exit ${rc})"
        return
    fi

    # The container ID changes on recreate, so look it up again by name
    after="$(docker inspect "${container}" --format '{{.Image}}' 2>/dev/null || true)"

    if [[ "${before}" == "${after}" ]]; then
        log "No new image for ${image_ref}: already current, or the tag is pinned in the compose file"
    else
        log "Updated ${container}: ${before:7:12} -> ${after:7:12}"
        docker image prune -f >/dev/null 2>&1 || true
    fi

    clear_version_cache
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
        "Home Assistant")
            container="${HOME_ASSISTANT_CONTAINER}"
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
            update_container "${container}"
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

    if ! valid_username "${username}"; then
        log "Mosquitto-AddUser: invalid username (allowed: A-Z a-z 0-9 . _ @ -)"
        return
    fi

    if ! docker_container_exists "${MOSQUITTO_CONTAINER}"; then
        log "Mosquitto container not found: ${MOSQUITTO_CONTAINER}"
        return
    fi

    log "Replacing Mosquitto credentials with user: ${username}"

    # -c recreates the password file: all other users are removed
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

    chmod "${CREDENTIALS_MODE}" "${CREDENTIALS_FILE}.tmp"
    mv "${CREDENTIALS_FILE}.tmp" "${CREDENTIALS_FILE}"

    log "Mosquitto credentials updated"
}

# ============================================================
# Node-RED login management
# ============================================================

update_node_red_credentials() {
    local command_file="$1"
    local username=""
    local password=""
    local content=""
    local temporary=""

    username="$(sed -n '1p' "${command_file}")"
    password="$(sed -n '2p' "${command_file}")"

    username="${username//$'\r'/}"
    password="${password//$'\r'/}"

    if [[ -z "${username}" || -z "${password}" ]]; then
        log "Node-RED-SetCredentials: missing username or password"
        return
    fi

    if ! valid_username "${username}"; then
        log "Node-RED-SetCredentials: invalid username (allowed: A-Z a-z 0-9 . _ @ -)"
        return
    fi

    if [[ ! -f "${NODE_RED_SETTINGS_FILE}" ]]; then
        log "Node-RED settings file not found: ${NODE_RED_SETTINGS_FILE}"
        return
    fi

    if ! docker_container_exists "${NODE_RED_CONTAINER}"; then
        log "Node-RED container not found: ${NODE_RED_CONTAINER}"
        return
    fi

    # The whole file is generated inside the container. Username and password
    # go through stdin (not argv), and JSON.stringify handles all quoting.
    content="$(printf '%s\n%s\n' "${username}" "${password}" \
        | docker exec -i "${NODE_RED_CONTAINER}" node -e '
            const lines = require("fs").readFileSync(0, "utf8").split("\n");
            let bcrypt;
            try { bcrypt = require("bcryptjs"); } catch (e) { bcrypt = require("bcrypt"); }
            const auth = {
                type: "credentials",
                users: [{
                    username: lines[0],
                    password: bcrypt.hashSync(lines[1], 8),
                    permissions: "*"
                }]
            };
            console.log("module.exports = " + JSON.stringify(auth, null, 4) + ";");
        ' 2>/dev/null)"

    if [[ -z "${content}" || "${content}" != module.exports* ]]; then
        log "Failed to generate Node-RED credentials file"
        return
    fi

    temporary="${NODE_RED_AUTH_FILE}.tmp"
    printf '%s\n' "${content}" > "${temporary}"

    write_in_place "${temporary}" "${NODE_RED_AUTH_FILE}"
    rm -f "${temporary}"
    chmod 644 "${NODE_RED_AUTH_FILE}"

    if ! docker restart "${NODE_RED_CONTAINER}"; then
        log "Failed to restart Node-RED"
        return
    fi

    log "Node-RED login updated for user: ${username}"
}

# ============================================================
# Zigbee2MQTT frontend token management
# ============================================================

update_zigbee_token() {
    local command_file="$1"
    local token=""
    local temporary=""

    token="$(sed -n '1p' "${command_file}")"
    token="${token//$'\r'/}"

    if [[ -z "${token}" ]]; then
        log "Zigbee2MQTT-SetToken: missing token"
        return
    fi

    if ! valid_token "${token}"; then
        log "Zigbee2MQTT-SetToken: invalid token (allowed: A-Z a-z 0-9 . _ -)"
        return
    fi

    if [[ ! -f "${ZIGBEE_CONFIG_FILE}" ]]; then
        log "Zigbee2MQTT configuration file not found: ${ZIGBEE_CONFIG_FILE}"
        return
    fi

    if ! docker_container_exists "${ZIGBEE_CONTAINER}"; then
        log "Zigbee2MQTT container not found: ${ZIGBEE_CONTAINER}"
        return
    fi

    log "Updating Zigbee2MQTT frontend token"

    temporary="${ZIGBEE_CONFIG_FILE}.tmp"

    if ! sed \
        "s|^\([[:space:]]*\)auth_token:.*|\1auth_token: \"${token}\"|" \
        "${ZIGBEE_CONFIG_FILE}" > "${temporary}"; then
        log "Failed to generate Zigbee2MQTT configuration"
        rm -f "${temporary}"
        return
    fi

    if ! grep -q "auth_token: \"${token}\"" "${temporary}"; then
        log "No auth_token line found in ${ZIGBEE_CONFIG_FILE}, nothing changed"
        rm -f "${temporary}"
        return
    fi

    write_in_place "${temporary}" "${ZIGBEE_CONFIG_FILE}"
    rm -f "${temporary}"

    if ! docker restart "${ZIGBEE_CONTAINER}"; then
        log "Failed to restart Zigbee2MQTT"
        return
    fi

    log "Zigbee2MQTT frontend token updated"
}

# ============================================================
# Command processing
# ============================================================

process_command_file() {
    local command_file="$1"
    local command_name
    local service=""
    local action=""

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
            log "System update requested (not implemented)"
            rm -f "${command_file}"
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

        Home\ Assistant-Start|Home\ Assistant-Stop|Home\ Assistant-Restart|Home\ Assistant-Update)
            service="Home Assistant"
            action="${command_name#Home Assistant-}"
            rm -f "${command_file}"
            run_service_action "${service}" "${action}"
            ;;

        Mosquitto-AddUser)
            add_mosquitto_user "${command_file}"
            rm -f "${command_file}"
            ;;

        Node-RED-SetCredentials)
            update_node_red_credentials "${command_file}"
            rm -f "${command_file}"
            ;;

        Zigbee2MQTT-SetToken)
            update_zigbee_token "${command_file}"
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

        # Dotfiles are ignored, so writers can create ".name.tmp"
        # and mv it into place once it is complete.
        [[ "$(basename "${command_file}")" == .* ]] && continue

        process_command_file "${command_file}"
    done

    shopt -u nullglob
}

# ============================================================
# Main loop: check commands every 5 seconds
# ============================================================

log "Meek.io action handler started"

process_commands

write_versions_file

LAST_VERSION_UPDATE="$(date +%s)"

while true; do
    process_commands

    now="$(date +%s)"

    if (( now - LAST_VERSION_UPDATE >= VERSION_REFRESH_SECONDS )); then
        write_versions_file
        LAST_VERSION_UPDATE="${now}"
    fi

    sleep "${CHECK_INTERVAL_SECONDS}"
done
