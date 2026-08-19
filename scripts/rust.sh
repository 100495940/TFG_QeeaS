#!/usr/bin/env bash

set -euo pipefail

bash scripts/rust_build.sh
ENTROPY_EXPERIMENT="$(date +'%H_%M_%d_%m_%Y')" bash scripts/rust_run.sh