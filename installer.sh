#!/bin/bash
############################################################################
# Copyright (C) 2026 thavanish
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License only.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# GNU General Public License v2 — All Rights Reserved
############################################################################

# don't use set -e — arithmetic like (( x++ )) returns 1 on zero and kills the script
set -uo pipefail

readonly VERSION="3.2.0-Stable"
readonly LOG="/tmp/airlink.log"
readonly PANEL_REPO="${PANEL_REPO:-https://github.com/Mitul636/panel.git}"
readonly DAEMON_REPO="${DAEMON_REPO:-https://github.com/Mitul636/daemon.git}"
readonly DAEMON_RELEASE_API="https://api.github.com/repos/Mitul636/daemon/releases/latest"

PNPM_REGISTRY="https://registry.npmjs.org"
PNPM="pnpm"
PNPM_STORE="/root/.pnpm-store"

declare -a ADDONS=(
    "Modrinth|https://github.com/airlinklabs/addons.git|modrinth|modrinth"
    "Parachute|https://github.com/airlinklabs/addons.git|parachute|parachute"
)

# =============================================================================
# ANSI
# =============================================================================
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
REV="${ESC}[7m"
C_GREEN="${ESC}[92m"
C_RED="${ESC}[91m"
C_GRAY="${ESC}[90m"
C_CYAN="${ESC}[96m"
C_YELLOW="${ESC}[93m"
HIDE_CURSOR="${ESC}[?25l"
SHOW_CURSOR="${ESC}[?25h"
CLEAR_SCREEN="${ESC}[2J${ESC}[H"

move_to() { printf "${ESC}[%d;%dH" "$1" "$2"; }
clr_line() { printf "${ESC}[2K"; }

# =============================================================================
# Logging & Status Helpers
# =============================================================================
log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
info() { log "INFO: $*"; }
ok()   { log "OK: $*"; }
warn() { log "WARN: $*"; }

die() {
    printf "%b" "${SHOW_CURSOR}" 2>/dev/null || true
    tput rmcup 2>/dev/null || printf "%b" "${CLEAR_SCREEN}" 2>/dev/null || true
    stty echo 2>/dev/null || true
    printf "\n${BOLD}  error:${RESET} %s\n\n" "$*" >&2
    log "ERROR: $*"
    exit 1
}

parse_status_line() {
    local line="${1:-}"
    line=$(echo "$line" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || echo "$line")
    line=$(echo "$line" | tr -d '\r\n' | xargs 2>/dev/null || echo "$line")
    echo "$line"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This installer must be run as root (use sudo)."
    fi
}

generate_key() {
    openssl rand -hex 16 2>/dev/null || echo "airlink_key_$(date +%s)"
}

# =============================================================================
# Args
# =============================================================================
ARG_MODE=""
ARG_NAME=""
ARG_PORT=""
ARG_PANEL_ADDR=""
ARG_DAEMON_PORT=""
ARG_DAEMON_KEY=""
ARG_ADDONS=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --panel-only)  ARG_MODE="panel";        shift ;;
            --daemon-only) ARG_MODE="daemon";       shift ;;
            --both)        ARG_MODE="both";         shift ;;
            --name)        ARG_NAME="${2:-}";       shift 2 ;;
            --port)        ARG_PORT="${2:-}";       shift 2 ;;
            --panel-addr)  ARG_PANEL_ADDR="${2:-}"; shift 2 ;;
            --daemon-port) ARG_DAEMON_PORT="${2:-}"; shift 2 ;;
            --daemon-key)  ARG_DAEMON_KEY="${2:-}";  shift 2 ;;
            --addons)      ARG_ADDONS="${2:-}";     shift 2 ;;
            *) log "Unknown arg ignored: $1"; shift ;;
        esac
    done
}

noninteractive() {
    [[ -n "${ARG_MODE}${ARG_NAME}${ARG_PORT}${ARG_PANEL_ADDR}${ARG_DAEMON_PORT}${ARG_DAEMON_KEY}${ARG_ADDONS}" ]]
}

