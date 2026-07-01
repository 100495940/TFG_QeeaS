use rand::RngCore;
use std::time::Duration;
use tokio::time;
use zenoh::config::{Config, WhatAmI};

const QRNG_TOPIC: &str = "qeeas/qrng/chunk";
const STATUS_TOPIC: &str = "qeeas/esp32/status";
const QRNG_BLOCK_SIZE: usize = 32;
const ZENOH_ROUTER_ENDPOINT: &str ="tcp/127.0.0.1:7447";

#[tokio::main]
async fn main() {
    println!("QeeaS Rust server arrancando.");

    let mut config = Config::default();

    config
        .insert_json5("mode", &format!("{:?}", WhatAmI::Client).to_lowercase())
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
        let mut qrng_block = [0u8; QRNG_BLOCK_SIZE];

        rand::thread_rng().fill_bytes(&mut qrng_block);

        println!("Publicando QRNG simulado: {}", hex::encode(qrng_block));

        session
            .put(QRNG_TOPIC, qrng_block.to_vec())
            .await
            .expect("Error publicando bloque QRNG");

        time::sleep(Duration::from_secs(2)).await;
    }
}