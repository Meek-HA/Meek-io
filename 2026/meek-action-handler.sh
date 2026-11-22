#!/usr/bin/env bash
# No "set -e" on purpose: this is a long-running daemon, and a single failed
# command must not kill the loop. Errors are handled and logged explicitly.
set -uo pipefail
umask 077
shopt -s nullglob

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

# Owner of the credentials file: the user PHP runs as in the nginx
# container (abc, uid/gid 1000), so the admin page can read it.
CREDENTIALS_OWNER="1000:1000"

ZIGBEE_CONTAINER="zigbee2mqtt"
NODE_RED_CONTAINER="node-red-node-red-1"
HOME_ASSISTANT_CONTAINER="homeassistant"
MOSQUITTO_CONTAINER="mosquitto"
MOSQUITTO_PASSWORD_FILE="/mosquitto/config/passwd"

# UID/GID used by the Mosquitto process in its container.
MOSQUITTO_UID_GID="1883:1883"

# Node-RED data folder on the host (mounted at /data in the container).
# It must be owned by the node-red user (uid/gid 1000) or Node-RED cannot
# write its settings.js on first start.
NODE_RED_DATA_DIR="/meek-io/node-red"
NODE_RED_UID_GID="1000:1000"

# Self update (System > Update)
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
INDEX_PHP_PATH="/meek-io/nginx/config/www/admin/index.php"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/Meek-HA/Meek-io/master/2026"
SERVICE_NAME="meek-action-handler"

CHECK_INTERVAL_SECONDS="4"
VERSION_REFRESH_SECONDS="3600"
HOST_IP_REFRESH_SECONDS="60"

# Must stay shorter than VERSION_REFRESH_SECONDS, so every refresh
# fetches fresh data instead of reusing a cache that is almost 1h old.
VERSION_CACHE_MAX_AGE_SECONDS="3000"

# After a failed GitHub request, do not retry for this long.
VERSION_FAIL_BACKOFF_SECONDS="300"

# Safety limits
DOCKER_TIMEOUT_SECONDS="120"
COMPOSE_TIMEOUT_SECONDS="900"
MAX_COMMAND_BYTES="4096"

LAST_HOST_IP=""

# ============================================================
# Logging
# ============================================================

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

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
# Single instance lock (taken before anything else is touched)
# ============================================================

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    log "Another instance is already running, exiting"
    exit 1
fi

cleanup() {
    rm -f \
        "${VERSIONS_FILE}.tmp" \
        "${HOST_IP_FILE}.tmp" \
        "${CREDENTIALS_FILE}.tmp" \
        2>/dev/null || true
}

trap cleanup EXIT
trap 'log "Signal received, shutting down"; exit 0' TERM INT

# ============================================================
# Preparation
# ============================================================

mkdir -p "${COMMANDS_DIR}" "${SETTINGS_DIR}" "${VERSIONS_CACHE_DIR}"

touch "${CREDENTIALS_FILE}"
chmod "${CREDENTIALS_MODE}" "${CREDENTIALS_FILE}"
chown "${CREDENTIALS_OWNER}" "${CREDENTIALS_FILE}" \
    || log "WARNING: could not chown ${CREDENTIALS_FILE} to ${CREDENTIALS_OWNER}"

# Make sure Node-RED can write to its data folder.
if [[ -d "${NODE_RED_DATA_DIR}" ]]; then
    chown -R "${NODE_RED_UID_GID}" "${NODE_RED_DATA_DIR}" 2>/dev/null \
        || log "WARNING: could not chown ${NODE_RED_DATA_DIR} to ${NODE_RED_UID_GID}"
fi