# =============================================================================
# Non-interactive spinner
# =============================================================================
NI_STEP=0
NI_TOTAL=0
_NI_SPIN_CHARS=('-' '\' '|' '/')

ni_header() {
    printf "\n"
    printf "    _    ___ ____  _     ___ _   _ _  __\n"
    printf "   / \\  |_ _|  _ \\| |   |_ _| \\ | | |/ /\n"
    printf "  / _ \\  | || |_) | |    | ||  \\| | ' / \n"
    printf " / ___ \\ | ||  _ <| |___ | || |\\  | . \\ \n"
    printf "/_/   \\_\\___|_| \\_\\_____|___|_| \\_|_|\\_\\\\\n"
    printf "\n"
    printf "  ${BOLD}Airlink Installer${RESET} ${C_GRAY}v${VERSION}${RESET}  ${C_GRAY}%s${RESET}\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"
}

ni_start() { NI_TOTAL="$1"; NI_STEP=0; }

ni_run() {
    local label="$1"; shift
    NI_STEP=$(( NI_STEP + 1 ))
    local fi=0
    local outfile; outfile=$(mktemp /tmp/al-step-XXXXXX)
    local out_lines=6

    "$@" >"$outfile" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${C_GRAY}[%02d/%02d]${RESET} %-42s ${_NI_SPIN_CHARS[$fi]}" "$NI_STEP" "$NI_TOTAL" "$label"
        fi=$(( (fi + 1) % 4 ))

        local last_line raw_status
        last_line=$(grep -v '^[[:space:]]*$' "$outfile" 2>/dev/null | tail -1 || true)
        raw_status=$(parse_status_line "$last_line")
        if [[ -n "$raw_status" ]]; then
            printf "\n    ${C_YELLOW}status:${RESET} ${C_GRAY}%-68.68s${RESET}" "$raw_status"
        else
            printf "\n%76s" ""
        fi

        local li=0
        while IFS= read -r line; do
            printf "\n    ${C_GRAY}%-72.72s${RESET}" "$line"
            li=$(( li + 1 ))
        done < <(tail -n${out_lines} "$outfile" 2>/dev/null)
        while [[ $li -lt $out_lines ]]; do
            printf "\n%76s" ""
            li=$(( li + 1 ))
        done
        printf "\033[%dA\r" $(( out_lines + 1 ))
        sleep 0.1
    done

    wait "$pid"
    local status=$?

    local li
    printf "\n%76s" ""
    for (( li = 0; li < out_lines; li++ )); do printf "\n%76s" ""; done
    printf "\033[%dA\r" $(( out_lines + 1 ))

    if [[ $status -eq 0 ]]; then
        printf "\r  ${C_GRAY}[%02d/%02d]${RESET} %-42s ${C_GREEN}done${RESET}\n" "$NI_STEP" "$NI_TOTAL" "$label"
        log "OK: $label"
    else
        printf "\r  ${C_GRAY}[%02d/%02d]${RESET} %-42s ${C_RED}FAIL${RESET}\n" "$NI_STEP" "$NI_TOTAL" "$label"
        local err_tail; err_tail=$(tail -n20 "$outfile" 2>/dev/null || true)
        rm -f "$outfile"
        log "ERROR: $label failed"
        printf "\n${BOLD}  failed:${RESET} %s\n\n%s\n\n" "$label" "$err_tail"
        exit 1
    fi

    rm -f "$outfile"
}

# =============================================================================
# TUI engine
# =============================================================================
TERM_ROWS=24
TERM_COLS=80
_TUI_ACTIVE=0

tui_measure() {
    TERM_ROWS=$(tput lines  2>/dev/null || echo 24)
    TERM_COLS=$(tput cols   2>/dev/null || echo 80)
    [[ $TERM_ROWS -lt 18 ]] && TERM_ROWS=18
    [[ $TERM_COLS -lt 60 ]] && TERM_COLS=60
}

tui_cleanup() {
    if [[ $_TUI_ACTIVE -eq 1 ]]; then
        _TUI_ACTIVE=0
        printf "%b" "${SHOW_CURSOR}"
        tput rmcup 2>/dev/null || printf "%b" "${CLEAR_SCREEN}"
        stty echo 2>/dev/null || true
    fi
}

tui_init() {
    tui_measure
    tput smcup 2>/dev/null || printf "%b" "${CLEAR_SCREEN}"
    printf "%b" "${HIDE_CURSOR}"
    stty -echo 2>/dev/null || true
    _TUI_ACTIVE=1
    trap 'tui_cleanup; exit 0' EXIT INT TERM
}

tui_box() {
    local row=$1 col=$2 w=$3 h=$4 title="${5:-}"
    local inner=$(( w - 2 ))

    move_to "$row" "$col"
    if [[ -n "$title" ]]; then
        local tlen=${#title}
        if [[ $(( tlen + 4 )) -gt $inner ]]; then
            tlen=$(( inner - 4 ))
            title="${title:0:$tlen}"
        fi
        local dashes=$(( inner - tlen - 2 ))
        local left_pad=$(( dashes / 2 ))
        local right_pad=$(( dashes - left_pad ))
        printf "+"
        [[ $left_pad -gt 0 ]] && printf '%*s' "$left_pad" '' | tr ' ' '-'
        printf " ${BOLD}%s${RESET} " "$title"
        [[ $right_pad -gt 0 ]] && printf '%*s' "$right_pad" '' | tr ' ' '-'
        printf "+"
    else
        printf "+"; printf '%*s' "$inner" '' | tr ' ' '-'; printf "+"
    fi

    local r
    for (( r = 1; r < h - 1; r++ )); do
        move_to $(( row + r )) "$col"
        printf "|%*s|" "$inner" ''
    done

    move_to $(( row + h - 1 )) "$col"
    printf "+"; printf '%*s' "$inner" '' | tr ' ' '-'; printf "+"
}

tui_hline() {
    local row=$1 col=$2 w=$3
    move_to "$row" "$col"
    printf "+"; printf '%*s' $(( w - 2 )) '' | tr ' ' '-'; printf "+"
}

_KEY=""
read_key() {
    local k1 k2 k3
    IFS= read -rsn1 k1
    if [[ "$k1" == $'\x1b' ]]; then
        IFS= read -rsn1 -t 0.05 k2 2>/dev/null || k2=""
        if [[ "$k2" == "[" ]]; then
            IFS= read -rsn1 -t 0.05 k3 2>/dev/null || k3=""
            case "$k3" in
                'A') _KEY="UP"    ;;
                'B') _KEY="DOWN"  ;;
                'C') _KEY="RIGHT" ;;
                'D') _KEY="LEFT"  ;;
                *)   _KEY="ESC"   ;;
            esac
        else
            _KEY="ESC"
        fi
    elif [[ "$k1" == "" || "$k1" == $'\n' || "$k1" == $'\r' ]]; then
        _KEY="ENTER"
    elif [[ "$k1" == $'\x7f' || "$k1" == $'\b' ]]; then
        _KEY="BACKSPACE"
    elif [[ "$k1" == " " ]]; then
        _KEY="SPACE"
    else
        _KEY="$k1"
    fi
}

