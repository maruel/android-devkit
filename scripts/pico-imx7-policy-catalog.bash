# shellcheck disable=SC2034
# Inventory is consumed by sourcing scripts, including the target updater.
# Shared generated policy inventory for image verification and target updates.
declare -a policy_paths=(
  /etc/sysctl.d/90-pico-imx7-memory.conf
  /usr/local/sbin/pico-imx7-zram-init
  /etc/systemd/system/zram-config.service.d/10-pico-imx7-memory.conf
  /etc/firefox/syspref.js
  /home/ubuntu/.config/autostart/blueman.desktop
  /usr/local/bin/pico-imx7-plain-background
  /home/ubuntu/.config/autostart/pico-imx7-plain-background.desktop
  /usr/local/sbin/pico-imx7-hostname
  /etc/systemd/system/pico-imx7-hostname.service
  /usr/local/sbin/pico-imx7-device-init
  /etc/systemd/system/tn_init.service.d/10-pico-imx7.conf
  /etc/systemd/journald.conf.d/10-pico-imx7-recovery.conf
  /etc/systemd/system.conf.d/10-pico-imx7-watchdog.conf
  /usr/local/bin/pico-imx7-cheese-defaults
  /home/ubuntu/.config/autostart/pico-imx7-cheese-defaults.desktop
)
declare -a policy_names=(
  memory_policy_sysctl memory_policy_zram_initializer memory_policy_zram_drop_in
  memory_policy_firefox_preferences memory_policy_blueman_autostart
  memory_policy_background_initializer memory_policy_background_autostart
  hostname_policy_initializer hostname_policy_service board_policy_device_initializer
  board_policy_device_service board_policy_journal board_policy_watchdog
  board_policy_cheese_initializer board_policy_cheese_autostart
)
declare -a hostname_dependencies=(
  sysinit.target.wants NetworkManager.service.requires avahi-daemon.service.requires
)
declare -a masked_services=(
  bluetooth.service blueman-mechanism.service ModemManager.service udisks2.service
  rsyslog.service snapd.service snapd.socket snapd.seeded.service
  snapd.autoimport.service snapd.apparmor.service
)
