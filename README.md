# ssh-warrior

An **Oh-My-Zsh plugin** that automatically changes your terminal background color based on the SSH host you connect to.  
Each host gets a unique, consistent color — making it easy to instantly see *where* you are.  

## Features

- 🎨 **Unique background per host:**  
  The hostname is hashed to a color hue, ensuring each host always gets the same color.

- 🌗 **Fixed lightness (20%):**  
  Keeps the color dark enough for text to remain readable.

- 🔄 **Automatic reset:**  
  When the SSH session closes, the terminal background resets to your default base color.

- ⚙️ **Customizable via environment variables:**  
  Fine-tune saturation, lightness, hashing method, or disable wrapping entirely.

- 🧩 **Seamless integration:**  
  Works with normal `ssh` commands or through the helper command `ssh-warrior`.

## Requirements

- **Zsh**
- **Oh My Zsh**
- A terminal that supports **OSC 11 / OSC 111** escape sequences  
  (Kitty, iTerm2, Alacritty, GNOME Terminal, etc. all work great)

## Installation

1. **Clone the repository:**

   ```sh
   git clone https://github.com/OfferPi/ssh-warrior.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ssh-warrior
   ````

2. **Enable the plugin:**

   Edit your `~/.zshrc` and add `ssh-warrior` to the `plugins=( … )` list:

   ```zsh
   plugins=(
     git
     ssh-warrior
   )
   ```

3. **Reload Zsh:**

   ```zsh
   source ~/.zshrc
   ```

## Configuration Variables

You can set any of these in your `~/.zshrc` **before** `source $ZSH/oh-my-zsh.sh`.

| Variable                         | Default  | Description                                                                                |
| -------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `SSH_WARRIOR_DISABLE`            | `0`      | Set to `1` to disable all behavior.                                                        |
| `SSH_WARRIOR_WRAP`               | `1`      | Wrap the normal `ssh` command. If `0`, only `ssh-warrior` is available.                    |
| `SSH_WARRIOR_ENABLE_SSH_WARRIOR` | `1`      | Create the explicit `ssh-warrior` helper command.                                          |
| `SSH_WARRIOR_BASE_HEX`           | `171421` | Base color to restore on exit (HEX without `#`).                                           |
| `SSH_WARRIOR_SATURATION`         | `0.65`   | Saturation value of generated colors.                                                      |
| `SSH_WARRIOR_LIGHTNESS`          | `0.20`   | Lightness (brightness) value of generated colors.                                          |
| `SSH_WARRIOR_RESET_STRATEGY`     | `auto`   | How to reset the background. `auto`: try OSC 111 then fallback. `base_only`: skip OSC 111. |
| `SSH_WARRIOR_HASH_CMD`           | `cksum`  | Hash function for color generation (`cksum` or `poly`).                                    |
| `SSH_WARRIOR_DEBUG`              | `0`      | Set to `1` for debug output to the terminal.                                               |

## Usage

You can use **ssh-warrior** in two ways:

### 1. Normal SSH command (default)

Just connect like you normally do:

```bash
ssh user@myserver
```

The plugin automatically adjusts your background color before connecting
and restores it when the session closes.

### 2. Explicit helper

If you prefer to keep your normal `ssh` untouched:

```bash
export SSH_WARRIOR_WRAP=0
```

Then use:

```bash
ssh-warrior myserver
```

### 3. Preview a host’s color

You can preview what color a host would get without connecting:

```bash
ssh-warrior-preview myserver
# => myserver → #12345A  (S=0.65 L=0.20)
```