_INSTALLING=0

_BANNER=(
    "    _    ___ ____  _     ___ _   _ _  __"
    "   / \\  |_ _|  _ \\| |   |_ _| \\ | | |/ /"
    "  / _ \\  | || |_) | |    | ||  \\| | ' / "
    " / ___ \\ | ||  _ <| |___ | || |\\  | . \\ "
    "/_/   \\_\\___|_| \\_\\_____|___|_| \\_|_|\\_\\\\"
    ""
    "  GNU General Public License v2 -- All Rights Reserved"
)

draw_banner() {
    local start_row=$1
    local banner_w=${#_BANNER[0]}
    local bx=$(( (TERM_COLS - banner_w) / 2 ))
    [[ $bx -lt 1 ]] && bx=1
    local bi
    for (( bi = 0; bi < ${#_BANNER[@]}; bi++ )); do
        move_to $(( start_row + bi )) "$bx"
        if [[ $bi -ge 6 ]]; then
            printf "${DIM}${C_GRAY}%s${RESET}" "${_BANNER[$bi]}"
        else
            printf "${DIM}%s${RESET}" "${_BANNER[$bi]}"
        fi
    done
}

# =============================================================================
# Main menu
# =============================================================================
TUI_RESULT=0

tui_menu() {
    local title="$1"; shift
    local -a items=("$@")
    local count=${#items[@]}
    local selected=0

    tui_measure

    local max_item_len=0
    local i
    for (( i = 0; i < count; i++ )); do
        local iw=${#items[$i]}
        [[ $iw -gt $max_item_len ]] && max_item_len=$iw
    done

    local min_needed=$(( max_item_len + 10 ))
    local preferred=$(( TERM_COLS * 60 / 100 ))
    local box_w=$preferred
    [[ $box_w -lt $min_needed ]] && box_w=$min_needed
    [[ $box_w -lt 60 ]]         && box_w=60
    [[ $box_w -gt $(( TERM_COLS - 4 )) ]] && box_w=$(( TERM_COLS - 4 ))

    local banner_h=7
    local gap=1
    local box_h=$(( count + 6 ))
    local total_h=$(( banner_h + gap + box_h ))

    local box_r=$(( (TERM_ROWS - total_h) / 2 + banner_h + gap ))
    [[ $box_r -lt $(( banner_h + gap + 1 )) ]] && box_r=$(( banner_h + gap + 1 ))
    local box_c=$(( (TERM_COLS - box_w) / 2 ))
    [[ $box_c -lt 1 ]] && box_c=1

    local inner=$(( box_w - 2 ))

    while true; do
        printf "%b" "${CLEAR_SCREEN}"
        draw_banner $(( box_r - banner_h - gap ))
        tui_box "$box_r" "$box_c" "$box_w" "$box_h" "$title"

        move_to $(( box_r + 1 )) $(( box_c + 2 ))
        printf "${DIM}%-${inner}s${RESET}" "arrows/jk move  enter select  0-9 hotkey  esc/q quit"

        tui_hline $(( box_r + 2 )) "$box_c" "$box_w"

        for (( i = 0; i < count; i++ )); do
            move_to $(( box_r + 3 + i )) $(( box_c + 1 ))
            local label=" [${i}] ${items[$i]}"
            if [[ $i -eq $selected ]]; then
                printf "${REV}%-${inner}s${RESET}" "$label"
            else
                printf "%-${inner}s" "$label"
            fi
        done

        move_to $(( box_r + box_h - 2 )) $(( box_c + 2 ))
        printf "${DIM}v${VERSION}${RESET}"

        read_key
        case "$_KEY" in
            UP|k)   [[ $selected -gt 0 ]]               && selected=$(( selected - 1 )) ;;
            DOWN|j) [[ $selected -lt $(( count-1 )) ]] && selected=$(( selected + 1 )) ;;
            ENTER)
                TUI_RESULT=$selected
                return 0
                ;;
            ESC|q|Q)
                if [[ $_INSTALLING -eq 0 ]]; then
                    TUI_RESULT=-1
                    return 1
                fi
                ;;
            [0-9])
                if [[ "${_KEY}" -lt $count ]]; then
                    TUI_RESULT="${_KEY}"
                    return 0
                fi
                ;;
        esac
    done
}

# =============================================================================
# Multi-select checklist
# =============================================================================
TUI_MULTI=""

tui_checklist() {
    local title="$1"; shift
    local -a items=("$@")
    local count=${#items[@]}
    local cursor=0
    declare -a checked
    for (( i = 0; i < count; i++ )); do checked[$i]=0; done

    tui_measure

    local max_item_len=0
    local i
    for (( i = 0; i < count; i++ )); do
        local iw=${#items[$i]}
        [[ $iw -gt $max_item_len ]] && max_item_len=$iw
    done
    local box_w=$(( max_item_len + 14 ))
    [[ $box_w -lt 50 ]] && box_w=50
    [[ $box_w -gt $(( TERM_COLS - 4 )) ]] && box_w=$(( TERM_COLS - 4 ))

    local box_h=$(( count + 6 ))
    local box_r=$(( (TERM_ROWS - box_h) / 2 ))
    local box_c=$(( (TERM_COLS - box_w) / 2 ))
    [[ $box_r -lt 1 ]] && box_r=1
    [[ $box_c -lt 1 ]] && box_c=1
    local inner=$(( box_w - 2 ))

    while true; do
        printf "%b" "${CLEAR_SCREEN}"
        tui_box "$box_r" "$box_c" "$box_w" "$box_h" "$title"

        move_to $(( box_r + 1 )) $(( box_c + 2 ))
        printf "${DIM}%-${inner}s${RESET}" "space/num toggle  enter confirm  q skip"

        tui_hline $(( box_r + 2 )) "$box_c" "$box_w"

        for (( i = 0; i < count; i++ )); do
            move_to $(( box_r + 3 + i )) $(( box_c + 1 ))
            local num=$(( i + 1 ))
            local mark="[ ]"
            [[ ${checked[$i]} -eq 1 ]] && mark="[x]"
            local label=" [${num}] ${mark} ${items[$i]}"
            if [[ $i -eq $cursor ]]; then
                printf "${REV}%-${inner}s${RESET}" "$label"
            else
                printf "%-${inner}s" "$label"
            fi
        done

        read_key
        case "$_KEY" in
            UP|k)   [[ $cursor -gt 0 ]]               && cursor=$(( cursor - 1 )) ;;
            DOWN|j) [[ $cursor -lt $(( count-1 )) ]] && cursor=$(( cursor + 1 )) ;;
            SPACE)
                if [[ ${checked[$cursor]} -eq 1 ]]; then checked[$cursor]=0; else checked[$cursor]=1; fi
                ;;
            [0-9])
                local np="${_KEY}"
                if [[ $np -lt $count ]]; then
                    if [[ ${checked[$np]} -eq 1 ]]; then checked[$np]=0; else checked[$np]=1; fi
                    cursor=$np
                fi
                ;;
            ENTER)
                TUI_MULTI=""
                for (( i = 0; i < count; i++ )); do
                    [[ ${checked[$i]} -eq 1 ]] && TUI_MULTI="${TUI_MULTI} $i"
                done
                TUI_MULTI="${TUI_MULTI# }"
                return 0
                ;;
            ESC|q|Q)
                if [[ $_INSTALLING -eq 0 ]]; then
                    TUI_MULTI=""
                    return 1
                fi
                ;;
        esac
    done
}

