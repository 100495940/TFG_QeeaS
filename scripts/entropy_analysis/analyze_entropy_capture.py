#!/usr/bin/env python3
"""
Analisis estadistico de archivos binarios de entropia para QeeaS / ESP32-C6.

Uso:
    python3 scripts/entropy_analysis/analyze_entropy_capture.py data/captures/blake2s --experiment blake2s

Tambien acepta un unico archivo:
    python3 scripts/entropy_analysis/analyze_entropy_capture.py data/captures/blake2s/entropy_final_active.bin --experiment blake2s
"""

from __future__ import annotations

import argparse
import json
import math
import zlib
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

try:
    from scipy.special import erfc
    from scipy.stats import chisquare
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

BLOCK_SIZE = 32
BYTE_VALUES = 256

def load_bytes(path: Path) -> np.ndarray:
    # Leer archivo binario y convertirlo a un array de bytes (uint8)
    data = path.read_bytes()

    if not data:
        raise ValueError(f"El archivo esta vacio: {path}")

    return np.frombuffer(data, dtype=np.uint8)

def shannon_entropy(probabilities: np.ndarray) -> float:
    # Calcular la entropia de Shannon a partir de un array de probabilidades
    # Mide cuánta incertidumbre media hay por byte
    # El máximo ideal es 8 bits/byte (distribución uniforme)
    non_zero = probabilities[probabilities > 0]
    return float(-np.sum(non_zero * np.log2(non_zero)))

def min_entropy(probabilities: np.ndarray) -> float:
    # Calcular la min-entropia a partir de un array de probabilidades
    # Mide cuánto domina el valor más repetido en la distribución
    # El máximo ideal es 8 bits/byte (distribución uniforme)
    max_probability = float(np.max(probabilities))

    if max_probability <= 0:
        return 0.0

    return float(-math.log2(max_probability))

def byte_chi_square(byte_array: np.ndarray) -> tuple[float, float | None]:
    # Calcular cuántas veces aparece cada byte y comparar con una distribución uniforme ideal
    # Mide si los 256 valores de byte aparecen con la misma frecuencia
    counts = np.bincount(byte_array, minlength=BYTE_VALUES)
    expected = len(byte_array) / BYTE_VALUES

    statistic = float(np.sum((counts - expected) ** 2 / expected))

    if SCIPY_AVAILABLE:
        expected_array = np.full(BYTE_VALUES, expected)
        scipy_statistic, p_value = chisquare(counts, expected_array)
        return float(scipy_statistic), float(p_value)

    return statistic, None

def bit_balance(byte_array: np.ndarray) -> dict[str, int | float]:
    # Convertir bytes a bits y contar cuántos ceros y unos hay, así como sus proporciones
    bits = np.unpackbits(byte_array)

    ones = int(np.sum(bits))
    zeros = int(bits.size - ones)
    total = int(bits.size)

    return {
        "bit_count": total,
        "zeros": zeros,
        "ones": ones,
        "zeros_ratio": zeros / total if total > 0 else 0.0,
        "ones_ratio": ones / total if total > 0 else 0.0,
    }

def erfc_value(x: float) -> float:
    if SCIPY_AVAILABLE:
        return float(erfc(x))
    return float(math.erfc(x))

def monobit_test(byte_array: np.ndarray) -> dict[str, float]:
    # Calcular equilibrio de 0 y 1, si hay equilibrio la suma de valores debe ser cercana a 0
    bits = np.unpackbits(byte_array)

    if bits.size == 0:
        return {
            "monobit_s_obs": 0.0,
            "monobit_p_value": 0.0,
        }

    signed_bits = 2 * bits.astype(np.int16) - 1
    s_n = int(np.sum(signed_bits))
    s_obs = abs(s_n) / math.sqrt(bits.size)
    p_value = erfc_value(s_obs / math.sqrt(2.0))

    return {
        "monobit_s_obs": float(s_obs),
        "monobit_p_value": float(p_value),
    }

def runs_test(byte_array: np.ndarray) -> dict[str, int | float | bool]:
    # Evaluar si los 0 y 1 se alternan de forman razonable y sin agrupamientos excesivos
    bits = np.unpackbits(byte_array)
    n = bits.size

    if n < 2:
        return {
            "runs_count": 0,
            "runs_p_value": 0.0,
            "runs_applicable": False,
        }

    pi = float(np.mean(bits))

    # El test de runs solo es aplicable si el balance de bits no esta
    # demasiado lejos de 0.5.
    threshold = 2.0 / math.sqrt(n)

    if abs(pi - 0.5) >= threshold:
        return {
            "runs_count": 0,
            "runs_p_value": 0.0,
            "runs_applicable": False,
        }

    runs = 1 + int(np.sum(bits[1:] != bits[:-1]))

    numerator = abs(runs - 2.0 * n * pi * (1.0 - pi))
    denominator = 2.0 * math.sqrt(2.0 * n) * pi * (1.0 - pi)

    p_value = erfc_value(numerator / denominator)

    return {
        "runs_count": int(runs),
        "runs_p_value": float(p_value),
        "runs_applicable": True,
    }

