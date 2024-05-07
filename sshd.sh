#!/usr/bin/env sh

GITHUB_USER="${GITHUB_USER:-pschmitt}"
KEYS_URL="https://github.com/$GITHUB_USER.keys"

user_homedir() {
  TARGET_USER="$1"
  USER_HOME=$(eval echo "~${TARGET_USER}")

  if [ -n "$USER_HOME" ]
  then
    echo "$USER_HOME"
    return 0
  fi

  USER_HOME=$(awk -v u="$TARGET_USER" -v FS=':' '$1==u {print $6}' /etc/passwd)
  if [ -n "$USER_HOME" ]
  then
    echo "$USER_HOME"
    return 0
  fi

  USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  if [ -n "$USER_HOME" ]
  then
    echo "$USER_HOME"
    return 0
  fi

  if [ "$TARGET_USER" = "root" ] && [ -d "/root" ]
  then
    echo "/root"
    return 0
  fi

  if [ -d "/home/${TARGET_USER}" ]
  then
    echo "/home/${TARGET_USER}"
    return 0
  fi

  return 1
}

fetch() {
  if command -v curl >/dev/null 2>&1
  then
    command curl -fsSL "$@"
    return "$?"
  fi

  if command -v wget >/dev/null 2>&1
  then
    command wget -q -O- "$@"
    return "$?"
  fi

  echo "Neither curl nor wget is found. Cannot download." >&2
  return 1
}

fetch_keys() {
  fetch "$KEYS_URL"
}

# Function to elevate a command (directly if root, via sudo or doas otherwise)
sudo() {
  COMMAND="$*"

  # Running as root
  if [ "$(id -u)" -eq 0 ]
  then
    eval "$COMMAND"
    return $?
  fi

  if command -v sudo >/dev/null 2>&1
  then
    if ! command sudo -n true
    then
      echo "sudo requires a password or permission is denied." >&2
      return 1
    fi

    # shellcheck disable=SC2086
    command sudo -n $COMMAND
    return "$?"
  fi

  if command -v doas >/dev/null 2>&1
  then
    if ! doas true
    then
      echo "doas requires a password or permission is denied." >&2
      return 1
    fi

    # shellcheck disable=SC2086
    doas $COMMAND
    return "$?"
  fi

  echo "Neither sudo nor doas found. Cannot elevate command." >&2
  return 1
}

update_authorized_keys() {
  TARGET_FILE="$1"
  KEYS="$2"

  while IFS= read -r key
  do
    # Skip empty lines
    if [ -z "$key" ]
    then
      continue
    fi

    if ! sudo cat "$TARGET_FILE" 2>/dev/null | grep -qxF "$key"
    then
      echo "$key" | sudo tee -a "$TARGET_FILE" >/dev/null
    fi
  done <<EOF
$KEYS
EOF

  sudo chmod 600 "$TARGET_FILE"
}

install_sshd() {
  if command -v sshd >/dev/null 2>&1
  then
    echo "sshd command found. OpenSSH server is likely installed."
    return 0
  fi

  if grep -iq alpine /etc/os-release
  then
    if ! sudo apk add --no-cache openssh-server
    then
      echo "Failed to install OpenSSH (apk)." >&2
      return 1
    fi

    return 0
  fi

  if grep -iqE 'ubuntu|debian' /etc/os-release
  then
    if ! sudo apt-get update
    then
      echo "Failed to update package list." >&2
      return 1
    fi
    if ! sudo apt-get install -y --no-install-recommends openssh-server
    then
      echo "Failed to install OpenSSH (apt)." >&2
      return 1
    fi

    return 0
  fi

  if grep -iqE 'centos|redhat|fedora|oracle' /etc/os-release
  then
    if command -v dnf >/dev/null 2>&1
    then
      if ! sudo dnf install -y openssh-server
      then
        echo "Failed to install OpenSSH (dnf)." >&2
        return 1
      fi

      return 0
    fi

    if ! sudo yum install -y openssh-server
    then
      echo "Failed to install OpenSSH (yum/dnf)." >&2
      return 1
    fi
    return 0
  fi

  echo "Unsupported OS. Please install OpenSSH server manually." >&2
  return 1
}

sshd_running() {
  SSHD_PATH="$(command -v sshd)"
  if [ -z "$SSHD_PATH" ]
  then
    echo "sshd command not found." >&2
    echo "Please install OpenSSH server" >&2
    return 1
  fi

  if command -v pgrep >/dev/null 2>&1
  then
    pgrep -af "$SSHD_PATH" >/dev/null
    return "$?"
  fi

  # shellcheck disable=SC2009
  ps -e | grep -v "$$" | grep -q "$SSHD_PATH"
}

start_sshd() {
  install_sshd
  # Create host keys if they do not exist
  sudo ssh-keygen -A

  if sshd_running
  then
    echo "sshd is already running."
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1
  then
    if sudo "systemctl start sshd"
    then
      echo "sshd started via systemctl."
      return 0
    else
      echo "Failed to start sshd via systemctl." >&2
    fi
  fi

  if command -v service >/dev/null 2>&1
  then
    if sudo "service ssh start"
    then
      echo "sshd started via service."
      return 0
    else
      echo "Failed to start sshd via service." >&2
    fi
  fi

  # Attempt to start sshd directly
  SSHD_PATH=$(command -v sshd)
  if [ -z "$SSHD_PATH" ]
  then
    echo "Unable to start sshd. Please ensure sshd is installed." >&2
    return 1
  fi

  if sudo "$SSHD_PATH"
  then
    echo "sshd started directly."
    return 0
  fi

  echo "Failed to start sshd directly." >&2
  return 1
}

setup_keys() {
  TARGET_USER="${1:-$(whoami)}"

  if [ -z "$TARGET_USER" ]
  then
    echo "No user specified." >&2
    return 1
  fi

  USER_HOME=$(user_homedir "$TARGET_USER")

  if [ -z "$USER_HOME" ]
  then
    echo "Failed to determine home directory for $TARGET_USER." >&2
    return 1
  fi

  SSH_DIR="${USER_HOME}/.ssh"
  sudo mkdir -p "$SSH_DIR"
  sudo chown -R "$TARGET_USER" "$SSH_DIR"
  sudo chmod 700 "$SSH_DIR"

  update_authorized_keys "${SSH_DIR}/authorized_keys" "$KEYS"
  sudo chown "$TARGET_USER" "${SSH_DIR}/authorized_keys"
}

while [ "$#" -gt 0 ]
do
  case "$1" in
    -u|--user)
      GITHUB_USER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

trap start_sshd EXIT

KEYS=$(fetch_keys)
if [ -z "$KEYS" ]
then
  echo "Failed to fetch SSH keys for $GITHUB_USER." >&2
  exit 1
fi

setup_keys "$USER"
setup_keys root