# =============================================================================
# Text input
# =============================================================================
TUI_INPUT=""

tui_input() {
    local prompt="$1"
    local default="${2:-}"
    local value="$default"
    local error_msg="${3:-}"

    tui_measure

    local box_w=$(( TERM_COLS / 2 + 10 ))
    [[ $box_w -lt 50 ]] && box_w=50
    [[ $box_w -gt $(( TERM_COLS - 4 )) ]] && box_w=$(( TERM_COLS - 4 ))

    local box_h=9
    [[ -n "$error_msg" ]] && box_h=10
    local box_r=$(( (TERM_ROWS - box_h) / 2 ))
    local box_c=$(( (TERM_COLS - box_w) / 2 ))
    [[ $box_r -lt 1 ]] && box_r=1
    [[ $box_c -lt 1 ]] && box_c=1
    local inner=$(( box_w - 2 ))
    local field_w=$(( box_w - 8 ))

    stty echo 2>/dev/null || true

    while true; do
        printf "%b" "${CLEAR_SCREEN}"
        tui_box "$box_r" "$box_c" "$box_w" "$box_h" "Input"

        move_to $(( box_r + 1 )) $(( box_c + 3 ))
        printf "%-${inner}s" "$prompt"

        if [[ -n "$error_msg" ]]; then
            move_to $(( box_r + 2 )) $(( box_c + 3 ))
            printf "${C_RED}%-${inner}s${RESET}" "$error_msg"
        fi

        local field_row=$(( box_r + 4 ))
        move_to "$field_row" $(( box_c + 3 ))
        printf "+%s+" "$(printf '%*s' "$field_w" '' | tr ' ' '-')"

        move_to $(( field_row + 1 )) $(( box_c + 3 ))
        local display="${value}"
        if [[ ${#display} -gt $(( field_w - 2 )) ]]; then
            display="${display: -$(( field_w - 2 ))}"
        fi
        printf "| %-$(( field_w - 2 ))s |" "$display"

        move_to $(( field_row + 2 )) $(( box_c + 3 ))
        printf "+%s+" "$(printf '%*s' "$field_w" '' | tr ' ' '-')"

        move_to $(( box_r + box_h - 2 )) $(( box_c + 3 ))
        printf "${DIM}%-${inner}s${RESET}" "esc = restore default   enter = confirm"

        local cursor_x=$(( box_c + 5 + ${#value} ))
        if [[ $cursor_x -gt $(( box_c + 3 + field_w - 1 )) ]]; then
            cursor_x=$(( box_c + 3 + field_w - 1 ))
        fi
        move_to $(( field_row + 1 )) "$cursor_x"
        printf "%b" "${SHOW_CURSOR}"

        read_key
        printf "%b" "${HIDE_CURSOR}"
        case "$_KEY" in
            ENTER)     TUI_INPUT="$value"; stty -echo 2>/dev/null || true; return 0 ;;
            BACKSPACE) [[ ${#value} -gt 0 ]] && value="${value%?}" ;;
            ESC)       value="$default" ;;
            UP|DOWN|LEFT|RIGHT) : ;;
            *)
                if [[ ${#_KEY} -eq 1 && "$_KEY" =~ [[:print:]] ]]; then
                    value="${value}${_KEY}"
                fi
                ;;
        esac
    done
}

# =============================================================================
# Confirm dialog
# =============================================================================
tui_confirm() {
    local prompt="$1"
    local selected=0

    tui_measure

    local box_w=52
    [[ $box_w -gt $(( TERM_COLS - 4 )) ]] && box_w=$(( TERM_COLS - 4 ))
    local box_h=7
    local box_r=$(( (TERM_ROWS - box_h) / 2 ))
    local box_c=$(( (TERM_COLS - box_w) / 2 ))
    [[ $box_r -lt 1 ]] && box_r=1
    [[ $box_c -lt 1 ]] && box_c=1
    local inner=$(( box_w - 2 ))

    while true; do
        printf "%b" "${CLEAR_SCREEN}"
        tui_box "$box_r" "$box_c" "$box_w" "$box_h" "Confirm"

        move_to $(( box_r + 2 )) $(( box_c + 3 ))
        printf "%-${inner}s" "$prompt"

        move_to $(( box_r + 4 )) $(( box_c + 10 ))
        if [[ $selected -eq 0 ]]; then
            printf "${REV}  yes  ${RESET}        no  "
        else
            printf "  yes         ${REV}  no  ${RESET}"
        fi

        move_to $(( box_r + 6 )) $(( box_c + 3 ))
        printf "${DIM}%-${inner}s${RESET}" "left/right or h/l  y/n  enter confirm"

        read_key
        case "$_KEY" in
            LEFT|h|H)  selected=0 ;;
            RIGHT|l|L) selected=1 ;;
            y|Y)       return 0 ;;
            n|N)       return 1 ;;
            ENTER)     return $selected ;;
            q|Q|ESC)   return 1 ;;
        esac
    done
}

# =============================================================================
# Full-screen progress view
# =============================================================================
PROGRESS_TASKS=()
PROGRESS_CURRENT=0

tui_progress_init() { PROGRESS_TASKS=("$@"); PROGRESS_CURRENT=0; }

_PBOX_R=0; _PBOX_C=0; _PBOX_W=0; _PBOX_H=0

tui_progress_draw() {
    local total=${#PROGRESS_TASKS[@]}
    printf "%b" "${CLEAR_SCREEN}"
    tui_measure

    local box_w=$(( TERM_COLS - 8 ))
    [[ $box_w -lt 54 ]] && box_w=54
    [[ $box_w -gt 90 ]] && box_w=90

    local box_h=$(( total + 9 ))
    local box_r=$(( (TERM_ROWS - box_h) / 2 ))
    [[ $box_r -lt 1 ]] && box_r=1
    local box_c=$(( (TERM_COLS - box_w) / 2 ))
    [[ $box_c -lt 1 ]] && box_c=1
    local inner=$(( box_w - 2 ))
    local bar_w=$(( box_w - 10 ))

    tui_box "$box_r" "$box_c" "$box_w" "$box_h" "Installing"

    move_to $(( box_r + 1 )) $(( box_c + 3 ))
    printf "${DIM}Airlink v${VERSION}${RESET}"
    tui_hline $(( box_r + 2 )) "$box_c" "$box_w"

    local i
    for (( i = 0; i < total; i++ )); do
        move_to $(( box_r + 3 + i )) $(( box_c + 3 ))
        if [[ $i -lt $PROGRESS_CURRENT ]]; then
            printf "${C_GREEN}[+]${RESET} ${DIM}%-$(( inner - 6 ))s${RESET}" "${PROGRESS_TASKS[$i]}"
        elif [[ $i -eq $PROGRESS_CURRENT ]]; then
            printf "${C_CYAN}[>]${RESET} ${BOLD}%-$(( inner - 6 ))s${RESET}" "${PROGRESS_TASKS[$i]}"
        else
            printf "${DIM}[ ] %-$(( inner - 6 ))s${RESET}" "${PROGRESS_TASKS[$i]}"
        fi
    done

    tui_hline $(( box_r + box_h - 4 )) "$box_c" "$box_w"

    local pct=0
    [[ $total -gt 0 ]] && pct=$(( PROGRESS_CURRENT * 100 / total ))
    local filled=$(( pct * bar_w / 100 ))
    local empty=$(( bar_w - filled ))

    move_to $(( box_r + box_h - 3 )) $(( box_c + 3 ))
    printf "[%s%s] %3d%%" \
        "$(printf '%*s' "$filled" '' | tr ' ' '#')" \
        "$(printf '%*s' "$empty"  '' | tr ' ' ' ')" \
        "$pct"

    _PBOX_R=$box_r; _PBOX_C=$box_c; _PBOX_W=$box_w; _PBOX_H=$box_h
}

tui_progress_step() {
    tui_progress_draw

    local spinner_row=$(( _PBOX_R + 3 + PROGRESS_CURRENT ))
    local spinner_col=$(( _PBOX_C + _PBOX_W - 4 ))
    local out_row=$(( _PBOX_R + _PBOX_H + 1 ))
    local out_lines=6
    local out_w=$(( _PBOX_W - 4 ))
    [[ $out_w -lt 20 ]] && out_w=20

    local outfile; outfile=$(mktemp /tmp/al-step-XXXXXX)

    "$@" >"$outfile" 2>&1 &
    local pid=$!
    local fi=0

    while kill -0 "$pid" 2>/dev/null; do
        move_to "$spinner_row" "$spinner_col"
        printf "${C_CYAN}%s${RESET}" "${_NI_SPIN_CHARS[$fi]}"
        fi=$(( (fi + 1) % 4 ))

        local last_line raw_status
        last_line=$(grep -v '^[[:space:]]*$' "$outfile" 2>/dev/null | tail -1 || true)
        raw_status=$(parse_status_line "$last_line")
        if [[ $(( out_row - 1 )) -lt $TERM_ROWS && -n "$raw_status" ]]; then
            move_to $(( out_row - 1 )) $(( _PBOX_C + 2 ))
            printf "${C_YELLOW}status:${RESET} ${DIM}%-$(( out_w - 8 )).$(( out_w - 8 ))s${RESET}" "$raw_status"
        fi

        local li=0
        while IFS= read -r line; do
            if [[ $(( out_row + li )) -lt $TERM_ROWS ]]; then
                move_to $(( out_row + li )) $(( _PBOX_C + 2 ))
                printf "${DIM}%-${out_w}.${out_w}s${RESET}" "$line"
            fi
            li=$(( li + 1 ))
        done < <(tail -n${out_lines} "$outfile" 2>/dev/null)
        while [[ $li -lt $out_lines ]]; do
            if [[ $(( out_row + li )) -lt $TERM_ROWS ]]; then
                move_to $(( out_row + li )) $(( _PBOX_C + 2 ))
                printf "%-${out_w}s" ""
            fi
            li=$(( li + 1 ))
        done

        sleep 0.1
    done

    wait "$pid"
    local status=$?

    if [[ $(( out_row - 1 )) -lt $TERM_ROWS ]]; then
        move_to $(( out_row - 1 )) $(( _PBOX_C + 2 ))
        printf "%-${out_w}s" ""
    fi
    local li
    for (( li = 0; li < out_lines; li++ )); do
        if [[ $(( out_row + li )) -lt $TERM_ROWS ]]; then
            move_to $(( out_row + li )) $(( _PBOX_C + 2 ))
            printf "%-${out_w}s" ""
        fi
    done

    move_to "$spinner_row" "$spinner_col"
    if [[ $status -eq 0 ]]; then
        printf "    "
        log "OK: ${PROGRESS_TASKS[$PROGRESS_CURRENT]}"
        PROGRESS_CURRENT=$(( PROGRESS_CURRENT + 1 ))
    else
        local err_out; err_out=$(tail -n20 "$outfile" 2>/dev/null || true)
        rm -f "$outfile"
        log "ERROR: ${PROGRESS_TASKS[$PROGRESS_CURRENT]}"
        tui_cleanup
        printf "\n${BOLD}  Step failed:${RESET} %s\n\n%s\n\n" "${PROGRESS_TASKS[$PROGRESS_CURRENT]}" "$err_out"
        exit 1
    fi

    rm -f "$outfile"
    sleep 0.05
}

tui_progress_finish() {
    PROGRESS_CURRENT=${#PROGRESS_TASKS[@]}
    tui_progress_draw
    sleep 1
}

# =============================================================================
# OS detection & Dependencies
# =============================================================================
OS="" VER="" FAM="" PKG=""

detect_os() {
    [[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release missing"
    OS=$(grep '^ID='          /etc/os-release | cut -d= -f2 | tr -d '"')
    VER=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

    case "$OS" in
        ubuntu|debian|linuxmint|pop|raspbian) FAM="debian"; PKG="apt" ;;
        fedora|centos|rhel|rocky|almalinux|ol)
            FAM="redhat"
            if command -v dnf &>/dev/null; then PKG="dnf"; else PKG="yum"; fi
            ;;
        arch|manjaro|endeavouros) FAM="arch"; PKG="pacman" ;;
        alpine) FAM="alpine"; PKG="apk" ;;
        *) die "Unsupported OS: $OS. Supported: Ubuntu/Debian/Fedora/RHEL/Arch/Alpine" ;;
    esac
    log "Detected OS: $OS $VER ($FAM)"
}

