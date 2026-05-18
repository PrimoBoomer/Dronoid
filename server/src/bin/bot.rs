use anyhow::{Context, Result};
use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing_subscriber::EnvFilter;

const BOT_VERSION: &str = "0.0.1";

#[derive(Parser, Debug)]
#[command(name = "dronoid-bot", about = "Autonomous Dronoid bot client")]
struct Args {
    #[arg(long, env = "DRONOID_URL", default_value = "ws://127.0.0.1:8080")]
    url: String,

    #[arg(long, env = "DRONOID_BOT_SEED", default_value_t = 42)]
    seed: u64,

    #[arg(long, env = "DRONOID_BOT_COUNT", default_value_t = 1)]
    count: u32,

    #[arg(long, env = "DRONOID_BOT_PREFIX", default_value = "Bot")]
    prefix: String,
}

fn bot_name(prefix: &str, seed: u64, index: u32) -> String {
    let mut h = seed.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    h ^= (index as u64).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    h = (h ^ (h >> 32)).wrapping_mul(0x94D0_49BB_1331_11EB);
    h ^= h >> 32;
    format!("{}-{:04X}", prefix, (h & 0xFFFF) as u16)
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();
    tracing::info!(url = %args.url, seed = args.seed, count = args.count, "swarm starting");

    let mut handles = Vec::with_capacity(args.count as usize);
    for i in 0..args.count {
        let name = bot_name(&args.prefix, args.seed, i);
        let url = args.url.clone();
        handles.push(tokio::spawn(async move {
            if let Err(e) = run_bot(&url, &name).await {
                tracing::error!(%name, error = %e, "bot exited with error");
            }
        }));
    }

    for h in handles {
        let _ = h.await;
    }

    tracing::info!("swarm exiting");
    Ok(())
}

async fn run_bot(url: &str, name: &str) -> Result<()> {
    tracing::info!(%name, "bot starting");

    let (mut ws, _) = connect_async(url)
        .await
        .with_context(|| format!("connect_async to {}", url))?;
    tracing::info!(%name, "ws connected");

    let hello = json!({
        "type": "hello",
        "name": name,
        "client_version": BOT_VERSION,
    });
    ws.send(Message::Text(hello.to_string())).await?;

    while let Some(frame) = ws.next().await {
        match frame? {
            Message::Text(text) => {
                let parsed: Value = match serde_json::from_str(&text) {
                    Ok(v) => v,
                    Err(e) => {
                        tracing::warn!(%name, error = %e, raw = %text, "non-json text frame");
                        continue;
                    }
                };
                handle_message(name, &parsed);
            }
            Message::Binary(_) => {}
            Message::Ping(p) => {
                ws.send(Message::Pong(p)).await?;
            }
            Message::Pong(_) => {}
            Message::Close(_) => {
                tracing::info!(%name, "server closed the connection");
                break;
            }
            Message::Frame(_) => {}
        }
    }

    tracing::info!(%name, "bot exiting");
    Ok(())
}

fn handle_message(name: &str, msg: &Value) {
    let t = msg.get("type").and_then(|v| v.as_str()).unwrap_or("?");
    match t {
        "welcome" => {
            let session = msg
                .get("session_id")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            let server_now_ms = msg
                .get("server_now_ms")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            tracing::info!(%name, %session, server_now_ms, "welcome");
        }
        "spawn" => {
            let first_time = msg
                .get("first_time")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            tracing::info!(%name, first_time, "spawned");
        }
        "error" => {
            let code = msg.get("code").and_then(|v| v.as_str()).unwrap_or("?");
            let message = msg.get("message").and_then(|v| v.as_str()).unwrap_or("");
            tracing::error!(%name, code, message, "server error");
        }
        other => {
            tracing::debug!(%name, kind = other, "unhandled message");
        }
    }
}
