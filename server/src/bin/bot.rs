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

    #[arg(long, env = "DRONOID_BOT_NAME")]
    name: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();
    tracing::info!(url = %args.url, name = %args.name, "bot starting");

    let (mut ws, _) = connect_async(&args.url)
        .await
        .with_context(|| format!("connect_async to {}", args.url))?;
    tracing::info!("ws connected");

    let hello = json!({
        "type": "hello",
        "name": args.name,
        "client_version": BOT_VERSION,
    });
    ws.send(Message::Text(hello.to_string())).await?;
    tracing::info!("hello sent");

    while let Some(frame) = ws.next().await {
        match frame? {
            Message::Text(text) => {
                let parsed: Value = match serde_json::from_str(&text) {
                    Ok(v) => v,
                    Err(e) => {
                        tracing::warn!(error = %e, raw = %text, "non-json text frame");
                        continue;
                    }
                };
                handle_message(&parsed);
            }
            Message::Binary(_) => {}
            Message::Ping(p) => {
                ws.send(Message::Pong(p)).await?;
            }
            Message::Pong(_) => {}
            Message::Close(_) => {
                tracing::info!("server closed the connection");
                break;
            }
            Message::Frame(_) => {}
        }
    }

    tracing::info!("bot exiting");
    Ok(())
}

fn handle_message(msg: &Value) {
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
            tracing::info!(%session, server_now_ms, "welcome");
        }
        "spawn" => {
            let system_id = msg
                .pointer("/system/id")
                .and_then(|v| v.as_i64())
                .unwrap_or(-1);
            let star_name = msg
                .pointer("/system/star/name")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            let n_planets = msg
                .pointer("/system/planets")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            let n_asteroids = msg
                .get("asteroids")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            let first_time = msg
                .get("first_time")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            tracing::info!(
                system_id,
                star_name,
                n_planets,
                n_asteroids,
                first_time,
                "spawned"
            );
        }
        "error" => {
            let code = msg.get("code").and_then(|v| v.as_str()).unwrap_or("?");
            let message = msg.get("message").and_then(|v| v.as_str()).unwrap_or("");
            tracing::error!(code, message, "server error");
        }
        other => {
            tracing::debug!(kind = other, "unhandled message");
        }
    }
}