pkg_install() {
    case "$PKG" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
            ;;
        dnf|yum) $PKG install -y -q "$@" ;;
        pacman)  pacman -Sy --noconfirm --needed "$@" ;;
        apk)     apk add --no-cache -q "$@" ;;
    esac
}

ensure_deps() {
    local deps=(curl wget git openssl unzip tar)
    local missing=()
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || missing+=("$d")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Installing missing: ${missing[*]}"
        pkg_install "${missing[@]}"
    fi
    for d in "${deps[@]}"; do
        command -v "$d" &>/dev/null || die "Failed to install dependency: $d"
    done
}

# =============================================================================
# Node.js & Package Managers
# =============================================================================
get_latest_node_lts() {
    local idx
    idx=$(curl -fsSL --max-time 15 "https://nodejs.org/dist/index.json" 2>/dev/null) || {
        log "WARN: can't fetch node index, defaulting to 22"
        echo "22"; return
    }
    local lts_ver
    lts_ver=$(echo "$idx" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for r in data:
        if r.get('lts') and r['lts'] is not False:
            print(r['version'].lstrip('v').split('.')[0])
            break
except Exception:
    pass
" 2>/dev/null) || true

    if [[ -z "$lts_ver" || ! "$lts_ver" =~ ^[0-9]+$ ]]; then
        log "WARN: can't parse LTS version, defaulting to 22"
        echo "22"
    else
        echo "$lts_ver"
    fi
}

select_npm_registry() {
    local geo
    geo=$(curl -fsSL --max-time 8 "http://ip-api.com/json/?fields=continentCode,countryCode" 2>/dev/null || echo "")

    local continent
    continent=$(echo "$geo" | grep -o '"continentCode":"[^"]*"' | cut -d'"' -f4 || echo "")

    case "$continent" in
        AS) PNPM_REGISTRY="https://registry.npmmirror.com"; log "Registry: npmmirror.com (Asia)" ;;
        *)  PNPM_REGISTRY="https://registry.npmjs.org";     log "Registry: npmjs.org (default)"  ;;
    esac

    if ! curl -fsSL --max-time 6 "${PNPM_REGISTRY}/npm" -o /dev/null 2>/dev/null; then
        log "WARN: $PNPM_REGISTRY unreachable, falling back to npmjs.org"
        PNPM_REGISTRY="https://registry.npmjs.org"
    fi
}

