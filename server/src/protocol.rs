use serde::{Deserialize, Serialize};

use crate::world::types::{
    Asteroid, AsteroidKind, BlackHole, Drone, Factory, Inventory, SolarSystem, StarLite,
};

pub const SERVER_VERSION: &str = "0.0.3";

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMsg {
    Hello {
        name: String,
        client_version: String,
    },
    Mine {
        asteroid_id: i64,
    },
    Build {
        item: String,
    },
    OrderDrone {
        drone_id: i64,
        order: String,
        #[serde(default)]
        position: Option<[f32; 3]>,
    },
    OrderAllDrones {
        order: String,
        #[serde(default)]
        kind: Option<String>,
        #[serde(default)]
        position: Option<[f32; 3]>,
    },
    Cheat {
        action: String,
    },
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMsg {
    Welcome {
        session_id: String,
        server_version: String,
        server_now_ms: i64,
    },
    Spawn {
        system: SolarSystem,
        asteroids: Vec<Asteroid>,
        black_hole: BlackHole,
        far_stars: Vec<StarLite>,
        inventory: Inventory,
        position: [f32; 3],
        first_time: bool,
        drones: Vec<Drone>,
        factories: Vec<Factory>,
    },
    MineTick {
        asteroid_id: i64,
        remaining: i32,
        gained_kind: AsteroidKind,
        gained_amount: i32,
        inventory: Inventory,
    },
    AsteroidDepleted {
        asteroid_id: i64,
        gained_kind: AsteroidKind,
        gained_amount: i32,
        inventory: Inventory,
    },
    MineReject {
        asteroid_id: i64,
        reason: String,
    },
    BuildResult {
        ok: bool,
        item: String,
        reason: Option<String>,
        inventory: Inventory,
        drones: Vec<Drone>,
        factories: Vec<Factory>,
    },
    DroneTick {
        drones: Vec<Drone>,
        inventory: Inventory,
    },
    OrderResult {
        ok: bool,
        reason: Option<String>,
        affected: usize,
    },
    Error {
        code: String,
        message: String,
    },
}

pub fn encode(msg: &ServerMsg) -> String {
    serde_json::to_string(msg).expect("ServerMsg serialization is infallible")
}

pub fn decode(text: &str) -> serde_json::Result<ClientMsg> {
    serde_json::from_str(text)
}

pub fn valid_name(n: &str) -> bool {
    !n.is_empty() && n.chars().count() <= 32 && n.chars().all(|c| !c.is_control())
}
