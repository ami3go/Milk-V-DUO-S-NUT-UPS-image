# shellcheck shell=sh
# Interactive reminder until the appliance has been configured with real UPS
# hardware.  The image never guesses credentials, host addresses or UPS IDs.
case "$-" in
    *i*)
        if [ ! -s /etc/cockpit-ups-wol/config.yaml ]; then
            cat <<'EOF'

Milk-V Duo S UPS appliance image
--------------------------------
cockpit-ups-wol is installed but intentionally not configured or armed.
Connect Ethernet and the real UPS USB interface, then run:

  sudo cockpit-ups-wol-setup --tui

After setup, Cockpit is available on HTTPS port 9090.
EOF
        fi
        ;;
esac
