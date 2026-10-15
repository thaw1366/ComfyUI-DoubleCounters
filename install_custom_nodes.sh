#!/usr/bin/env bash
# Run synchronously BEFORE ComfyUI starts. Requires bash and git.
# Host this .sh file at a public direct-download URL; no API keys are needed.
set -Eeuo pipefail
trap 'echo "[custom-nodes] FAILED at line $LINENO. See the error above." >&2' ERR
export GIT_TERMINAL_PROMPT=0

# Edit this list to add or remove public custom-node repositories.
NODE_REPOS=(
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/crystian/ComfyUI-Crystools.git"
    "https://github.com/jags111/efficiency-nodes-comfyui.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/TinyTerra/ComfyUI_tinyterraNodes.git"
    "https://github.com/ltdrdata/was-node-suite-comfyui.git"
    "https://github.com/alexopus/ComfyUI-Image-Saver.git"
    "https://github.com/HellerCommaA/ComfyUI-MetadataStripper.git"
    "https://github.com/thaw1366/ComfyUI-DoubleCounters.git" # User-built custom node
    "https://github.com/willmiao/ComfyUI-Lora-Manager.git"
)

# Optional overrides: set these in your pod environment or edit here.
# COMFYUI_DIR=/workspace/madapps/ComfyUI
# COMFYUI_PYTHON=/workspace/madapps/ComfyUI/.venv/bin/python
# Existing repositories stay at their current version by default.
UPDATE_NODES="${UPDATE_NODES:-0}"
[[ "$UPDATE_NODES" == 0 || "$UPDATE_NODES" == 1 ]] || {
    echo "UPDATE_NODES must be 0 or 1" >&2; exit 1;
}

