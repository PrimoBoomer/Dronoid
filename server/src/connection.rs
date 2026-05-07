use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

use crate::db::{self, BuildOutcome, MineOutcome, OrderOutcome};
use crate::protocol::{self, ClientMsg, ServerMsg, SERVER_VERSION};
use crate::AppState;

const DRONE_TICK_MS: u64 = 200;

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
        drones: spawn.drones,
        factories: spawn.factories,
    });
    ws.send(Message::Text(payload)).await?;

    let (tx_send, mut rx_send) = mpsc::unbounded_channel::<ServerMsg>();

    let tick_state = state.clone();
    let tick_tx = tx_send.clone();
    let tick_handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_millis(DRONE_TICK_MS));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let dt = (DRONE_TICK_MS as f32) / 1000.0;
        loop {
            interval.tick().await;
            let s = tick_state.clone();
            let res = tokio::task::spawn_blocking(move || {
                let mut conn = s.db.lock().expect("db mutex poisoned");
                db::tick_drones(&mut conn, player_id, dt)
            })
            .await;
            match res {
                Ok(Ok(out)) => {
                    if out.changed
                        && tick_tx
                            .send(ServerMsg::DroneTick {
                                drones: out.drones,
                                inventory: out.inventory,
                            })
                            .is_err()
                    {
                        break;
                    }
                }
                Ok(Err(e)) => {
                    tracing::warn!(error = %e, "drone tick db error");
                }
                Err(e) => {
                    tracing::warn!(error = %e, "drone tick join error");
                    break;
                }
            }
        }
    });

    loop {
        tokio::select! {
            biased;
            Some(out) = rx_send.recv() => {
                if ws.send(Message::Text(protocol::encode(&out))).await.is_err() {
                    break;
                }
            }
            frame = ws.next() => {
                let Some(frame) = frame else { break };
                match frame {
            Ok(Message::Text(t)) => match protocol::decode(&t) {
                Ok(ClientMsg::Hello { .. }) => {
                    tracing::debug!(%peer, session = %session_id, "rx duplicate hello (ignored)");
                }
                Ok(ClientMsg::Build { item }) => {
                    let build_state = state.clone();
                    let item_for_task = item.clone();
                    let build_res = tokio::task::spawn_blocking(move || {
                        let mut conn = build_state.db.lock().expect("db mutex poisoned");
                        db::build_item(&mut conn, player_id, &item_for_task)
                    })
                    .await?;
                    let msg = match build_res {
                        Ok(BuildOutcome::Ok {
                            inventory,
                            drones,
                            factories,
                        }) => {
                            tracing::info!(%peer, session = %session_id, player_id, item = %item, "built");
                            ServerMsg::BuildResult {
                                ok: true,
                                item: item.clone(),
                                reason: None,
                                inventory,
                                drones,
                                factories,
                            }
                        }
                        Ok(BuildOutcome::Insufficient {
                            inventory,
                            drones,
                            factories,
                        }) => {
                            tracing::debug!(%peer, session = %session_id, player_id, item = %item, "build rejected: insufficient");
                            ServerMsg::BuildResult {
                                ok: false,
                                item: item.clone(),
                                reason: Some("insufficient_resources".into()),
                                inventory,
                                drones,
                                factories,
                            }
                        }
                        Ok(BuildOutcome::UnknownItem) => {
                            tracing::debug!(%peer, session = %session_id, item = %item, "unknown build item");
                            ServerMsg::Error {
                                code: "bad_build_item".into(),
                                message: format!("unknown item: {item}"),
                            }
                        }
                        Err(e) => {
                            tracing::error!(%peer, session = %session_id, error = %e, "build db error");
                            ServerMsg::Error {
                                code: "internal".into(),
                                message: "internal error during build".into(),
                            }
                        }
                    };
                    ws.send(Message::Text(protocol::encode(&msg))).await?;
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
                Ok(ClientMsg::OrderDrone { drone_id, order }) => {
                    let order_state = state.clone();
                    let order_for_task = order.clone();
                    let order_res = tokio::task::spawn_blocking(move || {
                        let mut conn = order_state.db.lock().expect("db mutex poisoned");
                        db::order_drone(&mut conn, player_id, drone_id, &order_for_task)
                    })
                    .await?;
                    let (msg, follow_up) = match order_res {
                        Ok(OrderOutcome::Ok {
                            affected,
                            drones,
                            inventory,
                        }) => {
                            tracing::info!(%peer, session = %session_id, player_id, drone_id, order = %order, "ordered");
                            (
                                ServerMsg::OrderResult {
                                    ok: true,
                                    reason: None,
                                    affected,
                                },
                                Some(ServerMsg::DroneTick { drones, inventory }),
                            )
                        }
                        Ok(OrderOutcome::Reject(reason)) => {
                            tracing::debug!(%peer, session = %session_id, drone_id, reason = %reason, "order rejected");
                            (
                                ServerMsg::OrderResult {
                                    ok: false,
                                    reason: Some(reason),
                                    affected: 0,
                                },
                                None,
                            )
                        }
                        Err(e) => {
                            tracing::error!(%peer, session = %session_id, error = %e, "order db error");
                            (
                                ServerMsg::OrderResult {
                                    ok: false,
                                    reason: Some("internal".into()),
                                    affected: 0,
                                },
                                None,
                            )
                        }
                    };
                    ws.send(Message::Text(protocol::encode(&msg))).await?;
                    if let Some(f) = follow_up {
                        ws.send(Message::Text(protocol::encode(&f))).await?;
                    }
                }
                Ok(ClientMsg::OrderAllDrones { order }) => {
                    let order_state = state.clone();
                    let order_for_task = order.clone();
                    let order_res = tokio::task::spawn_blocking(move || {
                        let mut conn = order_state.db.lock().expect("db mutex poisoned");
                        db::order_all_drones(&mut conn, player_id, &order_for_task)
                    })
                    .await?;
                    let (msg, follow_up) = match order_res {
                        Ok(OrderOutcome::Ok {
                            affected,
                            drones,
                            inventory,
                        }) => {
                            tracing::info!(%peer, session = %session_id, player_id, affected, order = %order, "ordered all");
                            (
                                ServerMsg::OrderResult {
                                    ok: true,
                                    reason: None,
                                    affected,
                                },
                                Some(ServerMsg::DroneTick { drones, inventory }),
                            )
                        }
                        Ok(OrderOutcome::Reject(reason)) => (
                            ServerMsg::OrderResult {
                                ok: false,
                                reason: Some(reason),
                                affected: 0,
                            },
                            None,
                        ),
                        Err(e) => {
                            tracing::error!(%peer, session = %session_id, error = %e, "order all db error");
                            (
                                ServerMsg::OrderResult {
                                    ok: false,
                                    reason: Some("internal".into()),
                                    affected: 0,
                                },
                                None,
                            )
                        }
                    };
                    ws.send(Message::Text(protocol::encode(&msg))).await?;
                    if let Some(f) = follow_up {
                        ws.send(Message::Text(protocol::encode(&f))).await?;
                    }
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
        }
    }

    tick_handle.abort();
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
