#!/usr/bin/env python3
"""
Compara resultados generados por analyze_entropy_capture.py.

Uso:
    python3 scripts/entropy_analysis/compare_entropy_experiments.py \
        data/reports/blake2s/entropy_metrics_summary.csv \
        data/reports/legacy/entropy_metrics_summary.csv \
        --out data/reports/entropy_global_comparison.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

DEFAULT_KEY_COLUMNS = [
    "experiment",
    "label",
    "bytes",
    "blocks_32b",
    "shannon_bits_per_byte",
    "min_entropy_bits_per_byte",
    "chi_square_p_value",
    "ones_ratio",
    "monobit_p_value",
    "runs_p_value",
    "byte_autocorrelation_lag1",
    "bit_autocorrelation_lag1",
    "repeated_blocks",
    "zlib_compression_ratio",
]

def infer_experiment_name(path: Path) -> str:
    if path.parent.name:
        return path.parent.name
    return path.stem

def load_summary(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"No existe el archivo: {path}")

    df = pd.read_csv(path)

    if "experiment" not in df.columns:
        df.insert(0, "experiment", infer_experiment_name(path))

    return df

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Une y compara resumenes estadisticos de varios experimentos QeeaS."
    )

    parser.add_argument("summaries", nargs="+", type=Path, help="Uno o varios entropy_metrics_summary.csv")
    parser.add_argument("--out", type=Path, default=Path("data/reports/entropy_global_comparison.csv"))
    parser.add_argument("--markdown", type=Path, default=Path("data/reports/entropy_global_comparison.md"))

    args = parser.parse_args()

    frames = [load_summary(path) for path in args.summaries]

    if not frames:
        raise ValueError("No se ha cargado ningun resumen.")

    global_df = pd.concat(frames, ignore_index=True)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    global_df.to_csv(args.out, index=False)

    key_columns = [col for col in DEFAULT_KEY_COLUMNS if col in global_df.columns]
    compact_df = global_df[key_columns].copy()

    for col in [
        "shannon_bits_per_byte",
        "min_entropy_bits_per_byte",
        "chi_square_p_value",
        "ones_ratio",
        "monobit_p_value",
        "runs_p_value",
        "byte_autocorrelation_lag1",
        "bit_autocorrelation_lag1",
        "zlib_compression_ratio",
    ]:
        if col in compact_df.columns:
            compact_df[col] = compact_df[col].map(
                lambda x: "NA" if pd.isna(x) else f"{float(x):.8f}"
            )

    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text(compact_df.to_markdown(index=False), encoding="utf-8")

    print("============================================================")
    print("[OK] COMPARATIVA GLOBAL GENERADA")
    print("============================================================")
    print(f"CSV global : {args.out}")
    print(f"Markdown   : {args.markdown}")
    print("------------------------------------------------------------")
    print(compact_df.to_string(index=False))
    print("============================================================")

if __name__ == "__main__":
    main()