if (( ${#NODE_REPOS[@]} == 0 )); then
    echo "[custom-nodes] No repositories configured; skipping."
    exit 0
fi

# YAW runs setup after moving ComfyUI to its network volume.
if [[ -n "${YAW_NODE_MANIFESTS:-}" ]]; then
    COMFYUI_DIR="${COMFYUI_DIR:-${YAW_NETWORK_VOLUME:-/workspace}/ComfyUI}"
    [[ -d "${YAW_NETWORK_VOLUME:-/workspace}" ]] || COMFYUI_DIR=/ComfyUI
    COMFYUI_PYTHON="${COMFYUI_PYTHON:-python3}"
fi

if [[ -z "${COMFYUI_DIR:-}" ]]; then
    for candidate in /ComfyUI /workspace/madapps/ComfyUI /workspace/ComfyUI /app/ComfyUI; do
        if [[ -f "$candidate/main.py" && -d "$candidate/custom_nodes" ]]; then
            COMFYUI_DIR="$candidate"
            break
        fi
    done
fi
if [[ -z "${COMFYUI_DIR:-}" || ! -f "$COMFYUI_DIR/main.py" ]]; then
    echo "[custom-nodes] Set COMFYUI_DIR to your ComfyUI installation." >&2
    exit 1
fi
COMFYUI_DIR="$(cd "$COMFYUI_DIR" && pwd)"

if [[ -z "${COMFYUI_PYTHON:-}" ]]; then
    if [[ -n "${VIRTUAL_ENV:-}" && -x "$VIRTUAL_ENV/bin/python" ]]; then
        COMFYUI_PYTHON="$VIRTUAL_ENV/bin/python"
    else
        for candidate in "$COMFYUI_DIR/.venv/bin/python" "$COMFYUI_DIR/venv/bin/python" /workspace/madapps/venv/bin/python /opt/venv/bin/python; do
            if [[ -x "$candidate" ]]; then
                COMFYUI_PYTHON="$candidate"
                break
            fi
        done
    fi
fi
COMFYUI_PYTHON="${COMFYUI_PYTHON:-python3}"
command -v git >/dev/null
"$COMFYUI_PYTHON" -m pip --version
echo "[custom-nodes] ComfyUI: $COMFYUI_DIR"
echo "[custom-nodes] Python: $COMFYUI_PYTHON (must match ComfyUI's launcher)"
mkdir -p "$COMFYUI_DIR/custom_nodes"

# ComfyUI Manager reads these from config.ini, not environment variables.
# Default to enabling Git URL installs for this user's remote RunPod pod.
ENABLE_MANAGER_GIT_URL_INSTALL="${ENABLE_MANAGER_GIT_URL_INSTALL:-1}"
[[ "$ENABLE_MANAGER_GIT_URL_INSTALL" == 0 || "$ENABLE_MANAGER_GIT_URL_INSTALL" == 1 ]] || {
    echo "ENABLE_MANAGER_GIT_URL_INSTALL must be 0 or 1" >&2; exit 1;
}
if [[ "$ENABLE_MANAGER_GIT_URL_INSTALL" == 1 ]]; then
    manager_config="$COMFYUI_DIR/user/__manager/config.ini"
    legacy_manager_config="$COMFYUI_DIR/user/default/ComfyUI-Manager/config.ini"
    if [[ -f "$legacy_manager_config" && ! -f "$manager_config" ]]; then
        manager_config="$legacy_manager_config"
    fi
    mkdir -p "$(dirname "$manager_config")"
    "$COMFYUI_PYTHON" - "$manager_config" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
settings = {
    "allow_git_url_install": "true",
    "network_mode": "personal_cloud",
}
out = []
in_default = False
found_default = False
seen = set()

def append_missing():
    for key, value in settings.items():
        if key not in seen:
            out.append(f"{key} = {value}")
            seen.add(key)

for line in lines:
    section = re.match(r"^\s*\[([^]]+)\]", line)
    if section:
        if in_default:
            append_missing()
        in_default = section.group(1).strip().lower() == "default"
        found_default = found_default or in_default
        out.append(line)
        continue
    if in_default:
        setting = re.match(r"^(\s*)(allow_git_url_install|network_mode)(\s*=).*$", line, re.I)
        if setting:
            key = setting.group(2).lower()
            out.append(f"{setting.group(1)}{key}{setting.group(3)} {settings[key]}")
            seen.add(key)
            continue
    out.append(line)

if in_default:
    append_missing()
elif not found_default:
    if out and out[-1].strip():
        out.append("")
    out.extend(["[default]", "allow_git_url_install = true", "network_mode = personal_cloud"])

path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print(f"[custom-nodes] Enabled Manager Git URL installs in {path}")
PY
fi

for repo in "${NODE_REPOS[@]}"; do
    [[ "$repo" == https://* && "$repo" != *'?'* && "$repo" != *'#'* ]] || {
        echo "[custom-nodes] Use an HTTPS Git repository URL without query/fragment." >&2
        exit 1
    }
    name="${repo##*/}"
    name="${name%.git}"
    [[ "$name" =~ ^[a-zA-Z0-9_-][a-zA-Z0-9._-]*$ ]] || {
        echo "[custom-nodes] Invalid repository folder name." >&2; exit 1;
    }
    # YAW's launcher verifies these pinned nodes again after this script.
    # Keep their code and dependencies under the template's control.
    locked=false
    read -r -a manifests <<< "${YAW_NODE_MANIFESTS:-}"
    for manifest in "${manifests[@]}"; do
        [[ -r "$manifest" ]] || { echo "Unreadable lock manifest: $manifest" >&2; exit 1; }
        while read -r locked_repo locked_ref extra; do
            case "$locked_repo" in ''|'#'*) continue ;; esac
            locked_name="${locked_repo##*/}"
            locked_name="${locked_name%.git}"
            if [[ "${locked_name,,}" == "${name,,}" ]]; then
                locked=true
                break
            fi
        done < "$manifest"
        [[ "$locked" == true ]] && break
    done
    if [[ "$locked" == true && "$name" != "ComfyUI-DoubleCounters" ]]; then
        echo "[custom-nodes] $name is managed by YAW; preserving its pinned installation."
        continue
    fi
    destination="$COMFYUI_DIR/custom_nodes/$name"
    if [[ -e "$destination" || -L "$destination" ]]; then
        [[ -d "$destination/.git" ]] || {
            echo "[custom-nodes] $destination exists but is not a Git clone; refusing to overwrite." >&2
            exit 1
        }
        origin="$(git -C "$destination" remote get-url origin)"
        [[ "${origin%.git}" == "${repo%.git}" ]] || {
            echo "[custom-nodes] Repository origin differs for $name; refusing to overwrite." >&2
            exit 1
        }
        # Always refresh the user's node so workflow compatibility fixes are applied.
        if [[ "$UPDATE_NODES" == 1 || "$name" == "ComfyUI-DoubleCounters" ]]; then
            [[ -z "$(git -C "$destination" status --porcelain)" ]] || {
                echo "[custom-nodes] $name has local changes; refusing to update." >&2; exit 1;
            }
            git -C "$destination" pull --ff-only
        else
            echo "[custom-nodes] $name already installed; keeping current version."
        fi
    else
        # Clone to a temporary sibling so interrupted clones do not leave a broken node.
        temporary="$(mktemp -d "$COMFYUI_DIR/custom_nodes/.install-${name}.XXXXXX")"
        if git clone --depth 1 "$repo" "$temporary"; then
            mv "$temporary" "$destination"
        else
            rm -rf -- "$temporary"
            echo "[custom-nodes] Clone failed for $name." >&2
            exit 1
        fi
    fi
    if [[ -f "$destination/requirements.txt" ]]; then
        # Run each startup: persistent nodes can outlive a container's Python environment.
        (cd "$destination" && "$COMFYUI_PYTHON" -m pip install -r requirements.txt)
    fi
    if [[ "$name" == "ComfyUI-Impact-Pack" && -f "$destination/install.py" ]]; then
        (cd "$destination" && COMFYUI_PATH="$COMFYUI_DIR" "$COMFYUI_PYTHON" install.py)
    fi
    # Some nodes also require install.py, system packages, or model downloads.
    # Add their documented extra commands here using COMFYUI_PYTHON for Python.
    echo "[custom-nodes] Ready: $name"
done
echo "[custom-nodes] Finished; the pod launcher can now start ComfyUI."
