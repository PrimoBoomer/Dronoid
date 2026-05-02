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
