use anyhow::{Context, Result};
use metrics::{counter, histogram};
use metrics_exporter_prometheus::PrometheusBuilder;

/// Puerto donde se expone el endpoint /metrics.
const METRICS_PORT: u16 = 9091;

// Inicializamos métricas que en principio deben tener valores a 0
fn initialize_metrics() {
    counter!(
        "qeaas_qrng_total_error_requests",
        "source" => "qeaas"
    )
    .absolute(0);

    counter!(
        "qeaas_zenoh_publish_errors_total"
    )
    .absolute(0);
}

/// Inicializar el exporter HTTP de Prometheus.
pub fn init_metrics() -> Result<()> {
    PrometheusBuilder::new()
        .with_http_listener(([0, 0, 0, 0], METRICS_PORT))
        .install()
        .context("No se pudo iniciar el exporter de Prometheus")?;

    initialize_metrics();

    println!(
        "[METRICS] Prometheus exporter activo en 0.0.0.0:{}",
        METRICS_PORT
    );

    Ok(())
}

/// Registrar un bloque QRNG publicado a Zenoh.
pub fn record_qrng_block_published(source: &str) {
    counter!(
        "qeaas_qrng_blocks_published_total",
        "source" => source.to_string()
    )
    .increment(1);
}

/// Registrar número de bytes publicados a Zenoh
pub fn record_qrng_bytes_published(source: &str, bytes: usize) {
    counter!(
        "qeaas_qrng_bytes_published_total",
        "source" => source.to_string()
    )
    .increment(bytes as u64);
}

/// Registrar tiempo necesario para obtener un bloque QRNG de la API
pub fn record_qrng_fetch_duration(source: &str, duration_seconds: f64) {
    histogram!(
        "qeaas_qrng_fetch_duration_seconds",
        "source" => source.to_string()
    )
    .record(duration_seconds);
}

// Registrar número de peticiones a la API
pub fn record_qrng_request(source: &str) {
    counter!(
        "qeaas_qrng_total_requests",
        "source" => source.to_string()
    )
    .increment(1);
}


// Registrar número de peticiones fallidas a la API
pub fn record_qrng_request_errors(source: &str) {
    counter!(
        "qeaas_qrng_total_error_requests",
        "source" => source.to_string()
    )
    .increment(1);
}

// Registrar tiempo en publicar datos en la sesión Zenoh
pub fn record_zenoh_publish_duration(duration_seconds: f64) {
    histogram!(
        "qeaas_zenoh_publish_duration_seconds"
    )
    .record(duration_seconds);
}

// Registrar número de fallos al publicar en la sesión Zenoh
pub fn record_zenoh_publish_error() {
    counter!(
        "qeaas_zenoh_publish_errors_total"
    )
    .increment(1);
}