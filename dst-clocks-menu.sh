#!/bin/bash
# Menu driver for the alvarosaavedra.dst-clocks bar widget.
#
# With no arguments this shows the Omarchy menu flow: add a clock, remove a
# clock, or change a clock's emoji. State is read from and written back to
# the widget's layout entry in ~/.config/omarchy/shell.json; the shell's
# FileView watcher hot-reloads the bar on the save.
#
# (Writes go straight to shell.json rather than `omarchy bar set --json`
# because qs's IPC CLI splits comma-containing arguments — an array of zones
# cannot cross that boundary intact.)
#
# Non-interactive forms (used by the menu flow itself, handy from a shell):
#   dst-clocks-menu.sh add <tz> [emoji]
#   dst-clocks-menu.sh remove <tz>
#   dst-clocks-menu.sh emoji <tz> <emoji>
#   dst-clocks-menu.sh list

set -euo pipefail

PLUGIN_ID="alvarosaavedra.dst-clocks"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

# Current zones of the widget's layout entry as a JSON array. Falls back to
# the legacy zone1Flag/zone1Tz/zone2Flag/zone2Tz keys so a pre-zones config
# survives its first edit intact.
current_zones() {
  jq -c --arg id "$PLUGIN_ID" '
    [.bar.layout[][]? | objects | select(.id == $id)][0] as $e
    | if $e == null then
        error("no layout entry with id " + $id)
      else
        ($e.zones // [
          { flag: ($e.zone1Flag // "🇨🇱"), tz: ($e.zone1Tz // "America/Santiago") },
          { flag: ($e.zone2Flag // "🇨🇦"), tz: ($e.zone2Tz // "America/Toronto") }
        ])
      end' "$SHELL_JSON"
}

write_zones() {
  local tmp
  tmp=$(mktemp "$(dirname "$SHELL_JSON")/.dst-clocks.XXXXXX")
  jq --arg id "$PLUGIN_ID" --argjson zones "$1" '
    .bar.layout |= with_entries(
      .value |= map(if (.id? == $id) then . + { zones: $zones } else . end)
    )' "$SHELL_JSON" > "$tmp"
  mv "$tmp" "$SHELL_JSON"
}

cmd_add() {
  local tz="$1" emoji="${2:-🕐}"
  write_zones "$(current_zones | jq -c --arg tz "$tz" --arg flag "$emoji" \
    'map(select(.tz != $tz)) + [{ flag: $flag, tz: $tz }]')"
}

cmd_remove() {
  local tz="$1"
  write_zones "$(current_zones | jq -c --arg tz "$tz" 'map(select(.tz != $tz))')"
}

cmd_emoji() {
  local tz="$1" emoji="$2"
  write_zones "$(current_zones | jq -c --arg tz "$tz" --arg flag "$emoji" \
    'map(if .tz == $tz then .flag = $flag else . end)')"
}

# Common flag emojis to pick from; the last entry falls back to free input.
pick_emoji() {
  local prompt="$1" choice
  choice=$(printf '%s\n' \
    "🇨🇱 Chile" "🇨🇦 Canada" "🇺🇸 United States" "🇲🇽 Mexico" "🇧🇷 Brazil" \
    "🇦🇷 Argentina" "🇨🇴 Colombia" "🇵🇪 Peru" "🇬🇧 United Kingdom" "🇮🇪 Ireland" \
    "🇵🇹 Portugal" "🇪🇸 Spain" "🇫🇷 France" "🇩🇪 Germany" "🇮🇹 Italy" \
    "🇳🇱 Netherlands" "🇧🇪 Belgium" "🇨🇭 Switzerland" "🇸🇪 Sweden" "🇳🇴 Norway" \
    "🇩🇰 Denmark" "🇫🇮 Finland" "🇵🇱 Poland" "🇺🇦 Ukraine" "🇷🇺 Russia" "🇹🇷 Türkiye" \
    "🇮🇱 Israel" "🇦🇪 UAE" "🇮🇳 India" "🇯🇵 Japan" "🇰🇷 South Korea" \
    "🇨🇳 China" "🇹🇼 Taiwan" "🇭🇰 Hong Kong" "🇦🇺 Australia" "🇳🇿 New Zealand" \
    "🕐 Plain clock face" "✏️ Other — type or paste …" \
    | omarchy-menu-select "$prompt" -- --width 520 --maxheight 520) || return 1

  case "$choice" in
    ✏️*)
      omarchy-menu-input "$prompt" || return 1
      ;;
    🕐*)
      printf '🕐\n'
      ;;
    *)
      # First whitespace-separated token is the emoji itself.
      printf '%s\n' "${choice%% *}"
      ;;
  esac
}

interactive() {
  local action
  action=$(printf '%s\n' "Add clock" "Remove clock" "Change emoji" \
    | omarchy-menu-select "DST Clocks" -- --width 520) || exit 0

  case "$action" in
    "Add clock")
      local tz emoji
      tz=$(timedatectl list-timezones \
        | omarchy-menu-select "Add clock: timezone" -- --width 520 --maxheight 520) || exit 0
      emoji=$(pick_emoji "Add clock: emoji for $tz") || exit 0
      [[ -n "$emoji" ]] || exit 0
      cmd_add "$tz" "$emoji"
      ;;
    "Remove clock")
      local pick tz
      pick=$(current_zones | jq -r '.[] | "\(.flag)\t\(.tz)"' \
        | omarchy-menu-select "Remove clock" -- --width 520) || exit 0
      tz="${pick#*$'\t'}"
      cmd_remove "$tz"
      ;;
    "Change emoji")
      local pick tz emoji
      pick=$(current_zones | jq -r '.[] | "\(.flag)\t\(.tz)"' \
        | omarchy-menu-select "Change emoji: which clock" -- --width 520) || exit 0
      tz="${pick#*$'\t'}"
      emoji=$(pick_emoji "Change emoji: $tz") || exit 0
      [[ -n "$emoji" ]] || exit 0
      cmd_emoji "$tz" "$emoji"
      ;;
  esac
}

case "${1:-}" in
  "")     interactive ;;
  add)    cmd_add "$2" "${3:-🕐}" ;;
  remove) cmd_remove "$2" ;;
  emoji)  cmd_emoji "$2" "$3" ;;
  list)   current_zones | jq -r '.[] | "\(.flag)\t\(.tz)"' ;;
  *)
    echo "usage: $0 [add <tz> [emoji] | remove <tz> | emoji <tz> <emoji> | list]" >&2
    exit 64
    ;;
esac