# Claimed command files left behind by a crash may hold passwords: remove them.
rm -f "${COMMANDS_DIR}"/*.processing.*

# ============================================================
# Input helpers
# ============================================================

valid_username() {
    [[ "$1" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]
}

# Read every line of a command file into an indexed array.
# The nameref must use a different name from the caller's array,
# otherwise Bash reports a circular name reference.
read_command_fields() {
    local file="$1"
    local -n command_fields="$2"
    local line
    local index=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        command_fields[$((index++))]="${line//$'\r'/}"
    done < "${file}"
}

# Escape a string for use inside a JSON string literal.
json_escape() {
    local s="$1"

    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//[$'\001'-$'\037']/}"

    printf '%s' "${s}"
}

# ============================================================
# Docker helpers
# ============================================================

# Run docker with a timeout. fd 9 (the lock) is closed for the child, so a
# lingering docker process can never keep the lock after this script exits.
docker_run() {
    timeout "${DOCKER_TIMEOUT_SECONDS}" docker "$@" 9>&-
}

# Same, but logs the output with a prefix. Returns docker's exit status.
docker_logged() {
    local label="$1"
    local output rc
    shift

    output="$(docker_run "$@" 2>&1)"
    rc=$?
    log_block "${label}" "${output}"

    return "${rc}"
}

docker_container_exists() {
    docker inspect "$1" >/dev/null 2>&1
}

docker_container_running() {
    [[ "$(docker inspect "$1" --format '{{.State.Running}}' 2>/dev/null)" == "true" ]]
}

docker_label() {
    local container="$1"
    local label="$2"

    docker inspect "${container}" \
        --format "{{index .Config.Labels \"${label}\"}}" \
        2>/dev/null || true
}

# ============================================================
# Host IP helper
# ============================================================

write_host_ip_file() {
    local host_ip=""

    # Ask the kernel which source address it would use to reach the internet.
    # This avoids picking docker0 / br-* bridge addresses.
    host_ip="$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"

    if [[ -z "${host_ip}" ]]; then
        host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    if [[ -z "${host_ip}" ]]; then
        host_ip="Unknown"
    fi

    printf '%s' "${host_ip}" > "${HOST_IP_FILE}.tmp"
    mv "${HOST_IP_FILE}.tmp" "${HOST_IP_FILE}"
    chmod 644 "${HOST_IP_FILE}"

    if [[ "${host_ip}" != "${LAST_HOST_IP}" ]]; then
        log "Host IP updated: ${host_ip}"
        LAST_HOST_IP="${host_ip}"
    fi
}

# ============================================================
# Version helpers
#
# The handler only records the installed and latest versions.
# The admin page decides whether an update is available.
# ============================================================

get_installed_version() {
    local container="$1"
    local version=""

    version="$(docker_label "${container}" "org.opencontainers.image.version")"

    if [[ -z "${version}" ]]; then
        version="$(docker_label "${container}" "org.label-schema.version")"
    fi

    if [[ -z "${version}" && "${container}" == "${HOME_ASSISTANT_CONTAINER}" ]]; then
        version="$(docker_run exec "${container}" python3 -c \
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
    local fail_file="${cache_file}.fail"
    local response=""
    local version=""
    local age

    if [[ -f "${cache_file}" ]]; then
        age="$(( $(date +%s) - $(stat -c %Y "${cache_file}") ))"

        if (( age < VERSION_CACHE_MAX_AGE_SECONDS )); then
            cat "${cache_file}"
            return
        fi
    fi

    # Recent failure: do not hammer GitHub (and block the loop for 10 s per repo)
    if [[ -f "${fail_file}" ]]; then
        age="$(( $(date +%s) - $(stat -c %Y "${fail_file}") ))"

        if (( age < VERSION_FAIL_BACKOFF_SECONDS )); then
            if [[ -f "${cache_file}" ]]; then
                cat "${cache_file}"
            else
                printf 'Unknown'
            fi

            return
        fi
    fi

    response="$(curl -fsSL \
        --max-time 10 \
        -H 'User-Agent: Meek-io-Action-Handler' \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${repository}/releases/latest" \
        2>/dev/null 9>&- || true)"

    version="$(printf '%s' "${response}" \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -n 1 \
        | cut -d '"' -f 4 || true)"

    # Image labels usually have no "v" prefix, GitHub tags often do
    version="${version#v}"

    if [[ -z "${version}" ]]; then
        # GitHub unreachable or rate limited: remember the failure and
        # fall back to the old cache
        touch "${fail_file}"

        if [[ -f "${cache_file}" ]]; then
            cat "${cache_file}"
        else
            printf 'Unknown'
        fi

        return
    fi

    rm -f "${fail_file}"
    printf '%s' "${version}" > "${cache_file}"
    chmod 644 "${cache_file}"

    printf '%s' "${version}"
}

refresh_version_cache() {
    local repository="$1"
    local cache_file="${VERSIONS_CACHE_DIR}/${repository//\//_}.txt"

    rm -f "${cache_file}" "${cache_file}.fail" 2>/dev/null || true
}

write_versions_file() {
    local zigbee_installed zigbee_latest
    local node_red_installed node_red_latest
    local home_assistant_installed home_assistant_latest
    local temporary="${VERSIONS_FILE}.tmp"

    zigbee_installed="$(get_installed_version "${ZIGBEE_CONTAINER}")"
    zigbee_latest="$(get_latest_github_version "Koenkk/zigbee2mqtt")"

    node_red_installed="$(get_installed_version "${NODE_RED_CONTAINER}")"
    node_red_latest="$(get_latest_github_version "node-red/node-red")"

    home_assistant_installed="$(get_installed_version "${HOME_ASSISTANT_CONTAINER}")"
    home_assistant_latest="$(get_latest_github_version "home-assistant/core")"

    cat > "${temporary}" <<EOF
{
  "updated_at": "$(date -Is)",
  "zigbee2mqtt": {
    "installed": "$(json_escape "${zigbee_installed}")",
    "latest": "$(json_escape "${zigbee_latest}")"
  },
  "node-red": {
    "installed": "$(json_escape "${node_red_installed}")",
    "latest": "$(json_escape "${node_red_latest}")"
  },
  "home-assistant": {
    "installed": "$(json_escape "${home_assistant_installed}")",
    "latest": "$(json_escape "${home_assistant_latest}")"
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
    local image_ref before after output rc f first_compose_file
    local -a compose_args=()
    local -a files=()

    compose_service="$(docker_label "${container}" "com.docker.compose.service")"
    compose_project="$(docker_label "${container}" "com.docker.compose.project")"
    compose_files="$(docker_label "${container}" "com.docker.compose.project.config_files")"

    if [[ -z "${compose_service}" || -z "${compose_project}" || -z "${compose_files}" ]]; then
        log "${container} is not managed by Docker Compose, update skipped"
        return
    fi

    # The label can hold several compose files, separated by commas
    IFS=',' read -ra files <<< "${compose_files}"

    first_compose_file="$(resolve_host_path "${files[0]}")"

    if [[ ! -f "${first_compose_file}" ]]; then
        log "Compose file not found on host: ${first_compose_file}"
        log "Update skipped (for Portainer stacks, update from the Portainer UI instead)"
        return
    fi

    for f in "${files[@]}"; do
        f="$(resolve_host_path "${f}")"

        if [[ ! -f "${f}" ]]; then
            log "Compose file not found on host: ${f}"
            log "Update skipped (for Portainer stacks, update from the Portainer UI instead)"
            return
        fi

        compose_args+=(-f "${f}")
    done

    # Use the directory of the first resolved compose file, so relative
    # paths such as stack.env or .env resolve correctly.
    compose_directory="$(dirname "${first_compose_file}")"
    compose_args+=(--project-directory "${compose_directory}")

    image_ref="$(docker inspect "${container}" --format '{{.Config.Image}}')"
    before="$(docker inspect "${container}" --format '{{.Image}}')"

    log "Updating ${container} (image: ${image_ref})"

    output="$(timeout "${COMPOSE_TIMEOUT_SECONDS}" \
        docker compose -p "${compose_project}" "${compose_args[@]}" \
        pull "${compose_service}" 2>&1 9>&-)"
    rc=$?
    log_block "pull" "${output}"

    if (( rc != 0 )); then
        log "Pull failed for ${compose_service} (exit ${rc}), update aborted"
        return
    fi

    # Make sure Docker never creates the Node-RED data folder as root
    # and that the node-red user can write to it.
    if [[ "${container}" == "${NODE_RED_CONTAINER}" ]]; then
        mkdir -p "${NODE_RED_DATA_DIR}" \
            && chown -R "${NODE_RED_UID_GID}" "${NODE_RED_DATA_DIR}" 2>/dev/null \
            || log "WARNING: could not prepare ${NODE_RED_DATA_DIR}"
    fi

    output="$(timeout "${COMPOSE_TIMEOUT_SECONDS}" \
        docker compose -p "${compose_project}" "${compose_args[@]}" \
        up -d "${compose_service}" 2>&1 9>&-)"
    rc=$?
    log_block "up" "${output}"

    if (( rc != 0 )); then
        log "Failed to recreate ${compose_service} (exit ${rc})"
        return
    fi

    if ! docker_container_running "${container}"; then
        log "WARNING: ${container} is not running after the update"
    fi

    # The container ID changes on recreate, so look it up again by name
    after="$(docker inspect "${container}" --format '{{.Image}}' 2>/dev/null || true)"

    if [[ "${before}" == "${after}" ]]; then
        log "No new image for ${image_ref}: already current, or the tag is pinned in the compose file"
    else
        log "Updated ${container}: ${before:7:12} -> ${after:7:12}"
        docker image prune -f >/dev/null 2>&1 || true
    fi

    case "${container}" in
        "${ZIGBEE_CONTAINER}")
            refresh_version_cache "Koenkk/zigbee2mqtt"
            ;;

        "${NODE_RED_CONTAINER}")
            refresh_version_cache "node-red/node-red"
            ;;

        "${HOME_ASSISTANT_CONTAINER}")
            refresh_version_cache "home-assistant/core"
            ;;
    esac
}

# ============================================================
# Service actions
# ============================================================

run_service_action() {
    local service="$1"
    local action="$2"
    local container=""

    case "${service}" in
        Zigbee2MQTT)      container="${ZIGBEE_CONTAINER}" ;;
        Node-RED)         container="${NODE_RED_CONTAINER}" ;;
        "Home Assistant") container="${HOME_ASSISTANT_CONTAINER}" ;;
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
            docker_logged "start" start "${container}" || log "Failed to start ${container}"
            ;;

        Stop)
            if [[ "${service}" == "Zigbee2MQTT" ]]; then
                log "Killing ${container}"
                docker_logged "kill" kill "${container}" || log "Failed to kill ${container}"
            else
                log "Stopping ${container}"
                docker_logged "stop" stop "${container}" || log "Failed to stop ${container}"
            fi
            ;;

        Restart)
            log "Restarting ${container}"
            docker_logged "restart" restart "${container}" || log "Failed to restart ${container}"
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
    local username="${1:-}"
    local password="${2:-}"
    local output

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

    # "mosquitto_passwd -c" refuses to write to a file that already exists
    # ("File exists"). So the hash file is generated at a fresh temporary path
    # and then copied over the real file with "cat >", which keeps the inode.
    # -c means all previous users are replaced by this single user.
    # Values are passed as positional parameters ($1..$4), never interpolated
    # into the shell command, so there is no quoting or injection problem.
    if ! output="$(docker_run exec -u 0:0 "${MOSQUITTO_CONTAINER}" sh -c '
        set -e
        tmp="$(mktemp -u /tmp/passwd.XXXXXX)"
        trap "rm -f \"$tmp\"" EXIT
        mosquitto_passwd -b -c "$tmp" "$1" "$2" >/dev/null
        cat "$tmp" > "$3"
        chown "$4" "$3"
        chmod 600 "$3"
    ' _ "${username}" "${password}" \
        "${MOSQUITTO_PASSWORD_FILE}" "${MOSQUITTO_UID_GID}" 2>&1)"; then
        log_block "mosquitto_passwd" "${output}"
        log "Failed to update Mosquitto password file"
        return
    fi

    # The password file is now changed, so record the credentials right away,
    # even if the restart below fails.
    printf 'username=%s\npassword=%s\n' \
        "${username}" \
        "${password}" \
        > "${CREDENTIALS_FILE}.tmp"

    chmod "${CREDENTIALS_MODE}" "${CREDENTIALS_FILE}.tmp"
    chown "${CREDENTIALS_OWNER}" "${CREDENTIALS_FILE}.tmp" \
        || log "WARNING: could not chown credentials file to ${CREDENTIALS_OWNER}"
    mv "${CREDENTIALS_FILE}.tmp" "${CREDENTIALS_FILE}"

    if ! docker_logged "restart" restart "${MOSQUITTO_CONTAINER}"; then
        log "Failed to restart Mosquitto (password file was updated, restart it manually)"
        return
    fi

    log "Mosquitto credentials updated"
}

# ============================================================
# Home Assistant password management
# ============================================================

update_home_assistant_password() {
    local username="${1:-}"
    local password="${2:-}"
    local output

    if [[ -z "${username}" || -z "${password}" ]]; then
        log "HomeAssistant-SetPassword: missing username or password"
        return
    fi

    if ! valid_username "${username}"; then
        log "HomeAssistant-SetPassword: invalid username (allowed: A-Z a-z 0-9 . _ @ -)"
        return
    fi

    if ! docker_container_exists "${HOME_ASSISTANT_CONTAINER}"; then
        log "Home Assistant container not found: ${HOME_ASSISTANT_CONTAINER}"
        return
    fi

    if ! docker_container_running "${HOME_ASSISTANT_CONTAINER}"; then
        log "Home Assistant is not running, password change skipped"
        return
    fi

    log "Changing Home Assistant password for user: ${username}"

    output="$(docker_run exec "${HOME_ASSISTANT_CONTAINER}" \
        hass --script auth --config /config \
        change_password "${username}" "${password}" 2>&1)"

    log_block "hass" "${output}"

    # The script exits 0 even when the user does not exist,
    # so the success message is the reliable signal.
    if [[ "${output}" != *"Password changed"* ]]; then
        log "Home Assistant password was NOT changed (does the user exist?)"
        return
    fi

    if ! docker_logged "restart" restart "${HOME_ASSISTANT_CONTAINER}"; then
        log "Failed to restart Home Assistant"
        return
    fi

    write_versions_file

    log "Home Assistant password updated for user: ${username}"
}

# ============================================================
# Self update from GitHub
# ============================================================

# download_and_install <url> <target> <php|sh>
# Returns 0 = replaced, 2 = already identical, 1 = failed.
# The new file is validated first and moved into place atomically
# (new inode), so a running copy of this script is never overwritten
# while Bash is still reading it.
download_and_install() {
    local url="$1"
    local target="$2"
    local kind="$3"
    local temporary="${target}.new.$$"

    if ! curl -fsSL --max-time 30 \
        -H 'User-Agent: Meek-io-Action-Handler' \
        "${url}" -o "${temporary}" 9>&-; then
        log "Download failed: ${url}"
        rm -f "${temporary}"
        return 1
    fi

    if (( $(stat -c %s "${temporary}" 2>/dev/null || echo 0) < 500 )); then
        log "Downloaded file is empty or too small: ${url}"
        rm -f "${temporary}"
        return 1
    fi

    case "${kind}" in
        php)
            if [[ "$(head -c 5 "${temporary}")" != "<?php" ]]; then
                log "Downloaded file is not a PHP file: ${url}"
                rm -f "${temporary}"
                return 1
            fi

            if command -v php >/dev/null 2>&1 && ! php -l "${temporary}" >/dev/null 2>&1; then
                log "PHP syntax check failed: ${url}"
                rm -f "${temporary}"
                return 1
            fi
            ;;

        sh)
            if [[ "$(head -n 1 "${temporary}")" != "#!/usr/bin/env bash" ]] \
                || ! bash -n "${temporary}" 2>/dev/null; then
                log "Shell script check failed: ${url}"
                rm -f "${temporary}"
                return 1
            fi
            ;;
    esac

    if [[ -f "${target}" ]]; then
        if cmp -s "${temporary}" "${target}"; then
            rm -f "${temporary}"
            return 2
        fi

        # umask 077 made the temp file private: copy owner and mode from
        # the old file so PHP (user abc) can still read the new one.
        chown --reference="${target}" "${temporary}" 2>/dev/null || true
        chmod --reference="${target}" "${temporary}" 2>/dev/null || true
    else
        chmod 644 "${temporary}"
    fi

    if ! mv -f "${temporary}" "${target}"; then
        log "Could not replace ${target}"
        rm -f "${temporary}"
        return 1
    fi

    return 0
}

update_meek_files() {
    local rc restart_needed=0

    log "System update: fetching latest files from GitHub"

    download_and_install "${GITHUB_RAW_BASE}/index.php" "${INDEX_PHP_PATH}" php
    rc=$?
    case "${rc}" in
        0) log "index.php updated" ;;
        2) log "index.php is already up to date" ;;
        *) log "index.php update failed" ;;
    esac

    download_and_install "${GITHUB_RAW_BASE}/meek-action-handler.sh" "${SELF_PATH}" sh
    rc=$?
    case "${rc}" in
        0) log "Action handler updated"; restart_needed=1 ;;
        2) log "Action handler is already up to date" ;;
        *) log "Action handler update failed" ;;
    esac

    if (( restart_needed )); then
        log "Restarting ${SERVICE_NAME} to load the new version"
        systemctl restart --no-block "${SERVICE_NAME}" \
            || log "Could not restart ${SERVICE_NAME}, restart it manually"
    fi
}

# ============================================================
# Command processing
# ============================================================

process_command_file() {
    local command_file="$1"
    local command_name="${command_file##*/}"
    local safe_name="${command_name//[^[:print:]]/?}"
    local claimed_file="${command_file}.processing.$$"
    local service_regex='^(Zigbee2MQTT|Node-RED|Home Assistant|HomeAssistant)-(Start|Stop|Restart|Update)$'
    local size service action
    local -a fields=()

    [[ -f "${command_file}" || -L "${command_file}" ]] || return

    # Atomically claim the command before reading or acting on it.
    # This prevents a newly published command with the same name from
    # being read partially or deleted before it can be processed.
    if ! mv "${command_file}" "${claimed_file}" 2>/dev/null; then
        return
    fi

    log "Processing command: ${safe_name}"

    # A symlink would make "read" follow it to an arbitrary file
    if [[ -L "${claimed_file}" ]]; then
        log "Ignoring symlink command: ${safe_name}"
        rm -f "${claimed_file}"
        return
    fi

    size="$(stat -c %s "${claimed_file}" 2>/dev/null || echo 0)"

    if (( size > MAX_COMMAND_BYTES )); then
        log "Ignoring oversized command (${size} bytes): ${safe_name}"
        rm -f "${claimed_file}"
        return
    fi

    # Read the content once and delete the file right away, so passwords
    # do not stay on disk while slow actions (restarts, updates) run.
    read_command_fields "${claimed_file}" fields
    rm -f "${claimed_file}"

    if [[ "${command_name}" =~ ${service_regex} ]]; then
        service="${BASH_REMATCH[1]}"
        action="${BASH_REMATCH[2]}"

        [[ "${service}" == "HomeAssistant" ]] && service="Home Assistant"

        run_service_action "${service}" "${action}"
        return
    fi

    case "${command_name}" in
        System-Reboot)
            log "Reboot requested"
            sync
            sleep 2
            reboot
            ;;

        System-Update)
            update_meek_files
            ;;

        Mosquitto-AddUser)
            add_mosquitto_user "${fields[0]:-}" "${fields[1]:-}"
            ;;

        HomeAssistant-SetPassword)
            update_home_assistant_password "${fields[0]:-}" "${fields[1]:-}"
            ;;

        *)
            log "Ignoring unknown command: ${safe_name}"
            ;;
    esac
}