def lag1_autocorrelation(values: np.ndarray) -> float:
    # Calcular la autocorrelación entre cada valor y el siguiente
    # Mide si un byte depende del byte anterior
    if values.size < 2:
        return 0.0

    x = values[:-1].astype(np.float64)
    y = values[1:].astype(np.float64)

    if np.std(x) == 0 or np.std(y) == 0:
        return 0.0

    return float(np.corrcoef(x, y)[0, 1])

def bit_lag1_autocorrelation(byte_array: np.ndarray) -> float:
    # Convertir bytes a bits y calcular la autocorrelación entre cada bit y el siguiente
    bits = np.unpackbits(byte_array)
    return lag1_autocorrelation(bits)

def repeated_blocks(byte_array: np.ndarray, block_size: int = BLOCK_SIZE) -> dict[str, int]:
    # Dividir el archivo en bloques de 32 bytes y cuenta cuántos bloques se repiten
    usable_len = (len(byte_array) // block_size) * block_size

    if usable_len == 0:
        return {
            "block_size": block_size,
            "total_blocks": 0,
            "unique_blocks": 0,
            "repeated_blocks": 0,
        }

    raw = byte_array[:usable_len].tobytes()
    blocks = [raw[i:i + block_size] for i in range(0, usable_len, block_size)]

    total_blocks = len(blocks)
    unique_blocks = len(set(blocks))

    return {
        "block_size": block_size,
        "total_blocks": total_blocks,
        "unique_blocks": unique_blocks,
        "repeated_blocks": total_blocks - unique_blocks,
    }

def longest_repeated_byte_run(byte_array: np.ndarray) -> int:
    # Buscar la racha más larga de bytes repetidos consecutivos
    if len(byte_array) == 0:
        return 0

    longest = 1
    current = 1

    for i in range(1, len(byte_array)):
        if byte_array[i] == byte_array[i - 1]:
            current += 1
            longest = max(longest, current)
        else:
            current = 1

    return int(longest)

def compression_ratio(byte_array: np.ndarray) -> float:
    # Comprimir el archivo con zlib y calcular la relación de compresión
    raw = byte_array.tobytes()

    if len(raw) == 0:
        return 0.0

    compressed = zlib.compress(raw)

    return len(compressed) / len(raw)

def windowed_shannon(byte_array: np.ndarray, window_size: int) -> list[float]:
    # Dividir el archivo en ventanas de tamaño fijo y calcular la entropia de Shannon para cada ventana
    values: list[float] = []

    for start in range(0, len(byte_array), window_size):
        window = byte_array[start:start + window_size]

        if len(window) < window_size:
            continue

        counts = np.bincount(window, minlength=BYTE_VALUES)
        probabilities = counts / len(window)
        values.append(shannon_entropy(probabilities))

    return values

def lag_autocorrelations(byte_array: np.ndarray, max_lag: int) -> pd.DataFrame:
    # Calcular la autocorrelación para varios lags (desplazamientos) y devolver un DataFrame
    values = byte_array.astype(np.float64)
    rows = []

    for lag in range(1, max_lag + 1):
        if len(values) <= lag:
            break

        x = values[:-lag]
        y = values[lag:]

        if np.std(x) == 0 or np.std(y) == 0:
            corr = 0.0
        else:
            corr = float(np.corrcoef(x, y)[0, 1])

        rows.append({"lag": lag, "autocorrelation": corr})

    return pd.DataFrame(rows)

def make_histogram(byte_array: np.ndarray, output_path: Path, title: str) -> None:
    # Generar gráfica con la frecuencia de cada byte del 0 al 255
    counts = np.bincount(byte_array, minlength=BYTE_VALUES)

    plt.figure(figsize=(12, 6))
    plt.bar(np.arange(BYTE_VALUES), counts)
    plt.title(title)
    plt.xlabel("Valor del byte")
    plt.ylabel("Frecuencia")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()

def make_windowed_shannon_plot(values: list[float], output_path: Path, title: str) -> None:
    # Generar gráfica con la entropia de Shannon por ventana
    if not values:
        return

    x = np.arange(1, len(values) + 1)

    plt.figure(figsize=(12, 6))
    plt.plot(x, values, marker="o", linewidth=1)
    plt.axhline(8.0, linestyle="--", linewidth=1)
    plt.title(title)
    plt.xlabel("Ventana")
    plt.ylabel("Entropia de Shannon (bits/byte)")
    plt.ylim(0, 8.1)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()

def make_autocorrelation_plot(corr_df: pd.DataFrame, output_path: Path, title: str) -> None:
    # Generar gráfica con la autocorrelación de bytes para varios lags
    if corr_df.empty:
        return

    plt.figure(figsize=(12, 6))
    plt.plot(corr_df["lag"], corr_df["autocorrelation"], marker="o", linewidth=1)
    plt.axhline(0.0, linestyle="--", linewidth=1)
    plt.title(title)
    plt.xlabel("Lag")
    plt.ylabel("Autocorrelacion")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()

def format_optional_float(value: Any, digits: int = 8) -> str:
    # Formateo valores númericos
    if value is None:
        return "NA"
    return f"{float(value):.{digits}f}"

def analyze_entropy_file(
    input_path: Path,
    output_dir: Path,
    label: str,
    window_size: int,
    max_lag: int,) -> dict[str, Any]:
    byte_array = load_bytes(input_path)

    counts = np.bincount(byte_array, minlength=BYTE_VALUES)
    probabilities = counts / len(byte_array)

    shannon = shannon_entropy(probabilities)
    min_ent = min_entropy(probabilities)
    chi_stat, chi_p = byte_chi_square(byte_array)
    bit_stats = bit_balance(byte_array)
    monobit_stats = monobit_test(byte_array)
    runs_stats = runs_test(byte_array)
    block_stats = repeated_blocks(byte_array, BLOCK_SIZE)
    window_values = windowed_shannon(byte_array, window_size)
    autocorr_df = lag_autocorrelations(byte_array, max_lag)

    most_frequent_byte = int(np.argmax(counts))
    most_frequent_count = int(np.max(counts))
    most_frequent_probability = most_frequent_count / len(byte_array)

    metrics: dict[str, Any] = {
        "label": label,
        "file": str(input_path),
        "bytes": int(len(byte_array)),
        "blocks_32b": int(len(byte_array) // BLOCK_SIZE),
        "trailing_bytes": int(len(byte_array) % BLOCK_SIZE),
        "unique_byte_values": int(np.count_nonzero(counts)),
        "shannon_bits_per_byte": shannon,
        "min_entropy_bits_per_byte": min_ent,
        "chi_square": chi_stat,
        "chi_square_p_value": chi_p,
        "bit_count": bit_stats["bit_count"],
        "zeros": bit_stats["zeros"],
        "ones": bit_stats["ones"],
        "zeros_ratio": bit_stats["zeros_ratio"],
        "ones_ratio": bit_stats["ones_ratio"],
        "monobit_s_obs": monobit_stats["monobit_s_obs"],
        "monobit_p_value": monobit_stats["monobit_p_value"],
        "runs_count": runs_stats["runs_count"],
        "runs_p_value": runs_stats["runs_p_value"],
        "runs_applicable": runs_stats["runs_applicable"],
        "byte_autocorrelation_lag1": lag1_autocorrelation(byte_array),
        "bit_autocorrelation_lag1": bit_lag1_autocorrelation(byte_array),
        "block_size": block_stats["block_size"],
        "total_blocks": block_stats["total_blocks"],
        "unique_blocks": block_stats["unique_blocks"],
        "repeated_blocks": block_stats["repeated_blocks"],
        "longest_repeated_byte_run": longest_repeated_byte_run(byte_array),
        "most_frequent_byte": most_frequent_byte,
        "most_frequent_count": most_frequent_count,
        "most_frequent_probability": most_frequent_probability,
        "zlib_compression_ratio": compression_ratio(byte_array),
        "window_size": window_size,
        "window_count": len(window_values),
        "window_shannon_min": float(np.min(window_values)) if window_values else None,
        "window_shannon_mean": float(np.mean(window_values)) if window_values else None,
        "window_shannon_max": float(np.max(window_values)) if window_values else None,
        "scipy_available": SCIPY_AVAILABLE,
    }

    output_dir.mkdir(parents=True, exist_ok=True)

    report_path = output_dir / f"{label}_report.txt"
    json_path = output_dir / f"{label}_metrics.json"
    histogram_path = output_dir / f"{label}_histogram.png"
    window_plot_path = output_dir / f"{label}_windowed_shannon.png"
    autocorr_path = output_dir / f"{label}_byte_autocorrelation.png"
    autocorr_csv_path = output_dir / f"{label}_byte_autocorrelation.csv"
    byte_counts_csv_path = output_dir / f"{label}_byte_counts.csv"

    byte_counts_df = pd.DataFrame({
        "byte_value": np.arange(BYTE_VALUES),
        "count": counts,
        "probability": probabilities,
    })
    byte_counts_df.to_csv(byte_counts_csv_path, index=False)

    if not autocorr_df.empty:
        autocorr_df.to_csv(autocorr_csv_path, index=False)

    with report_path.open("w", encoding="utf-8") as f:
        f.write("============================================================\n")
        f.write(" REPORTE DE ENTROPIA - QEEAS / ESP32-C6\n")
        f.write("============================================================\n\n")

        f.write(f"Etiqueta                         : {metrics['label']}\n")
        f.write(f"Archivo                          : {metrics['file']}\n")
        f.write(f"Bytes analizados                 : {metrics['bytes']}\n")
        f.write(f"Bloques completos de 32 bytes    : {metrics['blocks_32b']}\n")
        f.write(f"Bytes sobrantes                  : {metrics['trailing_bytes']}\n")
        f.write(f"Valores byte unicos              : {metrics['unique_byte_values']}/256\n\n")

        f.write("DISTRIBUCION DE BYTES\n")
        f.write("------------------------------------------------------------\n")
        f.write(f"Entropia de Shannon              : {metrics['shannon_bits_per_byte']:.8f} bits/byte\n")
        f.write(f"Min-entropia empirica            : {metrics['min_entropy_bits_per_byte']:.8f} bits/byte\n")
        f.write(f"Chi-cuadrado                     : {metrics['chi_square']:.4f}\n")
        f.write(f"p-value chi-cuadrado             : {format_optional_float(metrics['chi_square_p_value'])}\n")
        f.write(f"Byte mas frecuente               : {metrics['most_frequent_byte']}\n")
        f.write(f"Frecuencia byte mas frecuente    : {metrics['most_frequent_count']}\n")
        f.write(f"Probabilidad byte mas frecuente  : {metrics['most_frequent_probability']:.8f}\n\n")

        f.write("BALANCE Y TESTS SOBRE BITS\n")
        f.write("------------------------------------------------------------\n")
        f.write(f"Bits analizados                  : {metrics['bit_count']}\n")
        f.write(f"Ceros                            : {metrics['zeros']}\n")
        f.write(f"Unos                             : {metrics['ones']}\n")
        f.write(f"Proporcion ceros                 : {metrics['zeros_ratio']:.8f}\n")
        f.write(f"Proporcion unos                  : {metrics['ones_ratio']:.8f}\n")
        f.write(f"Monobit S_obs                    : {metrics['monobit_s_obs']:.8f}\n")
        f.write(f"Monobit p-value                  : {metrics['monobit_p_value']:.8f}\n")
        f.write(f"Runs aplicable                   : {metrics['runs_applicable']}\n")
        f.write(f"Runs count                       : {metrics['runs_count']}\n")
        f.write(f"Runs p-value                     : {metrics['runs_p_value']:.8f}\n\n")

        f.write("DEPENDENCIA Y REPETICIONES\n")
        f.write("------------------------------------------------------------\n")
        f.write(f"Autocorrelacion bytes lag-1      : {metrics['byte_autocorrelation_lag1']:.10f}\n")
        f.write(f"Autocorrelacion bits lag-1       : {metrics['bit_autocorrelation_lag1']:.10f}\n")
        f.write(f"Bloques totales de 32 bytes      : {metrics['total_blocks']}\n")
        f.write(f"Bloques unicos de 32 bytes       : {metrics['unique_blocks']}\n")
        f.write(f"Bloques repetidos de 32 bytes    : {metrics['repeated_blocks']}\n")
        f.write(f"Mayor racha del mismo byte       : {metrics['longest_repeated_byte_run']}\n")
        f.write(f"Ratio compresion zlib            : {metrics['zlib_compression_ratio']:.8f}\n\n")

        f.write("ESTABILIDAD TEMPORAL\n")
        f.write("------------------------------------------------------------\n")
        f.write(f"Tamanho ventana                  : {metrics['window_size']} bytes\n")
        f.write(f"Numero ventanas completas        : {metrics['window_count']}\n")

        if metrics["window_count"] > 0:
            f.write(f"Shannon ventana minimo           : {metrics['window_shannon_min']:.8f}\n")
            f.write(f"Shannon ventana media            : {metrics['window_shannon_mean']:.8f}\n")
            f.write(f"Shannon ventana maximo           : {metrics['window_shannon_max']:.8f}\n")

        f.write("\nARCHIVOS GENERADOS\n")
        f.write("------------------------------------------------------------\n")
        f.write(f"Metricas JSON                    : {json_path}\n")
        f.write(f"Histograma                       : {histogram_path}\n")
        f.write(f"Shannon por ventanas             : {window_plot_path}\n")
        f.write(f"Autocorrelacion                  : {autocorr_path}\n")
        f.write(f"Frecuencias por byte CSV         : {byte_counts_csv_path}\n")
        f.write("\n============================================================\n")

    json_path.write_text(json.dumps(metrics, indent=4), encoding="utf-8")

    make_histogram(byte_array, histogram_path, f"Distribucion de bytes - {label}")
    make_windowed_shannon_plot(window_values, window_plot_path, f"Entropia de Shannon por ventanas - {label}")
    make_autocorrelation_plot(autocorr_df, autocorr_path, f"Autocorrelacion de bytes - {label}")

    print(f"[OK] {label}: reporte -> {report_path}")
    print(f"[OK] {label}: metricas -> {json_path}")
    print(f"[OK] {label}: histograma -> {histogram_path}")

    if window_values:
        print(f"[OK] {label}: ventanas -> {window_plot_path}")

    if not autocorr_df.empty:
        print(f"[OK] {label}: autocorrelacion -> {autocorr_path}")

    return metrics

def discover_bin_files(input_path: Path) -> list[Path]:
    if input_path.is_file():
        return [input_path]

    if input_path.is_dir():
        return sorted(input_path.glob("*.bin"))

    raise FileNotFoundError(f"No existe la ruta: {input_path}")

def label_from_path(path: Path) -> str:
    label = path.stem

    if label.startswith("entropy_"):
        label = label[len("entropy_"):]

    return label

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analiza archivos binarios de entropia capturados desde QeeaS/ESP32-C6."
    )

    parser.add_argument("input", type=Path, help="Archivo .bin o carpeta con archivos .bin")
    parser.add_argument("--experiment", default=None, help="Nombre del experimento")
    parser.add_argument("--output-root", type=Path, default=Path("data/reports"))
    parser.add_argument("--window-size", type=int, default=32768)
    parser.add_argument("--max-lag", type=int, default=32)

    args = parser.parse_args()

    input_path = args.input

    if args.experiment is not None:
        experiment = args.experiment
    elif input_path.is_dir():
        experiment = input_path.name
    else:
        experiment = input_path.parent.name

    output_dir = args.output_root / experiment
    output_dir.mkdir(parents=True, exist_ok=True)

    bin_files = discover_bin_files(input_path)

    if not bin_files:
        raise ValueError(f"No se encontraron archivos .bin en {input_path}")

    print("============================================================")
    print(" ANALISIS DE ENTROPIA - QEEAS / ESP32-C6")
    print("============================================================")
    print(f"Entrada     : {input_path}")
    print(f"Experimento : {experiment}")
    print(f"Salida      : {output_dir}")
    print(f"Archivos    : {len(bin_files)}")
    print(f"SciPy       : {'disponible' if SCIPY_AVAILABLE else 'no disponible'}")
    print("============================================================\n")

    all_metrics = []

    for bin_file in bin_files:
        label = label_from_path(bin_file)
        metrics = analyze_entropy_file(
            bin_file,
            output_dir,
            label,
            args.window_size,
            args.max_lag,
        )
        all_metrics.append(metrics)
        print()

    summary_path = output_dir / "entropy_metrics_summary.csv"
    summary_json_path = output_dir / "entropy_metrics_summary.json"

    df = pd.DataFrame(all_metrics)
    df.to_csv(summary_path, index=False)
    summary_json_path.write_text(json.dumps(all_metrics, indent=4), encoding="utf-8")

    key_columns = [
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
        "repeated_blocks",
        "zlib_compression_ratio",
    ]

    printable_columns = [col for col in key_columns if col in df.columns]

    print("============================================================")
    print("[OK] ANALISIS COMPLETADO")
    print("============================================================")
    print(f"CSV resumen : {summary_path}")
    print(f"JSON resumen: {summary_json_path}")
    print("------------------------------------------------------------")
    print(df[printable_columns].to_string(index=False))
    print("============================================================")

if __name__ == "__main__":
    main()
