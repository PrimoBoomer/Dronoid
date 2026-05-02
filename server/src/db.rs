use anyhow::{bail, Context, Result};
use chrono::Utc;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use std::path::Path;

use crate::world::gen::{
    gen_solar_system, BELT_K, BLACK_HOLE_ID, BODY_OMEGA_VERSION, MOON_K, ORBIT_K,
};
use crate::world::types::{Asteroid, AsteroidKind, BlackHole, Inventory, SolarSystem, StarLite};

const SCHEMA_VERSION: &str = "3";
const BLACK_HOLE_RADIUS: f32 = 200.0;
const BLACK_HOLE_COLOR: [f32; 3] = [0.05, 0.0, 0.08];

pub const MINE_TICK_AMOUNT: i32 = 5;

pub struct Db {
    pub conn: Connection,
    pub galaxy_seed: u64,
}

pub fn open(path: &Path) -> Result<Db> {
    let existed = path.exists();
    let conn = Connection::open(path).with_context(|| format!("opening {}", path.display()))?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;

    if !existed {
        migrate_v3(&conn)?;
        let seed: u64 = rand::random();
        conn.execute(
            "INSERT INTO meta(key, value) VALUES('schema_version', ?1)",
            params![SCHEMA_VERSION],
        )?;
        conn.execute(
            "INSERT INTO meta(key, value) VALUES('galaxy_seed', ?1)",
            params![format!("{:016x}", seed)],
        )?;
        conn.execute(
            "INSERT INTO meta(key, value) VALUES('created_at', ?1)",
            params![Utc::now().to_rfc3339()],
        )?;
        conn.execute(
            "INSERT INTO black_hole(id, radius, color_json) VALUES(?1, ?2, ?3)",
            params![
                BLACK_HOLE_ID,
                BLACK_HOLE_RADIUS,
                serde_json::to_string(&BLACK_HOLE_COLOR)?
            ],
        )?;
        tracing::info!(path = %path.display(), galaxy_seed = format!("0x{:016x}", seed), "opened db (new, schema v{})", SCHEMA_VERSION);
    } else {
        let v: String = conn
            .query_row(
                "SELECT value FROM meta WHERE key='schema_version'",
                [],
                |r| r.get(0),
            )
            .context("read schema_version")?;
        if v == "2" {
            tracing::info!("migrating schema v2 -> v3");
            migrate_v2_to_v3(&conn)?;
            tracing::info!("migration v2 -> v3 done");
        } else if v != SCHEMA_VERSION {
            bail!(
                "incompatible schema version (db={}, expected={}). Dev mode: delete galaxy.sqlite (and -shm/-wal) and restart.",
                v,
                SCHEMA_VERSION
            );
        } else {
            tracing::info!(path = %path.display(), "opened db (schema v{})", SCHEMA_VERSION);
        }
    }

    let seed_str: String =
        conn.query_row("SELECT value FROM meta WHERE key='galaxy_seed'", [], |r| {
            r.get(0)
        })?;
    let galaxy_seed = u64::from_str_radix(&seed_str, 16).context("parse galaxy_seed")?;

    sync_omega_to_constants(&conn)?;

    Ok(Db { conn, galaxy_seed })
}

