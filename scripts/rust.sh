#!/usr/bin/env bash

set -euo pipefail

bash scripts/rust_build.sh
bash scripts/rust_run.sh