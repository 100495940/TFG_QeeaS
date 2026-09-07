mod observability;

use anyhow::{Context, Result};
use rand::RngCore;
use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::fs::{create_dir_all, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use std::time::Instant;
use tokio::time;

const ACK_TOPIC: &str = "qeeas/esp32/ack";
const QRNG_TOPIC: &str = "qeeas/qrng/chunk";
const STATUS_TOPIC: &str = "qeeas/esp32/status";
const ENTROPY_SOURCE_TRNG_TOPIC: &str = "qeeas/esp32/entropy/source/trng";
const ENTROPY_SOURCE_QRNG_TOPIC: &str = "qeeas/esp32/entropy/source/qrng";
const ENTROPY_FINAL_ACTIVE_TOPIC: &str = "qeeas/esp32/entropy/final/active";
const ENTROPY_FINAL_XOR_TOPIC: &str = "qeeas/esp32/entropy/final/xor";

const ACK_SIZE: usize = 20;
const TOTAL_BLOCK_SIZE: usize = 40;
const QRNG_BLOCK_SIZE: usize = 32;
const QEAAS_MAX_BYTES_PER_REQUEST: usize = 8;

const ACK_TIMEOUT: Duration = Duration::from_secs(5);

const ZENOH_ROUTER_ENDPOINT_PLAIN: &str = "tcp/127.0.0.1:7447";
const ZENOH_ROUTER_ENDPOINT_TLS: &str = "tls/127.0.0.1:7447";

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

//Función para abrir un archivo de captura de entropía, creando directorios si es necesario
fn open_capture_file(path: &Path) -> anyhow::Result<Arc<Mutex<File>>> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent)?;
    }

    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(path)?;

    Ok(Arc::new(Mutex::new(file)))
}

// Función para escribir los bloques binarios de entropía en los archivos de captura
fn append_entropy_sample(
    label: &'static str,
    file: &Arc<Mutex<File>>,
    bytes: &[u8],
) {
    // Bloquear el archivo para escritura
    let mut guard = match file.lock() {
        Ok(guard) => guard,
        Err(err) => {
            eprintln!("[ERROR] No se pudo bloquear archivo de {}: {}", label, err);
            return;
        }
    };

    // Escribir todos los bytes recibidos
    if let Err(err) = guard.write_all(bytes) {
        eprintln!("[ERROR] No se pudo escribir muestra {}: {}", label, err);
        return;
    }

    // Volcar los datos en el archivo
    if let Err(err) = guard.flush() {
        eprintln!("[WARN] No se pudo hacer flush de {}: {}", label, err);
    }

    let head_len = bytes.len().min(4);

    println!(
        "[ENTROPY_CAPTURE] label={} bytes={} head={}",
        label,
        bytes.len(),
        hex::encode(&bytes[..head_len])
    );
}

// Función auxiliar para mapear tipado de errores
fn map_zenoh_error(err: Box<dyn std::error::Error + Send + Sync>) -> anyhow::Error {
    anyhow::anyhow!("{}", err)
}