fn migrate_v3(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE black_hole (
            id         INTEGER PRIMARY KEY CHECK(id = 0),
            radius     REAL NOT NULL,
            color_json TEXT NOT NULL
        );
        CREATE TABLE solar_systems (
            id             INTEGER PRIMARY KEY,
            seed           INTEGER NOT NULL UNIQUE,
            epoch_ms       INTEGER NOT NULL,
            gx             REAL NOT NULL,
            gy             REAL NOT NULL,
            gz             REAL NOT NULL,
            generated_json TEXT NOT NULL
        );
        CREATE TABLE asteroids (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            system_id     INTEGER NOT NULL REFERENCES solar_systems(id),
            primary_id    INTEGER NOT NULL,
            orbit_radius  REAL NOT NULL,
            orbit_y       REAL NOT NULL,
            phase         REAL NOT NULL,
            omega         REAL NOT NULL,
            radius        REAL NOT NULL,
            color_r       REAL NOT NULL,
            color_g       REAL NOT NULL,
            color_b       REAL NOT NULL,
            kind          TEXT NOT NULL,
            stock         INTEGER NOT NULL
        );
        CREATE INDEX idx_asteroids_system ON asteroids(system_id);
        CREATE TABLE players (
            id           INTEGER PRIMARY KEY,
            name         TEXT NOT NULL UNIQUE,
            spawn_seed   INTEGER NOT NULL,
            spawn_system INTEGER NOT NULL REFERENCES solar_systems(id),
            created_at   TEXT NOT NULL
        );
        CREATE TABLE player_state (
            player_id  INTEGER PRIMARY KEY REFERENCES players(id),
            system_id  INTEGER NOT NULL REFERENCES solar_systems(id),
            x          REAL NOT NULL,
            y          REAL NOT NULL,
            z          REAL NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE player_inventory (
            player_id INTEGER NOT NULL REFERENCES players(id),
            kind      TEXT    NOT NULL,
            amount    INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (player_id, kind)
        );
        "#,
    )?;
    Ok(())
}

fn update_asteroid_omegas(conn: &Connection, k: f32) -> Result<()> {
    let rows: Vec<(i64, f32)> = {
        let mut stmt = conn.prepare("SELECT id, orbit_radius FROM asteroids")?;
        let it = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, f32>(1)?)))?;
        let mut out = Vec::new();
        for row in it {
            out.push(row?);
        }
        out
    };
    let mut stmt = conn.prepare("UPDATE asteroids SET omega = ?1 WHERE id = ?2")?;
    for (id, r) in rows {
        let omega = k / r.max(0.1).sqrt();
        stmt.execute(params![omega, id])?;
    }
    Ok(())
}

fn backfill_asteroid_stock(conn: &Connection) -> Result<()> {
    let rows: Vec<(i64, f32)> = {
        let mut stmt = conn.prepare("SELECT id, radius FROM asteroids")?;
        let it = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, f32>(1)?)))?;
        let mut out = Vec::new();
        for row in it {
            out.push(row?);
        }
        out
    };
    let mut stmt = conn.prepare("UPDATE asteroids SET stock = ?1 WHERE id = ?2")?;
    for (id, radius) in rows {
        let stock = ((radius * radius) * 600.0).ceil().max(1.0) as i32;
        stmt.execute(params![stock, id])?;
    }
    Ok(())
}

fn sync_omega_to_constants(conn: &Connection) -> Result<()> {
    let current: Option<String> = conn
        .query_row(
            "SELECT value FROM meta WHERE key='body_omega_version'",
            [],
            |r| r.get(0),
        )
        .optional()?;
    if current.as_deref() == Some(BODY_OMEGA_VERSION) {
        return Ok(());
    }
    tracing::info!(
        from = ?current,
        to = BODY_OMEGA_VERSION,
        "syncing body omegas to current constants"
    );

    update_asteroid_omegas(conn, BELT_K)?;

    let systems: Vec<(i64, String)> = {
        let mut stmt = conn.prepare("SELECT id, generated_json FROM solar_systems")?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        out
    };
    for (id, json) in systems {
        let mut sys: SolarSystem = match serde_json::from_str(&json) {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!(system_id = id, error = %e, "skipping unparseable system during omega sync");
                continue;
            }
        };
        for p in &mut sys.planets {
            p.omega = ORBIT_K / p.orbit_radius.max(0.1).sqrt();
            for m in &mut p.moons {
                m.omega = MOON_K / m.orbit_radius.max(0.1).sqrt();
            }
        }
        let new_json = serde_json::to_string(&sys)?;
        conn.execute(
            "UPDATE solar_systems SET generated_json = ?1 WHERE id = ?2",
            params![new_json, id],
        )?;
    }
    conn.execute(
        "INSERT INTO meta(key, value) VALUES('body_omega_version', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![BODY_OMEGA_VERSION],
    )?;
    Ok(())
}

