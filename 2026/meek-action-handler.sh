#!/usr/bin/env bash
set -uo pipefail

ACTION_DIR="/meek-io/meek/commands"
LOG_FILE="/var/log/meek-action-handler.log"

HOME_ASSISTANT_COMPOSE="/var/lib/docker/volumes/portainer_data/_data/compose/1/docker-compose.yml"

ZIGBEE_CONTAINER="zigbee2mqtt"
NODE_RED_CONTAINER="node-red-node-red-1"
MOSQUITTO_CONTAINER="mosquitto"

# Optional explicit Compose paths.
# Leave empty to discover them from the containers' Compose labels.
ZIGBEE_COMPOSE=""
NODE_RED_COMPOSE=""

# Must match password_file in your Mosquitto configuration.
MOSQUITTO_PASSWORD_FILE="/mosquitto/config/passwd"

# Plaintext record of the currently configured Mosquitto credentials.
# The PHP admin page must mount /meek-io/meek/commands at
# /config/www/actions to read this file.
MOSQUITTO_CREDENTIALS_FILE="/meek-io/meek/commands/MQTT/current-credentials.txt"

# Host IP file read by Node-RED through the shared commands volume.
HOST_IP_FILE="$ACTION_DIR/MQTT/host-ip.txt"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >> "$LOG_FILE"
}

run_logged() {
    "$@" >> "$LOG_FILE" 2>&1
}

