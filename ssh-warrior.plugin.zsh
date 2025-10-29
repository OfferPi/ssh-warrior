# ssh-warrior.plugin.zsh
# Per-host SSH background color via OSC 11.
# - Stable color from hostname (hash → hue).
# - Defaults: S=0.65, L=0.20 (20% lightness as requested).
# - Works with normal `ssh` (if SSH_WARRIOR_WRAP=1) and via `ssh-warrior`.
# - Restores on exit using OSC 111 then a base fallback color.

# =========================
# Configuration (env vars)
# =========================
: ${SSH_WARRIOR_DISABLE:=0}           # 1 to disable all behavior
: ${SSH_WARRIOR_WRAP:=1}              # 1 to wrap the builtin `ssh`, 0 to leave `ssh` alone
: ${SSH_WARRIOR_DEBUG:=0}             # 1 to echo debug info
: ${SSH_WARRIOR_BASE_HEX:=171421}     # fallback base color (HEX w/o '#') used on exit
: ${SSH_WARRIOR_SATURATION:=0.65}     # saturation [0..1]
: ${SSH_WARRIOR_LIGHTNESS:=0.20}      # lightness [0..1] (keep at 0.20 for your requirement)
: ${SSH_WARRIOR_RESET_STRATEGY:=auto} # auto | base_only
                                      #  - auto: try OSC 111, then force BASE_HEX
                                      #  - base_only: skip OSC 111; set BASE_HEX directly
: ${SSH_WARRIOR_HASH_CMD:=cksum}      # cksum | poly (fallback polynomial hash)
: ${SSH_WARRIOR_ENABLE_SSH_WARRIOR:=1} # 1 to define `ssh-warrior` helper command

# =========================
# Internals
# =========================
_sshwarrior_dbg() { (( SSH_WARRIOR_DEBUG )) && print -r -- "[ssh-warrior] $*"; }

# --- HSL → RGB (0–255) helper (H in [0,360), S,L in [0,1]) ---
_sshwarrior_hsl_to_hex() {
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
_sshwarrior_hue_from_host() {
  local host="$1" num
  if [[ "$SSH_WARRIOR_HASH_CMD" == "cksum" ]] && command -v cksum >/dev/null 2>&1; then
    num=$(print -n -- "$host" | cksum | awk '{print $1}')
  else
    # polynomial fallback
    local -i h=0 i ch
    for (( i=1; i<=${#host}; i++ )); do
      ch=$(printf "%d" "'${host[i]}")
      h=$(( (h * 131 + ch) & 0x7FFFFFFF ))
    done
    num=$h
  fi
  echo $(( num % 360 ))
}

# --- Build HEX from hostname, using configured S and L ---
_sshwarrior_hex_from_host() {
  local host="$1"
  local -F s=$SSH_WARRIOR_SATURATION
  local -F l=$SSH_WARRIOR_LIGHTNESS
  local h=$(_sshwarrior_hue_from_host "$host")
  _sshwarrior_hsl_to_hex "$h" "$s" "$l"
}

# --- OSC 11 set background ---
_sshwarrior_set_bg() {
  local hex="$1"
  print -n -- "\033]11;#${hex}\007"
  _sshwarrior_dbg "set bg #$hex"
}

# --- Reset background based on strategy ---
_sshwarrior_reset_bg() {
  case "$SSH_WARRIOR_RESET_STRATEGY" in
    base_only)
      print -n -- "\033]11;#${SSH_WARRIOR_BASE_HEX}\007"
      _sshwarrior_dbg "reset: base_only #$SSH_WARRIOR_BASE_HEX"
      ;;
    auto|*)
      # Try OSC 111 (reset to terminal default) then enforce fallback base
      print -n -- "\033]111\007"
      print -n -- "\033]11;#${SSH_WARRIOR_BASE_HEX}\007"
      _sshwarrior_dbg "reset: osc111 + base #$SSH_WARRIOR_BASE_HEX"
      ;;
  esac
}

# --- Parse ssh dest (handles user@host, [ipv6], options) ---
_sshwarrior_parse_host() {
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

# --- Core runner used by both wrappers ---
_sshwarrior_run() {
  if (( SSH_WARRIOR_DISABLE )); then
    command ssh "$@"
    return $?
  fi

  local host hex _ssh_exit
  host=$(_sshwarrior_parse_host "$@") || {
    command ssh "$@"
    return $?
  }

  hex=$(_sshwarrior_hex_from_host "$host")
  _sshwarrior_set_bg "$hex"

  command ssh "$@"
  _ssh_exit=$?

  _sshwarrior_reset_bg
  return $_ssh_exit
}

# --- Public command: ssh-warrior (always uses the plugin logic) ---
if (( SSH_WARRIOR_ENABLE_SSH_WARRIOR )); then
  ssh-warrior() { _sshwarrior_run "$@"; }
fi

# --- Optional: wrap normal `ssh` (default on) ---
if (( SSH_WARRIOR_WRAP )); then
  ssh() { _sshwarrior_run "$@"; }
fi

# --- Optional: quick preview helper ---
ssh-warrior-preview() {
  local host="${1:-example}"
  local hex=$(_sshwarrior_hex_from_host "$host")
  print -r -- "$host → #$hex  (S=$SSH_WARRIOR_SATURATION L=$SSH_WARRIOR_LIGHTNESS)"
}