fn migrate_v2_to_v3(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        ALTER TABLE asteroids ADD COLUMN kind TEXT NOT NULL DEFAULT 'iron';
        ALTER TABLE asteroids ADD COLUMN stock INTEGER NOT NULL DEFAULT 100;
        CREATE TABLE IF NOT EXISTS player_inventory (
            player_id INTEGER NOT NULL REFERENCES players(id),
            kind      TEXT    NOT NULL,
            amount    INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (player_id, kind)
        );
        "#,
    )?;

    update_asteroid_omegas(conn, BELT_K)?;

    backfill_asteroid_stock(conn)?;

    let systems: Vec<(i64, String)> = {
        let mut stmt = conn.prepare("SELECT id, generated_json FROM solar_systems")?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        out
    };
    for (id, json) in systems {
        let mut sys: SolarSystem = match serde_json::from_str(&json) {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!(system_id = id, error = %e, "skipping unparseable system during migration");
                continue;
            }
        };
        for p in &mut sys.planets {
            p.omega = ORBIT_K / p.orbit_radius.max(0.1).sqrt();
            for m in &mut p.moons {
                m.omega = MOON_K / m.orbit_radius.max(0.1).sqrt();
            }
        }
        let new_json = serde_json::to_string(&sys)?;
        conn.execute(
            "UPDATE solar_systems SET generated_json = ?1 WHERE id = ?2",
            params![new_json, id],
        )?;
    }

    conn.execute(
        "UPDATE meta SET value = ?1 WHERE key = 'schema_version'",
        params![SCHEMA_VERSION],
    )?;
    Ok(())
}

pub struct PlayerSpawn {
    pub player_id: i64,
    pub system: SolarSystem,
    pub asteroids: Vec<Asteroid>,
    pub black_hole: BlackHole,
    pub far_stars: Vec<StarLite>,
    pub inventory: Inventory,
    pub position: [f32; 3],
    pub first_time: bool,
}

