#!/bin/bash
#  bn - BungeeCord Server Script
#
# ### License ###
#
# Copyright 2013 Dabo Ross
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

### Configuration ###

# Name of the script - to have unique scripts
declare -r NAME="bungee"

# Server directory - where the minecraft server is stored
declare -r SERVER_DIR="${HOME}/${NAME}/server"

# XMX and XMS
declare -r XMX="256m"
declare -r XMS="128m"

# Backup location to backup to
declare -r BACKUP_LOCATION="file:///mnt/backup/$(whoami)-${NAME}"

# Folder to backup
declare -r STUFF_TO_BACKUP="${HOME}/${NAME}"

### Script Variables ###

# Set THIS to be this script.
declare -r SCRIPT="$([[ $0 = /* ]] && echo "$0" || echo "$PWD/${0#./}")"

# Storage vars
declare -r PID_FILE="${HOME}/${NAME}/.server-pid"
declare -r SCRIPT_DISABLED_FILE="${HOME}/${NAME}/.script-disabled"

### Script Functions ###

# Resumes the server session
resume() {
    if tmux has-session -t "${NAME}-server" &> /dev/null; then
        tmux attach -t "${NAME}-server"
    else
        echo "No server session exists"
    fi
}

# Gets the current log file
# stdout - log file
get_log() {
    local -r LOG_DIR="${HOME}/${NAME}/logs"
    mkdir -p "$LOG_DIR"
    local -r LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
    touch "$LOG_FILE"
    echo "$LOG_FILE"
}

# Adds the log prefix to the input, and redirects to log file.
# $1 - name of the log.
# stdin - stuff to log
log_stdin() {
    local -r LOG_NAME="$1"
    local -r PREFIX="$(echo "$(date '+%Y/%m/%d %H:%M') [${LOG_NAME}] " | sed -e 's/[\/&]/\\&/g')"
    sed -e "s/^/${PREFIX}/g" >> "$(get_log)"
}

# Logs something to the log file
# $@ - Lines to log
log() {
    echo "$(date +'%Y/%m/%d %H:%M') [${1}] ${@:2}" >> "$(get_log)"
}

# Tests if the server is running
# stdout - true if running
server_running() {
    [[ -a "$PID_FILE" ]] || return 1
    local -r SERVER_PID="$(cat ${PID_FILE})"
    kill -s 0 "$SERVER_PID" &> /dev/null && return 0 || return 1
}

# Runs the server script
server_script() {
    if script_enabled; then
        if server_running; then
            log "server_script" "Server running"
        else
            log "server_script" "Restarting server"
            kill_server
            start_server
        fi
    else
        log "server_script" "Script disabled"
    fi
}

# Migrates the server.log file to
log_migrate() {
    local -r SERVER_LOG="${SERVER_DIR}/proxy.log.0"
    local -r ARCHIVE_DIR="${HOME}/${NAME}/log-archives"
    mkdir -p "$ARCHIVE_DIR"
    local -r CURRENT_DATE="$(date +%Y-%m-%d)"
    local ARCHIVE_FILE="$ARCHIVE_DIR/${CURRENT_DATE}.log.gz"
    if [[ -a "$ARCHIVE_FILE" ]]; then
        log "log_migrate" "${ARCHIVE_FILE} already exists"
        local FILE_NUM='1'
        ARCHIVE_FILE="${ARCHIVE_DIR}/${CURRENT_DATE}-${FILE_NUM}.log.gz"
        while [[ -a "$ARCHIVE_FILE" ]]; do
            FILE_NUM="$((FILE_NUM + 1))"
            ARCHIVE_FILE="$ARCHIVE_DIR/${CURRENT_DATE}-${FILE_NUM}.log.gz"
        done
    fi
    log "log_migrate" "Migrating log to $ARCHIVE_FILE"
    gzip -c "$SERVER_LOG" > "$ARCHIVE_FILE"
    > "$SERVER_LOG"
}

# Sends keystrokes to the server session
tell_server() {
    if ! tmux has-session -t "${NAME}-server" &> /dev/null; then
        log "tell_server" "Can't tell server because server has no session"
        return
    fi
    log "tell_server" "Running $@"
    local -i NUM=0
    while [[ "$NUM" -lt 50 ]]; do
        NUM="$((NUM + 1))"
        tmux send-keys -t "${NAME}-server" "BSpace"
    done
    tmux send-keys -l -t "${NAME}-server" "$*" 2> /dev/null \
    || tmux send-keys -t "${NAME}-server" "$* "

    tmux send-keys -t "${NAME}-server" "Enter"
}

# Sends a short 5 second restart warning to the server
restart_warning_short() {
    log "restart_warning_short" "Starting"
    if server_running; then
        tell_server 'alert Warning! Bungee restarting in 5 seconds!'
        sleep 1
        if server_running; then
            tell_server 'alert Warning! Bungee restarting in 4 seconds!'
            sleep 1
            if server_running; then
                tell_server 'alert Warning! Bungee restarting in 3 seconds!'
                sleep 1
                if server_running; then
                    tell_server 'alert Warning! Bungee restarting in 2 seconds!'
                    sleep 1
                    if server_running; then
                        tell_server 'alert Warning! Bungee restarting in 1 second!'
                        sleep 1
                    fi
                fi
            fi
        fi
    fi
    log "restart_warning_short" "Done"
}

# Sends a long 5 minute restart warning to the server
restart_warning_long() {
    log "restart_warning_long" "Starting"
    if server_running; then
        tell_server 'alert Warning! Bungee restarting in 5 minutes!'
        sleep 1m
        if server_running; then
            tell_server 'alert Warning! Bungee restarting in 4 minutes!'
            sleep 1m
            if server_running; then
                tell_server 'alert Warning! Bungee restarting in 3 minutes!'
                sleep 1m
                if server_running; then
                    tell_server 'say Warning! Bungee restarting in 2 minutes!'
                    sleep 1m
                    if server_running; then
                        tell_server 'say Warning! Bungee restarting in 1 minute!'
                        sleep 1m
                    fi
                fi
            fi
        fi
    fi
    log "restart_warning_long" "Done"
}

# Backs up the server
backup() {
    log "backup" "Starting"
    duplicity --name "${NAME}" \
        --no-encryption \
        --full-if-older-than 1W \
        --log-fd 1 \
        "$STUFF_TO_BACKUP" "$BACKUP_LOCATION" 2>&1 | log_stdin "backup-duplicity-output"
    log "backup" "Done"
}

backup_script() {
    log "backup_script" "Starting"
    disable_script
    restart_warning_short
    stop_server
    backup
    start_server
    log "backup_script" "Done"
}

boot() {
    log "boot" "Running"
    start_server
}

script_enabled() {
    [[ -a "$SCRIPT_DISABLED_FILE" ]] && return 1 || return 0
}

disable_script() {
    if [[ -a "$SCRIPT_DISABLED_FILE" ]]; then
        log "disable_script" "Script already disabled"
    else
        log "disable_script" "Disabling script"
        mkdir -p "$(dirname ${SCRIPT_DISABLED_FILE})"
        touch "$SCRIPT_DISABLED_FILE"
    fi
}

enable_script() {
    if [[ -a "$SCRIPT_DISABLED_FILE" ]]; then
        log "enable_script" "Enabling script"
        rm -f "$SCRIPT_DISABLED_FILE"
    else
        log "enable_script" "Script already enabled"
    fi
}

# Kills the server
kill_server() {
    log "kill_server" "Starting"
    local -r SERVER_PID="$(cat ${PID_FILE})"
    log "kill_server" "Killing $SERVER_PID"
    kill -9 "$SERVER_PID" &> /dev/null
    if [[ -a "$SERVER_DIR/server.log.lck" ]]; then
        rm -f "$SERVER_DIR/server.log.lck"
    fi
    log "kill_server" "Done"
}

# Kills the server then starts it
kill_start() {
    log "kill_start" "Starting"
    kill_server
    while server_running; do
        sleep 1
    done
    start_server
    log "kill_start" "Done"
    resume
}

# Starts the server!
start_server() {
    if server_running; then
        log "start_server" "Server already running"
    else
        log "start_server" "Starting server"
        if [[ "$TMUX" ]]; then
            local -r TMUX_BAK="$TMUX"
            unset "TMUX"
        fi
        tmux new -ds "${NAME}-server" "'$SCRIPT' internal-start"
        if [[ "$TMUX_BAK" ]]; then
            TMUX="$TMUX_BAK"
        fi
        enable_script
    fi
}

# Internally used start function
internal_start() {
    local -r JAR_FILE="${HOME}/${NAME}/jars/BungeeCord.jar"
    log "internal_start" "Running with jar ${JAR_FILE}, xms ${XMS}, xmx ${XMX}"
    cd "$SERVER_DIR"
    local -r SERVER_PID="$$"
    echo "$SERVER_PID" > "$PID_FILE"
    log "record-start" "Starting '$@' with pid $SERVER_PID"
    exec java "-Xms${XMS}" "-Xmx${XMX}" -Xincgc -XX:+CMSClassUnloadingEnabled -XX:MaxPermSize=64m -jar "$JAR_FILE" --log-strip-color
}

# Stops the server
stop_server() {
    if server_running; then
        log "stop_server" "Stopping server"
        tell_server "end"
        timeout="$((120 + $(date '+%s')))"
        while server_running; do
            if [[ "$(date '+%s')" -gt "$timeout" ]]; then
                kill_server
            fi
            sleep 1s
        done
    else
        log "stop_server" "Server not running"
    fi
}

# Stops the server, then starts it
stop_start() {
    log "stop_start" "Starting"
    disable_script
    restart_warning_short
    stop_server
    start_server
    log "stop_start" "Done"
}

# Views the log file with 'tail'
view_log() {
    local LENGTH="$1"
    if [[ -z "$LENGTH" ]]; then
        LENGTH="100"
    fi
    tail -n "$LENGTH" "$(get_log)"
}

### Commmand line function

cmd_help() {
    echo " ---- bn - ${NAME} ----"
    echo " status         - Gives the server's status"
    echo " resume         - Resumes the server session"
    echo " start-server   - Starts the server"
    echo " stop-server    - Stops the server"
    echo " stop-start     - Stops the server, then starts it"
    echo " kill-server    - Kills the server"
    echo " kill-start     - Kills the server then starts it"
    echo " view-log       - Views the script log"
    echo " backup-script  - Stops the server, backs up, and starts the server"
    echo " backup         - Backs up the server"
    echo " check-script   - Starts it if it isn't online"
    echo " script-enabled - Checks if the check-script is enabled"
    echo " enable-script  - Enables the check-script"
    echo " disable-script - Disable the check-script"
    if [[ "$1" == "--internal" ]]; then
        echo " ---- Internally used / debug commands ----"
        echo " warning-long         - Restart warning long"
        echo " warning-short        - Restart warning short"
        echo " log-migrate          - Migrates the server log"
        echo " boot                 - Script to run at boot"
        echo " internal-start       - Internal start script"
        echo " pre-start-actions    - Runs server pre-start actions"
        echo " tell-server          - Sends keystrokes to the server session"
     fi
}

main() {
    local -r FUNCTION="$1"
    local -r P="[${NAME}]"
    case "$FUNCTION" in
        resume)
            resume ;;
        status)
            if server_running; then
                echo "Server $NAME running!"
                return 0
            else
                echo "Server $NAME not running."
                return 1
            fi ;;
        check-script)
            server_script ;;
        log-migrate)
            log_migrate ;;
        warning-short)
            restart_warning_short ;;
        warning-long)
            restart_warning_long ;;
        backup)
            backup ;;
        backup-script)
            backup_script ;;
        boot)
            boot ;;
        script-enabled)
            if script_enabled; then
                echo "Script is enabled"
                return 0
            else
                echo "Script is disabled"
                return 1
            fi ;;
        enable-script)
            enable_script ;;
        disable-script)
            disable_script ;;
        kill-server)
            kill_server ;;
        persistent-start)
            persistent-start ;;
        kill-start)
            kill_start ;;
        start-server)
            start_server ;;
        spigot-restart)
            spigot_restart ;;
        internal-start)
            internal_start ;;
        stop-server)
            stop_server ;;
        stop-start)
            stop_start ;;
        view-log)
            view_log ;;
        tell-server)
            tell_server "${@:2}" ;;
        help)
            cmd_help "${@:2}" ;;
        ?*)
            echo "Unknown argument '${1}'"
            cmd_help ;;
        *)
            cmd_help ;;
    esac
}
main "$@"