setup_node() {
    local desired_major
    desired_major=$(get_latest_node_lts)
    log "Latest Node LTS: $desired_major"

    local current_major="0"
    if command -v node &>/dev/null; then
        current_major=$(node -e "console.log(process.versions.node.split('.')[0])" 2>/dev/null || echo "0")
    fi

    if [[ "$current_major" -ge 20 ]]; then
        log "Node.js v$current_major is already installed and compatible."
    else
        log "Installing Node.js v${desired_major}.x..."
        case "$FAM" in
            debian)
                curl -fsSL "https://deb.nodesource.com/setup_${desired_major}.x" | bash -
                pkg_install nodejs
                ;;
            redhat)
                curl -fsSL "https://rpm.nodesource.com/setup_${desired_major}.x" | bash -
                pkg_install nodejs
                ;;
            arch|alpine)
                pkg_install nodejs npm
                ;;
        esac
    fi
}

setup_pnpm() {
    if ! command -v pnpm &>/dev/null; then
        log "Installing pnpm..."
        npm install -g pnpm@latest --quiet || curl -fsSL https://get.pnpm.io/install.sh | sh -
    fi
    pnpm config set registry "$PNPM_REGISTRY" global &>/dev/null || true
}

setup_docker() {
    if command -v docker &>/dev/null; then
        log "Docker is already installed."
        systemctl enable --now docker &>/dev/null || true
        return 0
    fi

    log "Installing Docker runtime..."
    case "$FAM" in
        debian|redhat)
            curl -fsSL https://get.docker.com | sh
            ;;
        arch)
            pkg_install docker docker-compose
            ;;
        alpine)
            pkg_install docker docker-compose
            rc-update add docker boot 2>/dev/null || true
            service docker start 2>/dev/null || true
            ;;
    esac
    systemctl enable --now docker &>/dev/null || true
}

