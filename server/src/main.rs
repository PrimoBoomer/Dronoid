mod connection;
mod db;
mod protocol;
mod world;

use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(name = "dronoid-server", about = "Dronoid galaxy instance server")]
struct Args {
    #[arg(long, env = "DRONOID_DB", default_value = "galaxy.sqlite")]
    db: PathBuf,

    #[arg(long, env = "DRONOID_BIND", default_value = "127.0.0.1:8080")]
    bind: String,
}

pub struct AppState {
    pub db: Mutex<rusqlite::Connection>,
    pub galaxy_seed: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();
    let db = db::open(&args.db)?;
    let state = Arc::new(AppState {
        db: Mutex::new(db.conn),
        galaxy_seed: db.galaxy_seed,
    });

    let listener = TcpListener::bind(&args.bind).await?;
    tracing::info!("listening on {}", args.bind);

    loop {
        let (stream, peer) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = connection::handle(stream, peer, state).await {
                tracing::warn!(%peer, error = %e, "connection ended with error");
            }
        });
    }
}
