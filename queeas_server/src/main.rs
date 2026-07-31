use anyhow::{Context, Result};
use rand::RngCore;
use serde::Deserialize;
use std::env;
use std::time::Duration;
use tokio::time;
use zenoh::config::Config;

const QRNG_TOPIC: &str = "qeeas/qrng/chunk";
const STATUS_TOPIC: &str = "qeeas/esp32/status";
const QRNG_BLOCK_SIZE: usize = 32;
const QEAAS_MAX_BYTES_PER_REQUEST: usize = 8;
const ZENOH_ROUTER_ENDPOINT: &str = "tcp/127.0.0.1:7447";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum QrngSourceMode {
    Auto,
    QeaaS,
    Simulated,
}

impl QrngSourceMode {
    fn from_env() -> Self {
        // Función para leer el modo QRNG desde una variable de entorno
        let mode_str = env::var("QRNG_SOURCE_MODE").unwrap_or_else(|_| "auto".to_string());

        // Comparar el valor con distintos casos posibles
        match mode_str.to_lowercase().as_str() {
            "auto" => Self::Auto,
            "qeaas" => Self::QeaaS,
            "simulated" => Self::Simulated,
            other => {
                eprintln!(
                    "[WARN] Modo de fuente QRNG desconocido: {}. Usando 'auto' por defecto.",
                    other
                );
                Self::Auto
            }
        }
    }

    fn as_str(&self) -> &'static str {
        // Función para convertir un en texto legible
        match self {
            Self::Auto => "auto",
            Self::QeaaS => "qeaas",
            Self::Simulated => "simulated",
        }
    }
}

#[derive(Debug, Deserialize)]
// Estructura para deserializar la respuesta JSON de la API QEaaS
struct QeaaSResponse {
    // Sustituir campo return al ser una palabra reservada en Rust
    #[serde(rename = "return")]
    return_code: u8,
    random_number: Option<u64>,
    error_message: Option<String>,
}

// Función para generar un bloque de QRNG simulado de 32 bytes aleatorios
fn generate_simulated_qrng_block() -> Vec<u8> {
    let mut block = [0u8; QRNG_BLOCK_SIZE];
    rand::thread_rng().fill_bytes(&mut block);
    block.to_vec()
}

// Función asíncrona para obtener un bloque de QRNG desde la API QEaaS
async fn fetch_qeaas_chunk(
    client: &reqwest::Client,
    base_url: &str,
    num_bytes: usize,
) -> Result<Vec<u8>> {
    // Validar que el número de bytes solicitados esté dentro del rango permitido
    if num_bytes == 0 || num_bytes > QEAAS_MAX_BYTES_PER_REQUEST {
        anyhow::bail!(
            "QEaaS solo permite pedir entre 1 y {} bytes por petición",
            QEAAS_MAX_BYTES_PER_REQUEST
        );
    }

    // Construir la URL de la API QEaaS para obtener un número aleatorio
    let url = format!(
        "{}/random_number/{}",
        base_url.trim_end_matches('/'),
        num_bytes
    );

    // Constuir la petición HTTP GET
    let response = client
        .get(&url)
        .send()
        .await
        .with_context(|| format!("No se pudo contactar con QEaaS en {}", url))?
        .error_for_status()
        .with_context(|| format!("QEaaS devolvió un estado HTTP de error en {}", url))?
        .json::<QeaaSResponse>()
        .await
        .with_context(|| format!("No se pudo parsear la respuesta JSON de QEaaS en {}", url))?;

    if response.return_code != 0 {
        anyhow::bail!(
            "QEaaS devolvió error: {}",
            response
                .error_message
                .unwrap_or_else(|| "error desconocido".to_string())
        );
    }

    let random_number = response
        .random_number
        .context("QEaaS no devolvió el campo random_number")?;

    /*
     * El servidor C++ copia los bytes leídos dentro de un uint64_t con memcpy.
     * En el entorno Docker habitual x86_64, eso implica orden little-endian.
     * Por eso reconstruimos los bytes con to_le_bytes() y nos quedamos con
     * los num_bytes solicitados.
     */
    let bytes = random_number.to_le_bytes();

    Ok(bytes[..num_bytes].to_vec())
}

