use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlackHole {
    pub id: i64,
    pub radius: f32,
    pub color: [f32; 3],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Star {
    pub id: i64,
    pub primary: i64,
    pub name: String,
    pub galactic_pos: [f32; 3],
    pub radius: f32,
    pub color: [f32; 3],
    pub phase: f32,
    pub omega: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Moon {
    pub id: i64,
    pub primary: i64,
    pub name: String,
    pub orbit_radius: f32,
    pub phase: f32,
    pub omega: f32,
    pub radius: f32,
    pub color: [f32; 3],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Planet {
    pub id: i64,
    pub primary: i64,
    pub name: String,
    pub orbit_radius: f32,
    pub phase: f32,
    pub omega: f32,
    pub radius: f32,
    pub color: [f32; 3],
    pub moons: Vec<Moon>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AsteroidKind {
    Iron,
    Copper,
    Silicon,
    Ice,
}

impl AsteroidKind {
    pub fn as_str(self) -> &'static str {
        match self {
            AsteroidKind::Iron => "iron",
            AsteroidKind::Copper => "copper",
            AsteroidKind::Silicon => "silicon",
            AsteroidKind::Ice => "ice",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        Some(match s {
            "iron" => AsteroidKind::Iron,
            "copper" => AsteroidKind::Copper,
            "silicon" => AsteroidKind::Silicon,
            "ice" => AsteroidKind::Ice,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Asteroid {
    pub id: i64,
    pub system_id: i64,
    pub primary: i64,
    pub orbit_radius: f32,
    pub orbit_y: f32,
    pub phase: f32,
    pub omega: f32,
    pub radius: f32,
    pub color: [f32; 3],
    pub kind: AsteroidKind,
    pub stock: i32,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct Inventory {
    pub iron: i64,
    pub copper: i64,
    pub silicon: i64,
    pub ice: i64,
}

impl Inventory {
    pub fn add(&mut self, kind: AsteroidKind, amount: i64) {
        match kind {
            AsteroidKind::Iron => self.iron += amount,
            AsteroidKind::Copper => self.copper += amount,
            AsteroidKind::Silicon => self.silicon += amount,
            AsteroidKind::Ice => self.ice += amount,
        }
    }

    pub fn get(&self, kind: AsteroidKind) -> i64 {
        match kind {
            AsteroidKind::Iron => self.iron,
            AsteroidKind::Copper => self.copper,
            AsteroidKind::Silicon => self.silicon,
            AsteroidKind::Ice => self.ice,
        }
    }

    pub fn try_consume(&mut self, costs: &[(AsteroidKind, i64)]) -> bool {
        for &(kind, amount) in costs {
            if self.get(kind) < amount {
                return false;
            }
        }
        for &(kind, amount) in costs {
            self.add(kind, -amount);
        }
        true
    }
}

pub const DRONE_COST: &[(AsteroidKind, i64)] = &[
    (AsteroidKind::Iron, 20),
    (AsteroidKind::Copper, 10),
    (AsteroidKind::Silicon, 5),
];

pub const FACTORY_COST: &[(AsteroidKind, i64)] = &[
    (AsteroidKind::Iron, 200),
    (AsteroidKind::Copper, 100),
    (AsteroidKind::Silicon, 80),
    (AsteroidKind::Ice, 50),
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Drone {
    pub id: i64,
    pub kind: String,
    pub created_at: String,
    pub position: [f32; 3],
    pub velocity: [f32; 3],
    pub state: String,
    pub target_asteroid: Option<i64>,
}

pub const DRONE_SPEED: f32 = 12.0;
pub const DRONE_ACCEL: f32 = 4.0;
pub const DRONE_MINE_RANGE: f32 = 8.0;
pub const DRONE_MINE_INTERVAL_MS: i64 = 200;
pub const DRONE_MINE_AMOUNT: i32 = 2;
pub const DRONE_FORMATION_RADIUS: f32 = 14.0;
pub const DRONE_FORMATION_HEIGHT: f32 = 2.5;
pub const DRONE_RETURN_TOLERANCE: f32 = 2.0;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Factory {
    pub id: i64,
    pub kind: String,
    pub created_at: String,
    pub position: [f32; 3],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolarSystem {
    pub id: i64,
    pub seed: String,
    pub epoch_ms: i64,
    pub star: Star,
    pub planets: Vec<Planet>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StarLite {
    pub id: i64,
    pub name: String,
    pub galactic_pos: [f32; 3],
    pub radius: f32,
    pub color: [f32; 3],
}
