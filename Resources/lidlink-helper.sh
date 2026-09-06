#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 hzn822-dotcom and LidLink contributors

set -u

last_lid=""

restore_sleep() {
    /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
}

trap restore_sleep EXIT TERM INT

while true; do
    console_user=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
    enabled="0"

    if [[ -n "$console_user" && "$console_user" != "root" && "$console_user" != "loginwindow" ]]; then
        config_file="/Users/${console_user}/Library/Application Support/com.codex.lidlink/enabled"
        if [[ -f "$config_file" ]]; then
            enabled=$(/bin/cat "$config_file" 2>/dev/null | /usr/bin/tr -cd '01' | /usr/bin/head -c 1)
        fi
    fi

    if /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -q "AC Power"; then
        on_ac="1"
    else
        on_ac="0"
    fi

    if [[ "$enabled" == "1" && "$on_ac" == "1" ]]; then
        desired="1"
    else
        desired="0"
    fi

    current=$(/usr/bin/pmset -g 2>/dev/null | /usr/bin/awk '/SleepDisabled/{print $2; exit}')
    if [[ "$current" != "$desired" ]]; then
        /usr/bin/pmset -a disablesleep "$desired" >/dev/null 2>&1 || true
    fi

    lid=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 4 2>/dev/null | /usr/bin/awk -F'= ' '/AppleClamshellState/{print $2; exit}')
    if [[ "$desired" == "1" && "$lid" == "Yes" && "$last_lid" != "Yes" ]]; then
        /usr/bin/pmset displaysleepnow >/dev/null 2>&1 || true
    fi
    last_lid="$lid"

    /bin/sleep 2
done