pub fn get_or_create_player_spawn(
    conn: &mut Connection,
    galaxy_seed: u64,
    name: &str,
) -> Result<PlayerSpawn> {
    let tx = conn.transaction()?;

    let existing: Option<i64> = tx
        .query_row(
            "SELECT id FROM players WHERE name = ?1",
            params![name],
            |r| r.get(0),
        )
        .optional()?;

    let (player_id, first_time) = match existing {
        Some(pid) => (pid, false),
        None => {
            let spawn_seed: u64 = rand::random();
            let mut grng = ChaCha8Rng::seed_from_u64(galaxy_seed ^ spawn_seed);
            let galactic_pos = [
                grng.gen_range(-50000.0..50000.0),
                grng.gen_range(-2000.0..2000.0),
                grng.gen_range(-50000.0..50000.0),
            ];

            let epoch_ms = Utc::now().timestamp_millis();

            tx.execute(
                "INSERT INTO solar_systems(seed, epoch_ms, gx, gy, gz, generated_json) VALUES(?1,?2,?3,?4,?5,?6)",
                params![
                    spawn_seed as i64,
                    epoch_ms,
                    galactic_pos[0],
                    galactic_pos[1],
                    galactic_pos[2],
                    "{}"
                ],
            )?;
            let system_id = tx.last_insert_rowid();

            let generated = gen_solar_system(spawn_seed, system_id, galactic_pos, epoch_ms);
            let json = serde_json::to_string(&generated.system)?;
            tx.execute(
                "UPDATE solar_systems SET generated_json = ?1 WHERE id = ?2",
                params![json, system_id],
            )?;

            {
                let mut stmt = tx.prepare(
                    "INSERT INTO asteroids(system_id, primary_id, orbit_radius, orbit_y, phase, omega, radius, color_r, color_g, color_b, kind, stock) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",
                )?;
                for s in &generated.asteroid_seeds {
                    stmt.execute(params![
                        system_id,
                        s.primary,
                        s.orbit_radius,
                        s.orbit_y,
                        s.phase,
                        s.omega,
                        s.radius,
                        s.color[0],
                        s.color[1],
                        s.color[2],
                        s.kind.as_str(),
                        s.stock,
                    ])?;
                }
            }

            let now = Utc::now().to_rfc3339();
            tx.execute(
                "INSERT INTO players(name, spawn_seed, spawn_system, created_at) VALUES(?1,?2,?3,?4)",
                params![name, spawn_seed as i64, system_id, now],
            )?;
            let pid = tx.last_insert_rowid();
            tx.execute(
                "INSERT INTO player_state(player_id, system_id, x, y, z, updated_at) VALUES(?1,?2,0,0,0,?3)",
                params![pid, system_id, now],
            )?;
            (pid, true)
        }
    };

    let (sys_id, x, y, z): (i64, f32, f32, f32) = tx.query_row(
        "SELECT system_id, x, y, z FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
    )?;

    let json: String = tx.query_row(
        "SELECT generated_json FROM solar_systems WHERE id = ?1",
        params![sys_id],
        |r| r.get(0),
    )?;
    let mut system: SolarSystem = serde_json::from_str(&json)?;
    system.id = sys_id;

    let asteroids = load_asteroids(&tx, sys_id)?;
    let black_hole = load_black_hole(&tx)?;
    let far_stars = load_far_stars(&tx, sys_id)?;
    let inventory = load_inventory_tx(&tx, player_id)?;

    tx.commit()?;

    Ok(PlayerSpawn {
        player_id,
        system,
        asteroids,
        black_hole,
        far_stars,
        inventory,
        position: [x, y, z],
        first_time,
    })
}