process_commands() {
    local command_file name

    for command_file in "${COMMANDS_DIR}"/*; do
        name="${command_file##*/}"

        # Dotfiles are ignored, so writers can create ".name.tmp"
        # and mv it into place once it is complete.
        [[ "${name}" == .* ]] && continue
        [[ "${name}" == *.processing.* ]] && continue

        process_command_file "${command_file}"
    done
}

# ============================================================
# Main loop: check commands every CHECK_INTERVAL_SECONDS
# ============================================================

log "Meek.io action handler started"

process_commands

write_versions_file

LAST_VERSION_UPDATE="$(date +%s)"
LAST_HOST_IP_UPDATE="${LAST_VERSION_UPDATE}"

while true; do
    process_commands

    now="$(date +%s)"

    if (( now - LAST_VERSION_UPDATE >= VERSION_REFRESH_SECONDS )); then
        write_versions_file
        LAST_VERSION_UPDATE="${now}"
        LAST_HOST_IP_UPDATE="${now}"
    elif (( now - LAST_HOST_IP_UPDATE >= HOST_IP_REFRESH_SECONDS )); then
        write_host_ip_file
        LAST_HOST_IP_UPDATE="${now}"
    fi

    # Sleep in the background and wait, so SIGTERM is handled immediately
    sleep "${CHECK_INTERVAL_SECONDS}" 9>&- &
    wait $!
done