// Función asíncrona para obtener un bloque completo de QRNG desde la API QEaaS
// Hacer múltiples peticiones a QEaaS para obtener los 32 bytes
async fn fetch_qeaas_block(
    client: &reqwest::Client,
    base_url: &str,
    block_size: usize,
) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(block_size);

    while out.len() < block_size {
        let remaining = block_size - out.len();
        let request_size = remaining.min(QEAAS_MAX_BYTES_PER_REQUEST);

        let mut chunk = fetch_qeaas_chunk(client, base_url, request_size).await?;
        out.append(&mut chunk);
    }

    Ok(out)
}

// Función asíncrona para decidir la fuente de QRNG
async fn get_qrng_block(
    mode: QrngSourceMode,
    client: &reqwest::Client,
    qeaas_api_url: &str,
) -> Result<(Vec<u8>, &'static str)> {
    match mode {
        QrngSourceMode::Simulated => {
            let block = generate_simulated_qrng_block();
            Ok((block, "simulated"))
        }

        QrngSourceMode::QeaaS => {
            let block = fetch_qeaas_block(client, qeaas_api_url, QRNG_BLOCK_SIZE).await?;
            Ok((block, "qeaas"))
        }

        QrngSourceMode::Auto => match fetch_qeaas_block(client, qeaas_api_url, QRNG_BLOCK_SIZE).await
        {
            Ok(block) => Ok((block, "qeaas")),
            Err(err) => {
                println!(
                    "[WARN] No se pudo obtener QRNG desde QEaaS: {:#}",
                    err
                );
                println!("[WARN] Usando QRNG simulado como fallback.");

                let block = generate_simulated_qrng_block();
                Ok((block, "simulated-fallback"))
            }
        },
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("QeeaS Rust server arrancando.");

    let qrng_source_mode = QrngSourceMode::from_env();

    let qeaas_api_url = env::var("QEAAS_API_URL")
        .unwrap_or_else(|_| "http://172.17.0.1:6065".to_string());

    println!("Modo fuente QRNG: {}", qrng_source_mode.as_str());
    println!("QEaaS API configurada en: {}", qeaas_api_url);

    // Crear cliente HTTP
    let http_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .context("No se pudo crear el cliente HTTP")?;

    let mut config = Config::default();

    config
        .insert_json5("mode", r#""client""#)
        .expect("No se pudo configurar el modo cliente");

    config
        .insert_json5(
            "connect/endpoints",
            &format!("[\"{}\"]", ZENOH_ROUTER_ENDPOINT),
        )
        .expect("No se pudo configurar el endpoint Zenoh");

    println!("Conectando al router Zenoh en {}", ZENOH_ROUTER_ENDPOINT);

    let session = zenoh::open(config)
        .await
        .expect("No se pudo abrir la sesión Zenoh");

    println!("Sesión de Zenoh abierta");

    let listener = session
        .declare_subscriber(STATUS_TOPIC)
        .await
        .expect("No se pudo crear el listener.");

    tokio::spawn(async move {
        while let Ok(sample) = listener.recv_async().await {
            let payload = sample.payload().try_to_string().unwrap_or_default();
            println!("Estado recibido desde ESP32: {}", payload);
        }
    });

    loop {
        let (qrng_block, source_name) =
            get_qrng_block(qrng_source_mode, &http_client, &qeaas_api_url).await?;

        println!(
            "Publicando bloque QRNG [{}]: {}",
            source_name,
            hex::encode(&qrng_block)
        );

        session
            .put(QRNG_TOPIC, qrng_block)
            .await
            .expect("Error publicando bloque QRNG");

        time::sleep(Duration::from_secs(2)).await;
    }
}