# =============================================================================
# Airlink Component Installation Logic
# =============================================================================
do_install_panel() {
    log "Setting up Airlink Panel..."
    mkdir -p /var/www/airlink

    if [[ -d /var/www/airlink/.git ]]; then
        log "Updating existing Panel repository..."
        git -C /var/www/airlink pull --quiet || true
    else
        log "Cloning Panel repository from $PANEL_REPO..."
        git clone "$PANEL_REPO" /var/www/airlink --quiet
    fi

    cd /var/www/airlink
    log "Installing dependencies with pnpm..."
    pnpm install --quiet

    log "Building Airlink Panel..."
    pnpm build --quiet || true

    if [[ ! -f .env ]]; then
        log "Creating default .env configuration..."
        cat <<EOF > .env
PORT=${ARG_PORT:-3000}
NODE_ENV=production
EOF
    fi

    log "Creating systemd service for Panel..."
    cat <<EOF > /etc/systemd/system/airlink-panel.service
[Unit]
Description=Airlink Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/airlink
ExecStart=$(command -v pnpm) start
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now airlink-panel
}

do_install_daemon() {
    log "Setting up Airlink Daemon..."
    mkdir -p /etc/airlink-daemon

    if [[ -d /etc/airlink-daemon/.git ]]; then
        log "Updating existing Daemon repository..."
        git -C /etc/airlink-daemon pull --quiet || true
    else
        log "Cloning Daemon repository from $DAEMON_REPO..."
        git clone "$DAEMON_REPO" /etc/airlink-daemon --quiet
    fi

    cd /etc/airlink-daemon
    log "Installing Daemon dependencies..."
    pnpm install --quiet

    log "Building Airlink Daemon..."
    pnpm build --quiet || true

    if [[ ! -f config.json ]]; then
        log "Creating config.json..."
        cat <<EOF > config.json
{
  "port": ${ARG_DAEMON_PORT:-3001},
  "panelUrl": "${ARG_PANEL_ADDR:-http://localhost:3000}",
  "key": "${ARG_DAEMON_KEY:-secret}"
}
EOF
    fi

    log "Creating systemd service for Daemon..."
    cat <<EOF > /etc/systemd/system/airlink-daemon.service
[Unit]
Description=Airlink Daemon Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/airlink-daemon
ExecStart=$(command -v pnpm) start
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now airlink-daemon
}

