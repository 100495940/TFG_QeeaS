use anyhow::{Context, Result};
use metrics::{counter, histogram};
use metrics_exporter_prometheus::PrometheusBuilder;

// Puerto donde se expone el endpoint /metrics.
const METRICS_PORT: u16 = 9091;

// Inicializar métricas que en principio deben tener valores a 0
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

    counter!(
        "qeaas_ack_timeouts_total"
    )
    .absolute(0);
}

// Inicializar el exporter HTTP de Prometheus.
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

// Registrar número de bloques que nunca hacen ack
pub fn record_ack_timeout() {
    counter!(
        "qeaas_ack_timeouts_total"
    )
    .increment(1);
}

// Registrar número total de bloques acknowledged
pub fn record_block_acknowledged() {
    counter!(
        "qeaas_qrng_blocks_acknowledged_total"
    )
    .increment(1);
}

// Registrar número de ciclos del microcontrolador para sacar la salida final híbrida
pub fn record_esp32_final_active_entropy_duration(us: u32) {
    histogram!(
        "qeaas_esp32_final_active_entropy_duration_seconds"
    )
    .record(us as f64 / 1_000_000.0);
}

// Registrar número de ciclos del microcontrolador para sacar TRNG
pub fn record_esp32_trng_duration(us: u32) {
    histogram!(
        "qeaas_esp32_trng_duration_seconds"
    )
    .record(us as f64 / 1_000_000.0);
}

// Registrar número de ciclos del microcontrolador para realizar XOR
pub fn record_esp32_xor_duration(us: u32) {
    histogram!(
        "qeaas_esp32_xor_duration_seconds"
    )
    .record(us as f64 / 1_000_000.0);
}

// Registrar variación entre dos RTT consecutivos (jitter)
pub fn record_e2e_jitter(seconds: f64) {
    histogram!(
        "qeaas_e2e_jitter_seconds"
    )
    .record(seconds);
}

// Registrar tiempo en completar flujo completo
pub fn record_e2e_rtt(seconds: f64) {
    histogram!(
        "qeaas_e2e_rtt_seconds"
    )
    .record(seconds);
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