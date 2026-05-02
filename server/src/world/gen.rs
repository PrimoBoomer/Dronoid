use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;

use super::types::{AsteroidKind, Moon, Planet, SolarSystem, Star};

pub const ORBIT_K: f32 = 0.3;
pub const MOON_K: f32 = 0.8;
pub const BELT_K: f32 = 0.0;

pub const BODY_OMEGA_VERSION: &str = "2";

pub const BLACK_HOLE_ID: i64 = 0;

const ASTEROIDS_MIN: usize = 2300;
const ASTEROIDS_MAX: usize = 2700;
const BELT_GAP: f32 = 50.0;
const BELT_WIDTH: f32 = 80.0;
const BELT_THICKNESS_Y: f32 = 15.0;

fn star_id(system_id: i64) -> i64 {
    (system_id << 12) | 1
}
fn planet_id(system_id: i64, i: usize) -> i64 {
    (system_id << 12) | (0x0100 + i as i64)
}
fn moon_id(system_id: i64, planet_i: usize, j: usize) -> i64 {
    (system_id << 12) | (0x0800 + (planet_i as i64) * 8 + j as i64)
}

pub struct GeneratedSystem {
    pub system: SolarSystem,
    pub asteroid_seeds: Vec<AsteroidSeed>,
}

pub struct AsteroidSeed {
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

pub fn pick_asteroid_kind(rng: &mut impl Rng) -> AsteroidKind {
    let r: f32 = rng.gen_range(0.0..1.0);
    if r < 0.40 {
        AsteroidKind::Iron
    } else if r < 0.65 {
        AsteroidKind::Copper
    } else if r < 0.90 {
        AsteroidKind::Silicon
    } else {
        AsteroidKind::Ice
    }
}

pub fn base_color(kind: AsteroidKind) -> [f32; 3] {
    match kind {
        AsteroidKind::Iron => [0.45, 0.30, 0.20],
        AsteroidKind::Copper => [0.85, 0.45, 0.20],
        AsteroidKind::Silicon => [0.55, 0.65, 0.75],
        AsteroidKind::Ice => [0.85, 0.95, 1.0],
    }
}

fn jitter_color(rng: &mut impl Rng, base: [f32; 3], jitter: f32) -> [f32; 3] {
    [
        (base[0] + rng.gen_range(-jitter..jitter)).clamp(0.0, 1.0),
        (base[1] + rng.gen_range(-jitter..jitter)).clamp(0.0, 1.0),
        (base[2] + rng.gen_range(-jitter..jitter)).clamp(0.0, 1.0),
    ]
}

pub fn stock_for_radius(radius: f32) -> i32 {
    ((radius * radius) * 600.0).ceil().max(1.0) as i32
}

pub fn gen_solar_system(
    seed: u64,
    system_id: i64,
    galactic_pos: [f32; 3],
    epoch_ms: i64,
) -> GeneratedSystem {
    let mut rng = ChaCha8Rng::seed_from_u64(seed);

    let s_id = star_id(system_id);
    let star = Star {
        id: s_id,
        primary: BLACK_HOLE_ID,
        name: format!("Sol-{}", seed % 10000),
        galactic_pos,
        radius: rng.gen_range(8.0..25.0),
        color: [
            rng.gen_range(0.85..1.0),
            rng.gen_range(0.7..1.0),
            rng.gen_range(0.5..0.95),
        ],
        phase: rng.gen_range(0.0..std::f32::consts::TAU),
        omega: 0.0,
    };

    let n_planets = rng.gen_range(5..=12);
    let mut planets = Vec::with_capacity(n_planets);
    let mut orbit: f32 = star.radius * 4.0;
    for i in 0..n_planets {
        orbit += rng.gen_range(5.0..25.0);
        let p_radius: f32 = rng.gen_range(0.4..4.0);
        let p_id = planet_id(system_id, i);
        let n_moons = rng.gen_range(0..=3);
        let mut moons = Vec::with_capacity(n_moons);
        let mut m_orbit: f32 = p_radius * 1.8;
        for j in 0..n_moons {
            m_orbit += rng.gen_range(0.4..1.5);
            let m_radius: f32 = rng.gen_range(0.05..(p_radius * 0.4).max(0.06));
            let g: f32 = rng.gen_range(0.55..0.95);
            moons.push(Moon {
                id: moon_id(system_id, i, j),
                primary: p_id,
                name: format!("P{}m{}", i + 1, j + 1),
                orbit_radius: m_orbit,
                phase: rng.gen_range(0.0..std::f32::consts::TAU),
                omega: MOON_K / m_orbit.max(0.1).sqrt(),
                radius: m_radius,
                color: [
                    (g + rng.gen_range(-0.05..0.05)).clamp(0.0, 1.0),
                    (g + rng.gen_range(-0.05..0.05)).clamp(0.0, 1.0),
                    (g + rng.gen_range(-0.05..0.05)).clamp(0.0, 1.0),
                ],
            });
        }
        planets.push(Planet {
            id: p_id,
            primary: s_id,
            name: format!("P{}", i + 1),
            orbit_radius: orbit,
            phase: rng.gen_range(0.0..std::f32::consts::TAU),
            omega: ORBIT_K / orbit.max(0.1).sqrt(),
            radius: p_radius,
            color: [
                rng.gen_range(0.2..0.9),
                rng.gen_range(0.2..0.9),
                rng.gen_range(0.2..0.9),
            ],
            moons,
        });
    }

    let belt_inner = orbit + BELT_GAP;
    let belt_outer = belt_inner + BELT_WIDTH;
    let n_asteroids = rng.gen_range(ASTEROIDS_MIN..=ASTEROIDS_MAX);
    let mut asteroid_seeds = Vec::with_capacity(n_asteroids);
    for _ in 0..n_asteroids {
        let r = rng.gen_range(belt_inner..belt_outer);
        let kind = pick_asteroid_kind(&mut rng);
        let radius: f32 = rng.gen_range(0.05..1.0);
        asteroid_seeds.push(AsteroidSeed {
            primary: s_id,
            orbit_radius: r,
            orbit_y: rng.gen_range(-BELT_THICKNESS_Y..BELT_THICKNESS_Y),
            phase: rng.gen_range(0.0..std::f32::consts::TAU),
            omega: BELT_K / r.max(0.1).sqrt(),
            radius,
            color: jitter_color(&mut rng, base_color(kind), 0.10),
            kind,
            stock: stock_for_radius(radius),
        });
    }

    GeneratedSystem {
        system: SolarSystem {
            id: system_id,
            seed: format!("0x{seed:016x}"),
            epoch_ms,
            star,
            planets,
        },
        asteroid_seeds,
    }
}