// Función auxiliar para cargar la configuración de Zenoh (TCP/TLS)
fn load_zenoh_config() -> anyhow::Result<zenoh::Config> {
    if let Ok(config_path) = std::env::var("ZENOH_CONFIG") {
        println!("[ZENOH] Cargando configuracion desde {}", config_path);

        let config = zenoh::Config::from_file(&config_path)
            .map_err(|err| anyhow::anyhow!(
                "No se pudo cargar la configuracion Zenoh desde {}: {}",
                config_path,
                err
            ))?;

        return Ok(config);
    }

    println!(
        "[ZENOH] ZENOH_CONFIG no definido. Usando endpoint por defecto: {}",
        ZENOH_ROUTER_ENDPOINT_PLAIN
    );

    let mut config = zenoh::Config::default();

    config
        .insert_json5("mode", r#""client""#)
        .map_err(|err| anyhow::anyhow!(
            "No se pudo configurar el modo Zenoh client: {}",
            err
    ))?;

    config
        .insert_json5(
            "connect/endpoints",
            &format!(r#"["{}"]"#, ZENOH_ROUTER_ENDPOINT_PLAIN),
        )
        .map_err(|err| anyhow::anyhow!(
            "No se pudo configurar endpoint Zenoh por defecto {}: {}",
            ZENOH_ROUTER_ENDPOINT_PLAIN,
            err
    ))?;

    Ok(config)
}


// Función para parsear el ack del microcontrolador
fn parse_ack(bytes: &[u8]) -> anyhow::Result<(u64, u32, u32, u32)> {
    if bytes.len() != ACK_SIZE {
        anyhow::bail!(
            "ACK con tamaño incorrecto: {} bytes (esperados {})",
            bytes.len(),
            ACK_SIZE
        );
    }

    let sequence_id = u64::from_be_bytes(
        bytes[0..8].try_into()?
    );

    let trng_ns = u32::from_be_bytes(
        bytes[8..12].try_into()?
    );

    let xor_ns = u32::from_be_bytes(
        bytes[12..16].try_into()?
    );

    let final_active_entropy_ns = u32::from_be_bytes(
        bytes[16..20].try_into()?
    );

    Ok((sequence_id, trng_ns, xor_ns, final_active_entropy_ns))
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("QeeaS Rust server arrancando.");

    // Iniciar métricas en prometheus
    observability::init_metrics()?;

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

    let config = load_zenoh_config()?;

    let session = zenoh::open(config)
        .await
        .expect("No se pudo abrir la sesión Zenoh");

    println!("Sesión de Zenoh abierta");

    let experiment_label = std::env::var("ENTROPY_EXPERIMENT")
        .unwrap_or_else(|_| "default".to_string());

    let capture_dir = PathBuf::from("data")
        .join("captures")
        .join(&experiment_label);

    create_dir_all(&capture_dir)?;

    println!(
        "[INFO] Captura de entropia activada. Experimento={} dir={}",
        experiment_label,
        capture_dir.display()
    );

    let trng_file = open_capture_file(&capture_dir.join("entropy_source_trng.bin"))?;
    let qrng_file = open_capture_file(&capture_dir.join("entropy_source_qrng.bin"))?;
    let active_file = open_capture_file(&capture_dir.join("entropy_final_active.bin"))?;
    let xor_file = open_capture_file(&capture_dir.join("entropy_final_xor.bin"))?;

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

    let trng_file_for_sub = Arc::clone(&trng_file);

    let _trng_subscriber = session
        .declare_subscriber(ENTROPY_SOURCE_TRNG_TOPIC)
        .callback(move |sample| {
            let payload = sample.payload().to_bytes();
            append_entropy_sample("source_trng", &trng_file_for_sub, payload.as_ref());
        })
        .await
        .map_err(map_zenoh_error)?;

    let qrng_file_for_sub = Arc::clone(&qrng_file);

    let _qrng_subscriber = session
        .declare_subscriber(ENTROPY_SOURCE_QRNG_TOPIC)
        .callback(move |sample| {
            let payload = sample.payload().to_bytes();
            append_entropy_sample("source_qrng", &qrng_file_for_sub, payload.as_ref());
        })
        .await
        .map_err(map_zenoh_error)?;

    let active_file_for_sub = Arc::clone(&active_file);

    let _active_subscriber = session
        .declare_subscriber(ENTROPY_FINAL_ACTIVE_TOPIC)
        .callback(move |sample| {
            let payload = sample.payload().to_bytes();
            append_entropy_sample("final_active", &active_file_for_sub, payload.as_ref());
        })
        .await
        .map_err(map_zenoh_error)?;

    let xor_file_for_sub = Arc::clone(&xor_file);

    let _xor_subscriber = session
        .declare_subscriber(ENTROPY_FINAL_XOR_TOPIC)
        .callback(move |sample| {
            let payload = sample.payload().to_bytes();
            append_entropy_sample("final_xor", &xor_file_for_sub, payload.as_ref());
        })
        .await
        .map_err(map_zenoh_error)?;

    // Crear tabla con identificador de bloque y momento en el que se publica
    let pending = Arc::new(
        Mutex::new(
            HashMap::<u64, Instant>::new()
        )
    );

    let pending_ack = Arc::clone(&pending);

    let pending_timeout = Arc::clone(&pending);

    tokio::spawn(async move {
        loop {
            time::sleep(Duration::from_millis(500)).await;
            let now = Instant::now();
            let timed_out = {
                let mut pending = pending_timeout
                    .lock()
                    .expect("Mutex pending corrupto");
                let before = pending.len();
                pending.retain(
                    |sequence_id, sent_at| {
                        let keep = now.duration_since(*sent_at) < ACK_TIMEOUT;

                        if !keep {
                            eprintln!("[ACK-TIMEOUT] sequence_id={} sin ACK", sequence_id);
                        }

                        keep
                    },
                );

                before - pending.len()
            };

            for _ in 0..timed_out {
                observability::record_ack_timeout();
            }
        }
    });

    let previous_rtt = Arc::new(Mutex::new(None::<f64>));

    let previous_rtt_ack = Arc::clone(&previous_rtt);

    let _ack_subscriber = session
        .declare_subscriber(ACK_TOPIC)
        .callback(move |sample| {
            // Obtener payload del ACK
            let payload = sample.payload().to_bytes();
            let ack_bytes = payload.as_ref();

            // Interpretar ACK recibido
            let (sequence_id, trng_ns, xor_ns, final_active_entropy_ns) =
                match parse_ack(ack_bytes) {
                    Ok(values) => values,

                    Err(err) => {
                        eprintln!(
                            "[ACK] Error interpretando ACK: {:#}",
                            err
                        );
                        return;
                    }
                };

            // Buscar cuándo se publicó este bloque y borrarlo de la tabla
            let sent_at = {
                let mut pending =
                    pending_ack
                        .lock()
                        .expect("Mutex pending corrupto");

                pending.remove(&sequence_id)
            };

            match sent_at {
                Some(sent_at) => {
                    // RTT Rust -> ESP32 -> Rust
                    let rtt = sent_at.elapsed().as_secs_f64();
                    observability::record_e2e_rtt(rtt);

                    let jitter = {
                        let mut previous = previous_rtt_ack
                            .lock()
                            .expect("Mutex previous_rtt corrupto");

                        let jitter = previous.map(|prev| (rtt - prev).abs());

                        *previous = Some(rtt);
                        jitter
                    };

                    if let Some(jitter) = jitter {observability::record_e2e_jitter(jitter);}

                    observability::record_block_acknowledged();
                    observability::record_esp32_trng_duration(trng_ns);
                    observability::record_esp32_xor_duration(xor_ns);
                    observability::record_esp32_final_active_entropy_duration(final_active_entropy_ns);

                    println!(
                        "[ACK] seq={} RTT={:.3} ms TRNG={} ns XOR={} ns final entropy={}",
                        sequence_id,
                        rtt * 1000.0,
                        trng_ns,
                        xor_ns,
                        final_active_entropy_ns
                    );
                }

                None => {
                    eprintln!(
                        "[ACK] ACK recibido para sequence_id={} \
                        pero no existe en pending",
                        sequence_id
                    );
                }
            }
        })
        .await
        .map_err(map_zenoh_error)?;

    // Crear identificador de bloques para métricas
    let mut sequence_id: u64 = 0;

    loop {
        let source = qrng_source_mode.as_str();

        observability::record_qrng_request(source);

        // Timestamp para métricas prometheus
        let qrng_start = Instant::now();

        let qrng_result =
            get_qrng_block(
                qrng_source_mode, 
                &http_client, 
                &qeaas_api_url
            ).await;

        // Calcular tiempo consumido en llamar a la API
        let qrng_duration = qrng_start.elapsed().as_secs_f64();

        match &qrng_result {
            Ok(_) => {
                observability::record_qrng_fetch_duration(source, qrng_duration);
            }

            Err(_) => {
                observability::record_qrng_request_errors(source);
            }
        }

        let (qrng_block, source_name) = qrng_result?;
        

        println!(
            "Publicando bloque QRNG [{}]: {}",
            source_name,
            hex::encode(&qrng_block)
        );

        let block_size = qrng_block.len();

        let publish_zenoh_start = Instant::now();

        sequence_id += 1;
        // Crear bloque a enviar a través de Zenoh
        let mut frame =  Vec::with_capacity(TOTAL_BLOCK_SIZE);

        // Añadir identificador de bloque al mensaje a enviar
        frame.extend_from_slice(
            &sequence_id.to_be_bytes()
        );

        // Añadir QRNG al bloque a enviar
        frame.extend_from_slice(
            &qrng_block
        );

        let sent_at = Instant::now();

        // Grabar en la tabla el momento en el que sale cada bloque
        pending
            .lock()
            .expect("Mutex pending corrupto")
            .insert(sequence_id, sent_at);

        let publish_zenoh_result = session
            .put(QRNG_TOPIC, frame)
            .await;

        // Registrar duración de la publicación a la sesión Zenoh
        let publish_zenoh_duration = publish_zenoh_start.elapsed().as_secs_f64();

        match publish_zenoh_result {
            Ok(_) => {
                observability::record_zenoh_publish_duration(publish_zenoh_duration);

                // Incrementar contador bloques prometheus
                observability::record_qrng_block_published(source_name);

                // Incrementar contador bytes prometheus
                observability::record_qrng_bytes_published(source_name, block_size);
            }

            Err(err) => {
                observability::record_zenoh_publish_error();

                panic!("Error publicando bloque QRNG: {}", err);
            }
        }

        time::sleep(Duration::from_secs(2)).await;
    }
}