update_container() {
    local container="$1"
    local override="$2"
    local files service project working_dir path
    local -a compose_args file_list

    service="$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.service" }}' \
        "$container" 2>/dev/null)" || return 1

    if [[ -z "$service" || "$service" == "<no value>" ]]; then
        log "ERROR: No Compose service label on $container"
        return 1
    fi

    project="$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
        "$container" 2>/dev/null)" || return 1

    working_dir="$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
        "$container" 2>/dev/null)" || return 1

    if [[ -n "$override" ]]; then
        files="$override"
    else
        files="$(docker inspect \
            --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' \
            "$container" 2>/dev/null)" || return 1
    fi

    if [[ -z "$files" || "$files" == "<no value>" ]]; then
        log "ERROR: Compose path unavailable for $container; set its override"
        return 1
    fi

    compose_args=()

    if [[ -n "$project" && "$project" != "<no value>" ]]; then
        compose_args+=(-p "$project")
    fi

    if [[ -d "$working_dir" ]]; then
        compose_args+=(--project-directory "$working_dir")
    fi

    IFS=',' read -r -a file_list <<< "$files"

    for path in "${file_list[@]}"; do
        if [[ "$path" != /* && -d "$working_dir" ]]; then
            path="$working_dir/$path"
        fi

        if [[ ! -f "$path" ]]; then
            log "ERROR: Compose file not found: $path"
            return 1
        fi

        compose_args+=(-f "$path")
    done

    log "Pulling image for $container"

    run_logged docker compose "${compose_args[@]}" pull "$service" \
        || return 1

    log "Recreating $container"

    run_logged docker compose "${compose_args[@]}" up -d "$service"
}

save_host_ip() {
    local host_ip

    host_ip="$(hostname -I | awk '{print $1}')"

    if [[ -z "$host_ip" ]]; then
        log "ERROR: Could not determine host IP"
        return 1
    fi

    if ! mkdir -p -- "$(dirname -- "$HOST_IP_FILE")"; then
        log "ERROR: Could not create host IP directory: $(dirname -- "$HOST_IP_FILE")"
        return 1
    fi

    if ! printf '%s' "$host_ip" > "$HOST_IP_FILE"; then
        log "ERROR: Could not write host IP file: $HOST_IP_FILE"
        return 1
    fi

    chmod 644 "$HOST_IP_FILE"

    log "Saved host IP to $HOST_IP_FILE: $host_ip"
}

save_mosquitto_credentials() {
    local username="$1"
    local password="$2"
    local credentials_dir
    local credentials_temp

    credentials_dir="$(dirname -- "$MOSQUITTO_CREDENTIALS_FILE")"
    credentials_temp="${MOSQUITTO_CREDENTIALS_FILE}.tmp.$$"

    if ! mkdir -p -- "$credentials_dir"; then
        log "ERROR: Could not create credentials directory: $credentials_dir"
        return 1
    fi

    if ! printf 'username=%s\npassword=%s\n' \
        "$username" "$password" > "$credentials_temp"; then
        log "ERROR: Could not write temporary credentials file"
        rm -f -- "$credentials_temp"
        return 1
    fi

    chmod 644 "$credentials_temp"

    if ! mv -f -- "$credentials_temp" "$MOSQUITTO_CREDENTIALS_FILE"; then
        log "ERROR: Could not move credentials file into place"
        rm -f -- "$credentials_temp"
        return 1
    fi

    log "Saved current Mosquitto credentials to $MOSQUITTO_CREDENTIALS_FILE"
}

add_mosquitto_user() {
    local file="$1"
    local username password

    {
        IFS= read -r username || return 1
        IFS= read -r password || return 1
    } < "$file"

    if [[ -z "$username" || -z "$password" ]]; then
        log "ERROR: Empty Mosquitto username or password"
        return 1
    fi

    if [[ "$username" == *:* || "$username" == *$'\r'* ||
          "$password" == *$'\r'* ]]; then
        log "ERROR: Unsupported characters in Mosquitto request"
        return 1
    fi

    # The password file must already be configured and writable
    # inside the Mosquitto container.
    if ! docker exec "$MOSQUITTO_CONTAINER" \
        test -f "$MOSQUITTO_PASSWORD_FILE"; then
        log "ERROR: Mosquitto password file not found: $MOSQUITTO_PASSWORD_FILE"
        return 1
    fi

    # Recreate the password file with only this user.
    # -c overwrites the existing password file and removes all other users.
    if ! run_logged docker exec "$MOSQUITTO_CONTAINER" \
        mosquitto_passwd -b -c "$MOSQUITTO_PASSWORD_FILE" \
        "$username" "$password"; then
        log "ERROR: Failed to write Mosquitto user"
        return 1
    fi

    if ! save_mosquitto_credentials "$username" "$password"; then
        log "ERROR: Mosquitto user was updated, but credentials file could not be saved"
    fi

    # Restart to load the updated password file.
    run_logged docker restart "$MOSQUITTO_CONTAINER"
}

process_file() {
    local file="$1"
    local name
    name="$(basename -- "$file")"

    log "Processing action: $name"

    case "$name" in
        System-Reboot)
            rm -f -- "$file"
            log "Rebooting host"
            sync
            run_logged /sbin/reboot
            ;;

        System-Update)
            rm -f -- "$file"

            if [[ ! -f "$HOME_ASSISTANT_COMPOSE" ]]; then
                log "ERROR: Home Assistant Compose file not found"
                return
            fi

            log "Updating Home Assistant Compose project"

            if run_logged docker compose \
                -f "$HOME_ASSISTANT_COMPOSE" pull &&
               run_logged docker compose \
                -f "$HOME_ASSISTANT_COMPOSE" up -d; then
                log "Home Assistant project updated"
            else
                log "ERROR: Home Assistant project update failed"
            fi
            ;;

        Zigbee2MQTT-Start|Zigbee2MQTT-Stop|Zigbee2MQTT-Restart)
            rm -f -- "$file"

            local action="${name#Zigbee2MQTT-}"
            action="${action,,}"

            if run_logged docker "$action" "$ZIGBEE_CONTAINER"; then
                log "Completed: $name"
            else
                log "ERROR: Failed: $name"
            fi
            ;;

        Zigbee2MQTT-Update)
            rm -f -- "$file"

            if update_container "$ZIGBEE_CONTAINER" "$ZIGBEE_COMPOSE"; then
                log "Zigbee2MQTT updated"
            else
                log "ERROR: Zigbee2MQTT update failed"
            fi
            ;;

        Node-RED-Start|Node-RED-Stop|Node-RED-Restart)
            rm -f -- "$file"

            local action="${name#Node-RED-}"
            action="${action,,}"

            if run_logged docker "$action" "$NODE_RED_CONTAINER"; then
                log "Completed: $name"
            else
                log "ERROR: Failed: $name"
            fi
            ;;

        Node-RED-Update)
            rm -f -- "$file"

            if update_container "$NODE_RED_CONTAINER" "$NODE_RED_COMPOSE"; then
                log "Node-RED updated"
            else
                log "ERROR: Node-RED update failed"
            fi
            ;;

        Mosquitto-AddUser)
            if add_mosquitto_user "$file"; then
                log "Mosquitto user request completed"
            else
                log "ERROR: Mosquitto user request failed; resubmit after fixing configuration"
            fi

            rm -f -- "$file"
            ;;

        *)
            log "Ignoring unknown command: $name"
            ;;
    esac
}

mkdir -p "$ACTION_DIR"
touch "$LOG_FILE"

# Save the Docker host LAN IP for Node-RED.
save_host_ip

# Prevent two copies of the handler running simultaneously.
exec 9>/run/meek-action-handler.lock
flock -n 9 || exit 1

log "Action handler started"

while true; do
    shopt -s nullglob

    for file in "$ACTION_DIR"/*; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        process_file "$file"
    done

    sleep 2
done
