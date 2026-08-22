use anyhow::{Context, Result};
use metrics::{counter, histogram};
use metrics_exporter_prometheus::PrometheusBuilder;

/// Puerto donde se expone el endpoint /metrics.
const METRICS_PORT: u16 = 9091;

/// Inicializar el exporter HTTP de Prometheus.
pub fn init_metrics() -> Result<()> {
    PrometheusBuilder::new()
        .with_http_listener(([0, 0, 0, 0], METRICS_PORT))
        .install()
        .context("No se pudo iniciar el exporter de Prometheus")?;

    println!(
        "[METRICS] Prometheus exporter activo en 0.0.0.0:{}",
        METRICS_PORT
    );

    Ok(())
}

/// Registrar un bloque QRNG publicado.
pub fn record_qrng_block_published(source: &str) {
    counter!(
        "qeaas_qrng_blocks_published_total",
        "source" => source.to_string()
    )
    .increment(1);
}

/// Registrar tiempo necesario para obtener un bloque QRNG.
pub fn record_qrng_fetch_duration(source: &str, duration_seconds: f64) {
    histogram!(
        "qeaas_qrng_fetch_duration_seconds",
        "source" => source.to_string()
    )
    .record(duration_seconds);
}