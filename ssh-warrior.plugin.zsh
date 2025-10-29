# ~/.oh-my-zsh/custom/plugins/ssh-host-bg/ssh-host-bg.plugin.zsh
# Per-host SSH background color via OSC 11. Restores on exit.
# - Hue seeded from hostname; S=0.65, L=0.20 (fixed).
# - Works with plain `ssh`, `user@host`, options, IPv6 [addr], etc.
# - On exit: try OSC 111 reset, then force a fallback base color.

# Toggle off (skip coloring):
#   export SSH_BG_DISABLE=1
#
# Fallback base background (HEX without '#') used on exit:
: ${SSH_BG_FALLBACK_DEFAULT:=171421}

# --- HSL → RGB (0–255) helper (H in [0,360), S,L in [0,1]) ---
_sshbg_hsl_to_hex() {
  local -F h=$1 s=$2 l=$3
  local -F c x m r1=0 g1=0 b1=0 r g b hp mod2 tminus1 abs_tminus1

  # chroma
  local -F twol=$(( 2.0*l - 1.0 ))
  (( twol < 0 )) && twol=$(( -twol ))
  c=$(( (1.0 - twol) * s ))

  # hp in [0,6)
  hp=$(( h / 60.0 ))
  while (( hp >= 6.0 )); do hp=$(( hp - 6.0 )); done
  while (( hp < 0.0 ));  do hp=$(( hp + 6.0 )); done

  # mod2 in [0,2)
  mod2=$hp
  while (( mod2 >= 2.0 )); do mod2=$(( mod2 - 2.0 )); done
  while (( mod2 < 0.0 ));  do mod2=$(( mod2 + 2.0 )); done

  # x = c * (1 - |mod2 - 1|)
  tminus1=$(( mod2 - 1.0 ))
  abs_tminus1=$tminus1
  (( abs_tminus1 < 0.0 )) && abs_tminus1=$(( -abs_tminus1 ))
  x=$(( c * (1.0 - abs_tminus1) ))

  if (( 0.0 <= hp && hp < 1.0 )); then
    r1=$c; g1=$x; b1=0
  elif (( 1.0 <= hp && hp < 2.0 )); then
    r1=$x; g1=$c; b1=0
  elif (( 2.0 <= hp && hp < 3.0 )); then
    r1=0;  g1=$c; b1=$x
  elif (( 3.0 <= hp && hp < 4.0 )); then
    r1=0;  g1=$x; b1=$c
  elif (( 4.0 <= hp && hp < 5.0 )); then
    r1=$x; g1=0;  b1=$c
  else
    r1=$c; g1=0;  b1=$x
  fi

  m=$(( l - c/2.0 ))
  r=$(( (r1 + m) * 255.0 ))
  g=$(( (g1 + m) * 255.0 ))
  b=$(( (b1 + m) * 255.0 ))

  (( r < 0 )) && r=0; (( r > 255 )) && r=255
  (( g < 0 )) && g=0; (( g > 255 )) && g=255
  (( b < 0 )) && b=0; (( b > 255 )) && b=255
  printf "%02X%02X%02X" ${r%.*} ${g%.*} ${b%.*}
}

# --- Hostname → Hue in [0,360) ---
_sshbg_hue_from_host() {
  local host="$1" num
  if command -v cksum >/dev/null 2>&1; then
    num=$(print -n -- "$host" | cksum | awk '{print $1}')
  else
    local -i h=0 i ch
    for (( i=1; i<=${#host}; i++ )); do
      ch=$(printf "%d" "'${host[i]}")
      h=$(( (h * 131 + ch) & 0x7FFFFFFF ))
    done
    num=$h
  fi
  echo $(( num % 360 ))
}

# --- Build HEX from hostname, S=0.65, L=0.20 ---
_sshbg_hex_from_host() {
  local host="$1"
  local -F s=0.65 l=0.20
  local h=$(_sshbg_hue_from_host "$host")
  _sshbg_hsl_to_hex "$h" "$s" "$l"
}

# --- OSC 11 set background ---
_sshbg_set_bg() {
  local hex="$1"
  print -n -- "\033]11;#${hex}\007"
}

# --- Reset background: try OSC 111, then force fallback base ---
_sshbg_reset_bg() {
  # Try terminal default
  print -n -- "\033]111\007"
  # Ensure a clean restore even if OSC 111 is ignored
  if [[ -n "$SSH_BG_FALLBACK_DEFAULT" ]]; then
    print -n -- "\033]11;#${SSH_BG_FALLBACK_DEFAULT}\007"
  fi
}

# --- Parse ssh dest (handles user@host, [ipv6], options) ---
_sshbg_parse_host() {
  local argv=("$@")
  local dest="" a
  local i=1
  local n=${#argv[@]}

  while (( i <= n )); do
    a="${argv[i]}"

    if [[ "$a" == "--" ]]; then
      (( i++ ))
      while (( i <= n )); do
        a="${argv[i]}"
        if [[ "$a" != -* ]]; then dest="$a"; break; fi
        (( i++ ))
      done
      break
    fi

    if [[ "$a" == --* ]]; then
      if [[ "$a" == *=* ]]; then
        (( i++ )); continue
      else
        (( i+=2 )); continue
      fi
    fi

    if [[ "$a" == -* ]]; then
      if [[ "$a" == -o* ]]; then
        if [[ "$a" == "-o" ]]; then (( i+=2 )); else (( i++ )); fi
        continue
      fi
      if [[ "$a" == -[plJFfibcDEFILmRSWwRJ]*[^-] ]]; then
        (( i++ )); continue
      fi
      case "$a" in
        -p|-l|-J|-F|-i|-W|-R|-L|-D|-E|-S|-b|-c|-I|-m)
          (( i+=2 )); continue;;
      esac
      (( i++ ))
      continue
    fi

    dest="$a"
    break
  done

  [[ -z "$dest" ]] && return 1
  dest="${dest#*@}"
  dest="${dest#\[}"
  dest="${dest%\]}"
  print -r -- "$dest"
}

# --- ssh wrapper ---
ssh() {
  if [[ -n "$SSH_BG_DISABLE" ]]; then
    command ssh "$@"
    return $?
  fi

  local host hex _ssh_exit
  host=$(_sshbg_parse_host "$@") || {
    command ssh "$@"
    return $?
  }

  hex=$(_sshbg_hex_from_host "$host")
  _sshbg_set_bg "$hex"

  command ssh "$@"
  _ssh_exit=$?

  _sshbg_reset_bg
  return $_ssh_exit
}

