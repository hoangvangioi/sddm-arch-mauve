#!/usr/bin/env bash
# Install, update or remove the sddm-arch-mauve theme.
#
#   ./install.sh              install (or update) for this machine
#   ./install.sh --dry-run    print what it would do, change nothing
#   ./install.sh --uninstall  remove the theme and its Current= line
#
# Copying files needs root, so this re-runs itself under sudo when needed.
# It never restarts SDDM: that ends your graphical session. The command is
# printed at the end instead.

set -euo pipefail

theme=sddm-arch-mauve
themes_dir=/usr/share/sddm/themes
conf=/etc/sddm.conf
here=$(cd -- "$(dirname -- "$0")" && pwd)

dry=0
uninstall=0
for arg in "$@"; do
    case $arg in
    -n | --dry-run) dry=1 ;;
    -u | --uninstall) uninstall=1 ;;
    -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '%s\n' "$*"; }
run() {
    if [ "$dry" -eq 1 ]; then
        printf '  would run: %s\n' "$*"
    else
        "$@"
    fi
}

# ---- everything below this line runs as root ----
if [ "$(id -u)" -ne 0 ]; then
    if [ "$dry" -eq 1 ]; then
        say "(--dry-run as a normal user: root-only steps are simulated, not checked)"
    else
        exec sudo -- "$0" "$@"
    fi
fi

# ---- uninstall ----
if [ "$uninstall" -eq 1 ]; then
    say "removing $themes_dir/$theme"
    run rm -rf "${themes_dir:?}/$theme"
    say "removing [Theme] Current=$theme from $conf"
    if [ -f "$conf" ] && grep -q "^Current=$theme\$" "$conf"; then
        if [ "$dry" -eq 1 ]; then
            run sed -i "\|^Current=$theme\$|d" "$conf"
        else
            # Drop our Current= line, and drop the [Theme] header too when that
            # leaves the section empty.
            awk -v theme="$theme" '
                { line[NR] = $0 }
                /^\[/ { sect = $0 }
                sect == "[Theme]" && $0 !~ /^\[/ && $0 != "" && $0 != "Current=" theme { keys++ }
                END {
                    sect = ""
                    for (i = 1; i <= NR; i++) {
                        l = line[i]
                        if (l == "Current=" theme) continue
                        if (l ~ /^\[/) {
                            sect = l
                            if (sect == "[Theme]" && keys == 0) continue
                        }
                        print l
                    }
                }
            ' "$conf" > "$conf.new" && chmod --reference="$conf" "$conf.new" && mv "$conf.new" "$conf"
        fi
    fi
    [ "$dry" -eq 1 ] || say "done. Restart SDDM to fall back to the default theme:
  systemctl restart sddm"
    exit 0
fi

# ---- sanity checks ----
missing=
for pkg in sddm qt6-declarative; do
    pacman -Qq "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
done
[ -n "$missing" ] && say "warning: not installed:$missing  (continue anyway, Ctrl-C to abort)"

for f in Main.qml theme.conf metadata.desktop Components Assets; do
    [ -e "$here/$f" ] || { echo "error: $here/$f is missing, run this from the repository" >&2; exit 1; }
done

# ---- theme files ----
say "installing to $themes_dir/$theme"
run install -d -m 755 "${themes_dir:?}/$theme"
# The theme itself. Everything here lives at the top level of the repository, so
# each item is copied explicitly - `cp -r` would also drag in .git, install.sh
# and the README.
run rm -rf "${themes_dir:?}/$theme/Components" "${themes_dir:?}/$theme/Assets"
run cp -r -- "$here/Main.qml" "$here/theme.conf" "$here/metadata.desktop" \
    "$here/Components" "$here/Assets" "$themes_dir/$theme/"
# Optional files, installed only when they are there.
for f in background.png preview.png; do
    if [ -f "$here/$f" ]; then
        run install -m 644 "$here/$f" "$themes_dir/$theme/$f"
    fi
done
run chmod -R a+rX "$themes_dir/$theme"

# ---- SDDM config ----
# /etc/sddm.conf is the file SDDM reads (ConfigReader.cpp:148). Its [Theme]
# section is rewritten, but the rest of the file is kept: overwriting it, as the
# upstream setup.sh does, drops every other setting on the machine.
say "setting [Theme] Current=$theme in $conf"
if [ "$dry" -eq 1 ]; then
    printf '  would rewrite the [Theme] section of %s\n' "$conf"
elif [ ! -f "$conf" ]; then
    printf '[Theme]\nCurrent=%s\n' "$theme" >"$conf"
    chmod 644 "$conf"
elif grep -qx '\[Theme\]' "$conf"; then
    # Delete the section's own Current= line, then insert ours after the header.
    awk -v theme="$theme" '
        /^\[/ { sect = $0 }
        sect == "[Theme]" && /^Current=/ { next }
        { print }
        sect == "[Theme]" && /^\[Theme\]$/ { print "Current=" theme }
    ' "$conf" >"$conf.new" && chmod --reference="$conf" "$conf.new" && mv "$conf.new" "$conf"
else
    printf '\n[Theme]\nCurrent=%s\n' "$theme" >>"$conf"
fi

say ""
say "done. Check it first without logging out:
  sddm-greeter-qt6 --test-mode --theme $themes_dir/$theme"
say "Then apply it:
  systemctl restart sddm"