do_install_addons() {
    if [[ -z "$ARG_ADDONS" ]]; then
        return 0
    fi
    log "Installing selected addons: $ARG_ADDONS..."
    for idx in $ARG_ADDONS; do
        if [[ $idx -ge 0 && $idx -lt ${#ADDONS[@]} ]]; then
            local entry="${ADDONS[$idx]}"
            IFS='|' read -r name repo dir target <<< "$entry"
            log "Installing addon: $name..."
            mkdir -p "/var/www/airlink/plugins/$target"
            git clone "$repo" "/tmp/addon_$target" --quiet || true
            if [[ -d "/tmp/addon_$target/$dir" ]]; then
                cp -rf "/tmp/addon_$target/$dir/"* "/var/www/airlink/plugins/$target/"
            fi
            rm -rf "/tmp/addon_$target"
        fi
    done
}

# =============================================================================
# Execution Workflows
# =============================================================================
show_summary() {
    printf "\n"
    printf "${C_GREEN}${BOLD}======================================================${RESET}\n"
    printf "   ${BOLD}Airlink Installation Completed Successfully!${RESET}\n"
    printf "${C_GREEN}${BOLD}======================================================${RESET}\n\n"

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        printf " ${BOLD}Panel URL:${RESET}   http://<YOUR_SERVER_IP>:${ARG_PORT:-3000}\n"
        printf " ${BOLD}Panel Dir:${RESET}   /var/www/airlink\n"
        printf " ${BOLD}Service:${RESET}     systemctl status airlink-panel\n\n"
    fi

    if [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]]; then
        printf " ${BOLD}Daemon Port:${RESET} ${ARG_DAEMON_PORT:-3001}\n"
        printf " ${BOLD}Daemon Key:${RESET}  ${ARG_DAEMON_KEY:-secret}\n"
        printf " ${BOLD}Daemon Dir:${RESET}  /etc/airlink-daemon\n"
        printf " ${BOLD}Service:${RESET}     systemctl status airlink-daemon\n\n"
    fi

    printf " Detailed log stored at: ${C_CYAN}%s${RESET}\n\n" "$LOG"
}

run_interactive() {
    tui_init

    local menu_items=(
        "Install Airlink Panel"
        "Install Airlink Daemon"
        "Install Both (Panel + Daemon)"
        "Exit"
    )

    tui_menu "Airlink Installer (Mitul636 Fork)" "${menu_items[@]}" || { tui_cleanup; exit 0; }

    case "$TUI_RESULT" in
        0) ARG_MODE="panel" ;;
        1) ARG_MODE="daemon" ;;
        2) ARG_MODE="both" ;;
        *) tui_cleanup; exit 0 ;;
    esac

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        tui_input "Enter Panel Port:" "3000"
        ARG_PORT="$TUI_INPUT"
    fi

    if [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]]; then
        tui_input "Enter Daemon Port:" "3001"
        ARG_DAEMON_PORT="$TUI_INPUT"

        tui_input "Enter Panel Address (URL):" "http://localhost:${ARG_PORT:-3000}"
        ARG_PANEL_ADDR="$TUI_INPUT"

        local gen_key; gen_key=$(generate_key)
        tui_input "Enter Daemon Key:" "$gen_key"
        ARG_DAEMON_KEY="$TUI_INPUT"
    fi

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        local addon_names=()
        for addon in "${ADDONS[@]}"; do
            addon_names+=("${addon%%|*}")
        done
        if tui_checklist "Select Addons to Install" "${addon_names[@]}"; then
            ARG_ADDONS="$TUI_MULTI"
        fi
    fi

    if ! tui_confirm "Proceed with installation?"; then
        tui_cleanup
        echo "Installation cancelled."
        exit 0
    fi

    _INSTALLING=1

    local tasks=()
    tasks+=("Detect System Environment")
    tasks+=("Install System Dependencies")
    tasks+=("Configure Node.js Runtime")
    tasks+=("Configure Package Manager")

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        tasks+=("Install Airlink Panel")
    fi

    if [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]]; then
        tasks+=("Install Docker Runtime")
        tasks+=("Install Airlink Daemon")
    fi

    if [[ -n "$ARG_ADDONS" ]]; then
        tasks+=("Install Selected Addons")
    fi

    tui_progress_init "${tasks[@]}"

    tui_progress_step detect_os
    tui_progress_step ensure_deps
    tui_progress_step setup_node
    tui_progress_step setup_pnpm

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        tui_progress_step do_install_panel
    fi

    if [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]]; then
        tui_progress_step setup_docker
        tui_progress_step do_install_daemon
    fi

    if [[ -n "$ARG_ADDONS" ]]; then
        tui_progress_step do_install_addons
    fi

    tui_progress_finish
    tui_cleanup

    show_summary
}

run_noninteractive() {
    ni_header
    log "Starting non-interactive installation..."

    local total_steps=4
    [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]] && total_steps=$(( total_steps + 1 ))
    [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]] && total_steps=$(( total_steps + 2 ))
    [[ -n "$ARG_ADDONS" ]] && total_steps=$(( total_steps + 1 ))

    ni_start "$total_steps"

    ni_run "Detect System Environment" detect_os
    ni_run "Install System Dependencies" ensure_deps
    ni_run "Configure Node.js Runtime" setup_node
    ni_run "Configure Package Manager" setup_pnpm

    if [[ "$ARG_MODE" == "panel" || "$ARG_MODE" == "both" ]]; then
        ni_run "Install Airlink Panel" do_install_panel
    fi

    if [[ "$ARG_MODE" == "daemon" || "$ARG_MODE" == "both" ]]; then
        ni_run "Install Docker Runtime" setup_docker
        ni_run "Install Airlink Daemon" do_install_daemon
    fi

    if [[ -n "$ARG_ADDONS" ]]; then
        ni_run "Install Selected Addons" do_install_addons
    fi

    show_summary
}

# =============================================================================
# Main Entry Point
# =============================================================================
main() {
    check_root
    parse_args "$@"
    select_npm_registry

    if noninteractive; then
        run_noninteractive
    else
        run_interactive
    fi
}

main "$@"
