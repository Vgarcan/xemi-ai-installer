# Scheduled Open WebUI backups: a systemd timer runs a small script that copies the SQLite
# databases with SQLite's online backup API (consistent while Open WebUI keeps running),
# plus uploads, the vector index and the secret key, then rotates old archives.
# Restore always takes a "pre-restore" backup first and rolls back if Open WebUI fails to start.

validate_backup_time() {
  [[ "${1:-}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

validate_backup_keep() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 365 ]
}

owui_backup_dir() {
  echo "${OWUI_BACKUP_DIR:-$OWUI_BACKUP_DIR_DEFAULT}"
}

write_owui_backup_script() {
  local dest="$1"
  local keep="$2"
  cat > "$OWUI_BACKUP_SCRIPT" <<EOF
#!/bin/bash
# Written by xemi_ai_install.sh: Open WebUI backup with rotation.
# Usage: $(basename "$OWUI_BACKUP_SCRIPT") [tag]   (a tag such as pre-restore is never rotated away)
set -euo pipefail
umask 077
DATA_DIR="${OPENWEBUI_DATA_DIR}"
DEST="${dest}"
KEEP="${keep}"
VENV="${OPENWEBUI_VENV}"
EOF
  cat >> "$OWUI_BACKUP_SCRIPT" <<'EOF'
TAG="${1:-}"
[[ "$TAG" =~ ^[a-z-]*$ ]] || { echo "Invalid tag: $TAG" >&2; exit 2; }
[ -f "$DATA_DIR/webui.db" ] || { echo "Open WebUI database not found: $DATA_DIR/webui.db" >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"
work="$(mktemp -d "$DEST/.work.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/data"

# SQLite online backup: a consistent copy even while Open WebUI writes. The Open WebUI venv
# maps sqlite3 to its newer pysqlite3, matching the library that wrote the database.
sqlite_copy() {
  "$VENV/bin/python" - "$1" "$2" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1])
dst = sqlite3.connect(sys.argv[2])
with dst:
    src.backup(dst)
dst.close()
src.close()
PY
}

sqlite_copy "$DATA_DIR/webui.db" "$work/data/webui.db"
[ -f "$DATA_DIR/.webui_secret_key" ] && cp -a "$DATA_DIR/.webui_secret_key" "$work/data/"
[ -d "$DATA_DIR/uploads" ] && cp -a "$DATA_DIR/uploads" "$work/data/"
if [ -d "$DATA_DIR/vector_db" ]; then
  mkdir -p "$work/data/vector_db"
  for item in "$DATA_DIR"/vector_db/*; do
    [ -e "$item" ] || continue
    case "$item" in
      *.sqlite3) sqlite_copy "$item" "$work/data/vector_db/$(basename "$item")" ;;
      *) cp -a "$item" "$work/data/vector_db/" ;;
    esac
  done
fi
"$VENV/bin/pip" show open-webui 2>/dev/null | awk '/^Version:/ {print $2}' > "$work/open-webui-version"

name="openwebui-${stamp}.tar.gz"
[ -n "$TAG" ] && name="openwebui-${TAG}-${stamp}.tar.gz"
tar -C "$work" -czf "$DEST/.${name}.part" data open-webui-version
mv -f "$DEST/.${name}.part" "$DEST/$name"

# Rotation keeps the newest KEEP scheduled archives (openwebui-2*.tar.gz); tagged ones stay.
ls -1t "$DEST"/openwebui-2*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f --
echo "Backup written: $DEST/$name ($(du -h "$DEST/$name" | cut -f1))"
EOF
  chmod 750 "$OWUI_BACKUP_SCRIPT"
}

write_owui_backup_units() {
  local dest="$1"
  local time="$2"
  cat > "/etc/systemd/system/${OWUI_BACKUP_SERVICE}.service" <<EOF
[Unit]
Description=Open WebUI backup (xemi)
After=openwebui.service

[Service]
Type=oneshot
ExecStart=${OWUI_BACKUP_SCRIPT}
Nice=10
IOSchedulingClass=idle
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
# The data directory must be writable: SQLite opens the WAL database read-write to copy it.
ReadWritePaths=${dest} ${OPENWEBUI_DATA_DIR}
EOF
  cat > "/etc/systemd/system/${OWUI_BACKUP_SERVICE}.timer" <<EOF
[Unit]
Description=Daily Open WebUI backup (xemi)

[Timer]
OnCalendar=*-*-* ${time}:00
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

configure_openwebui_backups() {
  header
  load_manifest
  local dest keep time ans data_fs dest_fs
  echo "Daily backups of Open WebUI: chats, users, settings, knowledge, uploads and vector index."
  echo "The model cache is not included (it is downloaded again). Each backup is about the size of"
  echo "the data without cache, compressed."
  echo ""
  if ! is_openwebui_installed || [ ! -f "${OPENWEBUI_DATA_DIR}/webui.db" ]; then
    fail "Open WebUI is not installed or has no database yet."
    pause
    return 1
  fi

  dest="$(ask_absolute_path "Backup directory" "$(owui_backup_dir)")"
  case "$dest" in
    "$OPENWEBUI_DATA_DIR"|"$OPENWEBUI_DATA_DIR"/*)
      fail "The backup directory cannot be inside the Open WebUI data directory."
      pause
      return 1
      ;;
  esac
  while true; do
    keep="$(ask "Daily backups to keep (1-365)" "${OWUI_BACKUP_KEEP:-$OWUI_BACKUP_KEEP_DEFAULT}")"
    validate_backup_keep "$keep" && break
    warn "Use a number from 1 to 365." >&2
  done
  while true; do
    time="$(ask "Time of day for the backup (HH:MM)" "${OWUI_BACKUP_TIME:-$OWUI_BACKUP_TIME_DEFAULT}")"
    validate_backup_time "$time" && break
    warn "Use 24-hour time, for example 03:30." >&2
  done

  # Only a directory created here is made root-only: an existing one (/srv, a shared mount) may be
  # used by other services. The archives themselves are always root-only (umask 077).
  if [ ! -d "$dest" ]; then
    mkdir -p "$dest"
    chmod 700 "$dest"
  fi
  data_fs="$(df --output=source "$OPENWEBUI_DATA_DIR" 2>/dev/null | tail -n 1)"
  dest_fs="$(df --output=source "$dest" 2>/dev/null | tail -n 1)"
  if [ -n "$data_fs" ] && [ "$data_fs" = "$dest_fs" ]; then
    warn "The backups are on the same disk as Open WebUI (${data_fs}). They protect against mistakes,"
    warn "not against a disk failure: copy them elsewhere too, or choose a directory on another disk."
  fi

  write_owui_backup_script "$dest" "$keep"
  write_owui_backup_units "$dest" "$time"
  systemctl daemon-reload
  systemctl enable --now "${OWUI_BACKUP_SERVICE}.timer" >/dev/null 2>&1
  record_manifest "OWUI_BACKUP_ENABLED" "1"
  record_manifest "OWUI_BACKUP_DIR" "$dest"
  record_manifest "OWUI_BACKUP_KEEP" "$keep"
  record_manifest "OWUI_BACKUP_TIME" "$time"
  OWUI_BACKUP_ENABLED=1
  OWUI_BACKUP_DIR="$dest"
  ok "Daily backup scheduled at ${time} into ${dest}, keeping ${keep}."

  ans="$(confirm_proceed "Run the first backup now yes or no" "yes")"
  if is_yes "$ans"; then
    run_owui_backup_service
  fi
  pause
}

run_owui_backup_service() {
  echo "Running backup..."
  if systemctl start "${OWUI_BACKUP_SERVICE}.service"; then
    # The last journal line is systemd's own summary; show the script's result line instead.
    journalctl -u "${OWUI_BACKUP_SERVICE}.service" -n 30 -o cat --no-pager 2>/dev/null \
      | grep '^Backup written:' | tail -n 1 | sed 's/^/  /' || true
    ok "Backup completed."
  else
    fail "Backup failed. Check: journalctl -u ${OWUI_BACKUP_SERVICE} -e"
    return 1
  fi
}

run_openwebui_backup_now() {
  header
  load_manifest
  if [ "${OWUI_BACKUP_ENABLED:-}" != "1" ]; then
    warn "Backups are not set up yet: use Schedule daily backups first."
    pause
    return 0
  fi
  run_owui_backup_service || true
  pause
}

list_openwebui_backups() {
  header
  load_manifest
  local dest
  dest="$(owui_backup_dir)"
  if [ "${OWUI_BACKUP_ENABLED:-}" = "1" ]; then
    echo "Schedule: daily at ${OWUI_BACKUP_TIME:-?}, keeping ${OWUI_BACKUP_KEEP:-?} (pre-restore backups are kept apart)."
    echo "Next run: $(systemctl show "${OWUI_BACKUP_SERVICE}.timer" -p NextElapseUSecRealtime --value 2>/dev/null || echo unknown)"
  else
    warn "Backups are not scheduled."
  fi
  echo ""
  echo "Backups in ${dest}:"
  if compgen -G "${dest}/openwebui-*.tar.gz" >/dev/null; then
    ls -1t "${dest}"/openwebui-*.tar.gz | while read -r file; do
      printf "  %-48s %6s  %s\n" "$(basename "$file")" "$(du -h "$file" | cut -f1)" "$(date -r "$file" '+%F %H:%M')"
    done
  else
    echo "  none"
  fi
  pause
}

restore_openwebui_backup() {
  header
  load_manifest
  local dest file opt i ans work stamp old version installed item
  local -a files=()
  dest="$(owui_backup_dir)"
  mapfile -t files < <(ls -1t "${dest}"/openwebui-*.tar.gz 2>/dev/null)
  if [ "${#files[@]}" -eq 0 ]; then
    warn "No backups found in ${dest}."
    pause
    return 0
  fi
  menu_section "Choose a backup to restore"
  for i in "${!files[@]}"; do
    menu_item "$((i + 1))" "$(printf '%-48s %s' "$(basename "${files[$i]}")" "$(date -r "${files[$i]}" '+%F %H:%M')")"
  done
  echo ""
  opt="$(ask "Select backup (0 to cancel)" "0")"
  if ! [[ "$opt" =~ ^[0-9]+$ ]] || [ "$((10#$opt))" -lt 1 ] || [ "$((10#$opt))" -gt "${#files[@]}" ]; then
    warn "Cancelled."
    pause
    return 0
  fi
  file="${files[$((10#$opt - 1))]}"

  if ! tar -tzf "$file" data/webui.db >/dev/null 2>&1; then
    fail "Not a valid Open WebUI backup: $file"
    pause
    return 1
  fi
  version="$(tar -xzOf "$file" open-webui-version 2>/dev/null || true)"
  installed="$(openwebui_package_version 2>/dev/null || true)"
  echo ""
  echo "Backup: $(basename "$file") (Open WebUI ${version:-unknown}); installed now: ${installed:-unknown}"
  if [ -n "$version" ] && [ -n "$installed" ] && [ "$(printf '%s\n%s\n' "$version" "$installed" | sort -V | tail -n 1)" != "$installed" ]; then
    warn "The backup comes from a NEWER Open WebUI than the one installed; update Open WebUI first."
    pause
    return 1
  fi
  warn "Everything created after this backup (chats, users, documents, settings) will be replaced."
  echo "A pre-restore backup of the current state is taken first."
  ans="$(confirm_proceed "Restore this backup yes or no" "no")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi

  "$OWUI_BACKUP_SCRIPT" pre-restore || { fail "Could not take the pre-restore backup; nothing was changed."; pause; return 1; }
  stamp="$(date +%Y%m%d-%H%M%S)"
  work="$(mktemp -d "${dest}/.restore.XXXXXX")"
  tar -xzf "$file" -C "$work" || { safe_rm_rf "$work" "$dest"; fail "Could not extract the backup."; pause; return 1; }
  old="${OPENWEBUI_DATA_DIR}/.pre-restore-${stamp}"

  systemctl stop openwebui || { safe_rm_rf "$work" "$dest"; fail "Could not stop Open WebUI; nothing was changed."; pause; return 1; }
  # Each step is checked explicitly (errexit is off inside the if): any failure puts the old data back.
  if owui_restore_swap_in "$work" "$old" && systemctl start openwebui \
    && wait_openwebui_health "${OPENWEBUI_PORT:-$WEBUI_PORT_DEFAULT}"; then
    safe_rm_rf "$old" "$OPENWEBUI_DATA_DIR"
    ok "Restored $(basename "$file"). The previous state is in the pre-restore backup."
  else
    fail "Restoring failed or Open WebUI did not start; putting the previous data back."
    systemctl stop openwebui >/dev/null 2>&1 || true
    owui_restore_put_back "$old"
    systemctl start openwebui || true
  fi
  safe_rm_rf "$work" "$dest"
  pause
}

OWUI_RESTORE_ITEMS="webui.db webui.db-wal webui.db-shm .webui_secret_key uploads vector_db"

# Moves the current data aside (same filesystem, instant) and copies the backup in.
owui_restore_swap_in() {
  local work="$1"
  local old="$2"
  local item
  mkdir -p "$old" || return 1
  for item in $OWUI_RESTORE_ITEMS; do
    if [ -e "${OPENWEBUI_DATA_DIR}/${item}" ]; then
      mv -- "${OPENWEBUI_DATA_DIR}/${item}" "$old/" || return 1
    fi
  done
  cp -a "$work/data/." "${OPENWEBUI_DATA_DIR}/" || return 1
  chown -R "$AI_USER:$AI_GROUP" "$OPENWEBUI_DATA_DIR"
}

# Removes whatever was restored and moves the saved data back.
owui_restore_put_back() {
  local old="$1"
  local item
  [ -d "$old" ] || return 0
  for item in $OWUI_RESTORE_ITEMS; do
    if [ -e "$old/${item}" ]; then
      if [ -e "${OPENWEBUI_DATA_DIR}/${item}" ]; then
        safe_rm_rf "${OPENWEBUI_DATA_DIR}/${item}" "$OPENWEBUI_DATA_DIR" || true
      fi
      mv -- "$old/${item}" "${OPENWEBUI_DATA_DIR}/" || warn "Could not move back ${item}; it is in ${old}"
    fi
  done
  rmdir "$old" 2>/dev/null || warn "Previous data left in ${old}; check it before deleting."
}

remove_openwebui_backups() {
  local purge="${1:-0}"
  [ "${OWUI_BACKUP_ENABLED:-}" = "1" ] || return 0
  systemctl disable --now "${OWUI_BACKUP_SERVICE}.timer" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${OWUI_BACKUP_SERVICE}.service" "/etc/systemd/system/${OWUI_BACKUP_SERVICE}.timer" "$OWUI_BACKUP_SCRIPT"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "${OWUI_BACKUP_SERVICE}.service" >/dev/null 2>&1 || true
  local key
  for key in OWUI_BACKUP_ENABLED OWUI_BACKUP_DIR OWUI_BACKUP_KEEP OWUI_BACKUP_TIME; do
    remove_manifest_key "$key"
  done
  OWUI_BACKUP_ENABLED=""
  ok "Scheduled backups removed."
  # Backup archives are user data: they are never deleted automatically, not even by purge.
  if [ "$purge" = "1" ]; then
    warn "Backup archives kept in $(owui_backup_dir); delete them by hand when no longer needed."
  fi
}

remove_openwebui_backups_interactive() {
  header
  load_manifest
  if [ "${OWUI_BACKUP_ENABLED:-}" != "1" ]; then
    warn "Backups are not scheduled."
    pause
    return 0
  fi
  local dest ans
  dest="$(owui_backup_dir)"
  ans="$(confirm_proceed "Stop the daily backups yes or no" "no")"
  if ! is_yes "$ans"; then
    warn "Cancelled."
    pause
    return 0
  fi
  remove_openwebui_backups 0
  ans="$(ask "Also delete the existing backup archives in ${dest} yes or no" "no")"
  if is_yes "$ans" && [ -d "$dest" ]; then
    # Only this installer's archives; the directory goes only if nothing else is in it.
    rm -f -- "$dest"/openwebui-*.tar.gz
    rmdir "$dest" 2>/dev/null || true
    ok "Backup archives deleted from $dest"
  else
    echo "Backup archives kept in ${dest}."
  fi
  pause
}

openwebui_backups_menu() {
  run_submenu "Open WebUI Backups" \
    "Schedule daily backups (directory, time, how many to keep)|configure_openwebui_backups" \
    "Run a backup now|run_openwebui_backup_now" \
    "List backups and next run|list_openwebui_backups" \
    "Restore a backup|restore_openwebui_backup" \
    "Stop daily backups|remove_openwebui_backups_interactive"
}

doctor_check_backups() {
  if [ "${OWUI_BACKUP_ENABLED:-}" != "1" ]; then
    doctor_warn "Open WebUI backups are not scheduled: Open WebUI > Backups"
    return 0
  fi
  local newest age_h
  if systemctl is-active "${OWUI_BACKUP_SERVICE}.timer" >/dev/null 2>&1; then
    doctor_ok "Open WebUI backup timer active (daily at ${OWUI_BACKUP_TIME:-?})"
  else
    doctor_fail "Open WebUI backup timer is not active"
  fi
  newest="$(ls -1t "$(owui_backup_dir)"/openwebui-*.tar.gz 2>/dev/null | head -n 1 || true)"
  if [ -z "$newest" ]; then
    doctor_warn "No Open WebUI backup has been written yet"
  else
    age_h="$(( ($(date +%s) - $(date -r "$newest" +%s)) / 3600 ))"
    if [ "$age_h" -le 48 ]; then
      doctor_ok "Latest Open WebUI backup: $(basename "$newest") (${age_h} h ago)"
    else
      doctor_warn "Latest Open WebUI backup is ${age_h} h old: $(basename "$newest")"
    fi
  fi
}