fn load_asteroids(conn: &Connection, system_id: i64) -> Result<Vec<Asteroid>> {
    let mut stmt = conn.prepare(
        "SELECT id, primary_id, orbit_radius, orbit_y, phase, omega, radius, color_r, color_g, color_b, kind, stock FROM asteroids WHERE system_id = ?1",
    )?;
    let rows = stmt.query_map(params![system_id], |r| {
        let kind_str: String = r.get(10)?;
        let kind = AsteroidKind::from_str(&kind_str).unwrap_or(AsteroidKind::Iron);
        Ok(Asteroid {
            id: r.get(0)?,
            system_id,
            primary: r.get(1)?,
            orbit_radius: r.get(2)?,
            orbit_y: r.get(3)?,
            phase: r.get(4)?,
            omega: r.get(5)?,
            radius: r.get(6)?,
            color: [r.get(7)?, r.get(8)?, r.get(9)?],
            kind,
            stock: r.get(11)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

fn load_black_hole(conn: &Connection) -> Result<BlackHole> {
    let (id, radius, color_json): (i64, f32, String) = conn.query_row(
        "SELECT id, radius, color_json FROM black_hole WHERE id = ?1",
        params![BLACK_HOLE_ID],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
    )?;
    let color: [f32; 3] = serde_json::from_str(&color_json)?;
    Ok(BlackHole { id, radius, color })
}

fn load_far_stars(conn: &Connection, exclude_system_id: i64) -> Result<Vec<StarLite>> {
    let mut stmt = conn.prepare("SELECT id, generated_json FROM solar_systems WHERE id != ?1")?;
    let rows = stmt.query_map(params![exclude_system_id], |r| {
        let id: i64 = r.get(0)?;
        let json: String = r.get(1)?;
        Ok((id, json))
    })?;
    let mut out = Vec::new();
    for row in rows {
        let (sys_id, json) = row?;
        let sys: SolarSystem = match serde_json::from_str(&json) {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!(error = %e, system_id = sys_id, "skipping unparseable system");
                continue;
            }
        };
        out.push(StarLite {
            id: sys.star.id,
            name: sys.star.name,
            galactic_pos: sys.star.galactic_pos,
            radius: sys.star.radius,
            color: sys.star.color,
        });
    }
    Ok(out)
}

fn load_inventory_tx(tx: &Transaction, player_id: i64) -> Result<Inventory> {
    let mut inv = Inventory::default();
    let mut stmt = tx.prepare("SELECT kind, amount FROM player_inventory WHERE player_id = ?1")?;
    let rows = stmt.query_map(params![player_id], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
    })?;
    for row in rows {
        let (kind_str, amount) = row?;
        if let Some(k) = AsteroidKind::from_str(&kind_str) {
            inv.add(k, amount);
        }
    }
    Ok(inv)
}

fn load_inventory_conn(conn: &Connection, player_id: i64) -> Result<Inventory> {
    let mut inv = Inventory::default();
    let mut stmt =
        conn.prepare("SELECT kind, amount FROM player_inventory WHERE player_id = ?1")?;
    let rows = stmt.query_map(params![player_id], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
    })?;
    for row in rows {
        let (kind_str, amount) = row?;
        if let Some(k) = AsteroidKind::from_str(&kind_str) {
            inv.add(k, amount);
        }
    }
    Ok(inv)
}

pub enum MineOutcome {
    Tick {
        kind: AsteroidKind,
        gained: i32,
        remaining: i32,
        inventory: Inventory,
    },
    Depleted {
        kind: AsteroidKind,
        gained: i32,
        inventory: Inventory,
    },
    Reject(String),
}

pub fn mine_asteroid(
    conn: &mut Connection,
    player_id: i64,
    asteroid_id: i64,
) -> Result<MineOutcome> {
    let tx = conn.transaction()?;

    let player_system: i64 = tx.query_row(
        "SELECT system_id FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| r.get(0),
    )?;

    let asteroid_row: Option<(i64, String, i32)> = tx
        .query_row(
            "SELECT system_id, kind, stock FROM asteroids WHERE id = ?1",
            params![asteroid_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?;

    let (sys_id, kind_str, stock) = match asteroid_row {
        Some(t) => t,
        None => {
            tx.commit()?;
            return Ok(MineOutcome::Reject("asteroid_not_found".into()));
        }
    };
    if sys_id != player_system {
        tx.commit()?;
        return Ok(MineOutcome::Reject("wrong_system".into()));
    }
    let kind = match AsteroidKind::from_str(&kind_str) {
        Some(k) => k,
        None => {
            tx.commit()?;
            return Ok(MineOutcome::Reject("bad_kind".into()));
        }
    };

    let gained = MINE_TICK_AMOUNT.min(stock);
    let new_stock = stock - gained;

    tx.execute(
        "INSERT INTO player_inventory(player_id, kind, amount) VALUES(?1, ?2, ?3)
         ON CONFLICT(player_id, kind) DO UPDATE SET amount = amount + excluded.amount",
        params![player_id, kind.as_str(), gained as i64],
    )?;

    let outcome = if new_stock <= 0 {
        tx.execute("DELETE FROM asteroids WHERE id = ?1", params![asteroid_id])?;
        let inventory = load_inventory_tx(&tx, player_id)?;
        MineOutcome::Depleted {
            kind,
            gained,
            inventory,
        }
    } else {
        tx.execute(
            "UPDATE asteroids SET stock = ?1 WHERE id = ?2",
            params![new_stock, asteroid_id],
        )?;
        let inventory = load_inventory_tx(&tx, player_id)?;
        MineOutcome::Tick {
            kind,
            gained,
            remaining: new_stock,
            inventory,
        }
    };

    tx.commit()?;
    Ok(outcome)
}

#[allow(dead_code)]
pub fn load_inventory(conn: &Connection, player_id: i64) -> Result<Inventory> {
    load_inventory_conn(conn, player_id)
}
