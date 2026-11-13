#!/usr/bin/env bash
# Python handles CIFTI extraction, validation, and projection commands.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "${MSHBM_PYTHON:-python3}" "$script_dir/project_labels.py" "$@"
