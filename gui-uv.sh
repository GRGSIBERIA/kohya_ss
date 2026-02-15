#!/usr/bin/env bash
export VIRTUAL_ENV=.venv

env_var_exists() {
  if [[ -n "${!1}" ]]; then
    return 0
  else
    return 1
  fi
}

lib_path="/usr/lib/wsl/lib/"

if [ -d "$lib_path" ]; then
    if [ -z "${LD_LIBRARY_PATH}" ]; then
        export LD_LIBRARY_PATH="$lib_path"
    fi
fi

if [ -n "$SUDO_USER" ] || [ -n "$SUDO_COMMAND" ]; then
    echo "The sudo command resets the non-essential environment variables, we keep the LD_LIBRARY_PATH variable."
    export LD_LIBRARY_PATH=$(sudo -i printenv LD_LIBRARY_PATH)
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1

# Check if --quiet is in the arguments
uv_quiet=""
args=()
for arg in "$@"; do
  if [[ "$arg" == "--quiet" ]]; then
    uv_quiet="--quiet"
  else
    args+=("$arg")
  fi
done

if ! command -v uv &> /dev/null; then
  read -p "uv is not installed. We can try to install it for you, or you can install it manually from https://astral.sh/uv before running this script again. Would you like to attempt automatic installation now? [Y/n]: " install_uv
  if [[ "$install_uv" =~ ^[Yy]$ ]]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.local/bin/env
  else
    echo "Okay, please install uv manually from https://astral.sh/uv and then re-run this script. Exiting."
    exit 1
  fi
fi

if [[ "$uv_quiet" == "--quiet" ]]; then
  echo "Notice: uv will run in quiet mode. No indication of the uv module download and install process will be displayed."
fi

ensure_xformers_for_aarch64() {
  local os_name
  local arch_name
  os_name=$(uname -s)
  arch_name=$(uname -m)

  if [[ "$os_name" != "Linux" || "$arch_name" != "aarch64" ]]; then
    return 0
  fi

  echo "Linux aarch64 detected. Checking xformers availability..."

  if uv run $uv_quiet python -c "import xformers; import xformers.ops" >/dev/null 2>&1; then
    echo "xformers is already available. Skipping source build."
    return 0
  fi

  echo "xformers wheel for aarch64 is typically unavailable. Building xformers from source..."

  if [[ -z "${MAX_JOBS}" ]]; then
    export MAX_JOBS=$(nproc)
  fi

  uv run $uv_quiet python -m pip install --upgrade pip setuptools wheel ninja cmake || return 1
  uv run $uv_quiet python -m pip install --no-binary xformers xformers==0.0.30 || return 1

  if uv run $uv_quiet python -c "import xformers; import xformers.ops" >/dev/null 2>&1; then
    echo "xformers build/install completed successfully."
  else
    echo "Failed to validate xformers after installation attempt."
    return 1
  fi
}

git submodule update --init --recursive
ensure_xformers_for_aarch64
uv run $uv_quiet kohya_gui.py --noverify "${args[@]}"
