use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

use crate::db::{self, MineOutcome};
use crate::protocol::{self, ClientMsg, ServerMsg, SERVER_VERSION};
use crate::AppState;

pub async fn handle(stream: TcpStream, peer: SocketAddr, state: Arc<AppState>) -> Result<()> {
    let mut ws = tokio_tungstenite::accept_async(stream).await?;
    tracing::info!(%peer, "ws accepted");

    let hello = match ws.next().await {
        Some(Ok(Message::Text(text))) => protocol::decode(&text),
        Some(Ok(Message::Close(_))) | None => {
            tracing::info!(%peer, "closed before hello");
            return Ok(());
        }
        Some(Ok(other)) => {
            send_error(&mut ws, "expected_text", "expected text hello frame").await;
            tracing::warn!(%peer, ?other, "non-text first frame");
            return Ok(());
        }
        Some(Err(e)) => {
            tracing::warn!(%peer, error = %e, "ws error before hello");
            return Ok(());
        }
    };

    let (name, client_version) = match hello {
        Ok(ClientMsg::Hello {
            name,
            client_version,
        }) => (name, client_version),
        Ok(_) => {
            send_error(&mut ws, "bad_hello", "first frame must be hello").await;
            return Ok(());
        }
        Err(e) => {
            send_error(&mut ws, "bad_hello", &format!("invalid hello: {e}")).await;
            return Ok(());
        }
    };

    if !protocol::valid_name(&name) {
        send_error(&mut ws, "bad_name", "name must be 1-32 non-control chars").await;
        return Ok(());
    }

    let session_id = Uuid::new_v4().to_string();
    tracing::info!(%peer, session = %session_id, name, client_version, "welcome");

    let welcome = protocol::encode(&ServerMsg::Welcome {
        session_id: session_id.clone(),
        server_version: SERVER_VERSION.to_string(),
        server_now_ms: chrono::Utc::now().timestamp_millis(),
    });
    ws.send(Message::Text(welcome)).await?;

    let spawn_state = state.clone();
    let spawn_name = name.clone();
    let spawn_res = tokio::task::spawn_blocking(move || {
        let mut conn = spawn_state.db.lock().expect("db mutex poisoned");
        db::get_or_create_player_spawn(&mut conn, spawn_state.galaxy_seed, &spawn_name)
    })
    .await?;

    let spawn = match spawn_res {
        Ok(s) => s,
        Err(e) => {
            tracing::error!(%peer, session = %session_id, error = %e, "spawn db error");
            send_error(&mut ws, "internal", "internal error resolving spawn").await;
            return Ok(());
        }
    };

    let player_id = spawn.player_id;
    tracing::info!(
        %peer,
        session = %session_id,
        player_id,
        system_id = spawn.system.id,
        first_time = spawn.first_time,
        n_planets = spawn.system.planets.len(),
        n_asteroids = spawn.asteroids.len(),
        n_far_stars = spawn.far_stars.len(),
        "spawn resolved"
    );

    let payload = protocol::encode(&ServerMsg::Spawn {
        system: spawn.system,
        asteroids: spawn.asteroids,
        black_hole: spawn.black_hole,
        far_stars: spawn.far_stars,
        inventory: spawn.inventory,
        position: spawn.position,
        first_time: spawn.first_time,
    });
    ws.send(Message::Text(payload)).await?;

    while let Some(frame) = ws.next().await {
        match frame {
            Ok(Message::Text(t)) => match protocol::decode(&t) {
                Ok(ClientMsg::Hello { .. }) => {
                    tracing::debug!(%peer, session = %session_id, "rx duplicate hello (ignored)");
                }
                Ok(ClientMsg::Mine { asteroid_id }) => {
                    let mine_state = state.clone();
                    let mine_res = tokio::task::spawn_blocking(move || {
                        let mut conn = mine_state.db.lock().expect("db mutex poisoned");
                        db::mine_asteroid(&mut conn, player_id, asteroid_id)
                    })
                    .await?;
                    let msg = match mine_res {
                        Ok(MineOutcome::Tick {
                            kind,
                            gained,
                            remaining,
                            inventory,
                        }) => ServerMsg::MineTick {
                            asteroid_id,
                            remaining,
                            gained_kind: kind,
                            gained_amount: gained,
                            inventory,
                        },
                        Ok(MineOutcome::Depleted {
                            kind,
                            gained,
                            inventory,
                        }) => ServerMsg::AsteroidDepleted {
                            asteroid_id,
                            gained_kind: kind,
                            gained_amount: gained,
                            inventory,
                        },
                        Ok(MineOutcome::Reject(reason)) => ServerMsg::MineReject {
                            asteroid_id,
                            reason,
                        },
                        Err(e) => {
                            tracing::error!(%peer, session = %session_id, error = %e, "mine db error");
                            ServerMsg::MineReject {
                                asteroid_id,
                                reason: "internal".into(),
                            }
                        }
                    };
                    ws.send(Message::Text(protocol::encode(&msg))).await?;
                }
                Err(e) => {
                    tracing::debug!(%peer, session = %session_id, error = %e, raw = %t, "bad client msg");
                }
            },
            Ok(Message::Binary(_)) => {
                tracing::debug!(%peer, session = %session_id, "rx binary (ignored)");
            }
            Ok(Message::Close(_)) => break,
            Ok(_) => {}
            Err(e) => {
                tracing::warn!(%peer, session = %session_id, error = %e, "ws error");
                break;
            }
        }
    }

    tracing::info!(%peer, session = %session_id, "closed");
    Ok(())
}

async fn send_error<S>(ws: &mut S, code: &str, message: &str)
where
    S: SinkExt<Message> + Unpin,
{
    let payload = protocol::encode(&ServerMsg::Error {
        code: code.to_string(),
        message: message.to_string(),
    });
    let _ = ws.send(Message::Text(payload)).await;
    let _ = ws.close().await;
}
