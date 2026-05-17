use anyhow::{bail, Context, Result};
use chrono::Utc;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use std::path::Path;

use crate::world::gen::{
    gen_solar_system, BELT_K, BLACK_HOLE_ID, BODY_OMEGA_VERSION, MOON_K, ORBIT_K,
};
use crate::world::types::{
    Asteroid, AsteroidKind, BlackHole, Drone, Factory, Inventory, SolarSystem, StarLite,
    DRONE_ACCEL, DRONE_COST, DRONE_FORMATION_HEIGHT, DRONE_FORMATION_RADIUS, DRONE_MINE_AMOUNT,
    DRONE_MINE_INTERVAL_MS, DRONE_MINE_RANGE, DRONE_RETURN_TOLERANCE, DRONE_SPEED, FACTORY_COST,
};

const SCHEMA_VERSION: &str = "6";
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
        migrate_fresh(&conn)?;
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
            tracing::info!("migrating schema v3 -> v4");
            migrate_v3_to_v4(&conn)?;
            tracing::info!("migration v3 -> v4 done");
            tracing::info!("migrating schema v4 -> v5");
            migrate_v4_to_v5(&conn)?;
            tracing::info!("migration v4 -> v5 done");
            tracing::info!("migrating schema v5 -> v6");
            migrate_v5_to_v6(&conn)?;
            tracing::info!("migration v5 -> v6 done");
        } else if v == "3" {
            tracing::info!("migrating schema v3 -> v4");
            migrate_v3_to_v4(&conn)?;
            tracing::info!("migration v3 -> v4 done");
            tracing::info!("migrating schema v4 -> v5");
            migrate_v4_to_v5(&conn)?;
            tracing::info!("migration v4 -> v5 done");
            tracing::info!("migrating schema v5 -> v6");
            migrate_v5_to_v6(&conn)?;
            tracing::info!("migration v5 -> v6 done");
        } else if v == "4" {
            tracing::info!("migrating schema v4 -> v5");
            migrate_v4_to_v5(&conn)?;
            tracing::info!("migration v4 -> v5 done");
            tracing::info!("migrating schema v5 -> v6");
            migrate_v5_to_v6(&conn)?;
            tracing::info!("migration v5 -> v6 done");
        } else if v == "5" {
            tracing::info!("migrating schema v5 -> v6");
            migrate_v5_to_v6(&conn)?;
            tracing::info!("migration v5 -> v6 done");
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

fn migrate_fresh(conn: &Connection) -> Result<()> {
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
        CREATE TABLE player_drones (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id       INTEGER NOT NULL REFERENCES players(id),
            kind            TEXT NOT NULL,
            created_at      TEXT NOT NULL,
            pos_x           REAL NOT NULL DEFAULT 0,
            pos_y           REAL NOT NULL DEFAULT 0,
            pos_z           REAL NOT NULL DEFAULT 0,
            vel_x           REAL NOT NULL DEFAULT 0,
            vel_y           REAL NOT NULL DEFAULT 0,
            vel_z           REAL NOT NULL DEFAULT 0,
            state           TEXT NOT NULL DEFAULT 'idle',
            target_asteroid INTEGER NULL
        );
        CREATE INDEX idx_player_drones_player ON player_drones(player_id);
        CREATE TABLE player_factories (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id  INTEGER NOT NULL REFERENCES players(id),
            kind       TEXT NOT NULL,
            created_at TEXT NOT NULL,
            pos_x      REAL NOT NULL,
            pos_y      REAL NOT NULL,
            pos_z      REAL NOT NULL
        );
        CREATE INDEX idx_player_factories_player ON player_factories(player_id);
        "#,
    )?;
    Ok(())
}

fn migrate_v3_to_v4(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS player_drones (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id       INTEGER NOT NULL REFERENCES players(id),
            kind            TEXT NOT NULL,
            created_at      TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_player_drones_player ON player_drones(player_id);
        CREATE TABLE IF NOT EXISTS player_factories (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id  INTEGER NOT NULL REFERENCES players(id),
            kind       TEXT NOT NULL,
            created_at TEXT NOT NULL,
            pos_x      REAL NOT NULL,
            pos_y      REAL NOT NULL,
            pos_z      REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_player_factories_player ON player_factories(player_id);
        "#,
    )?;
    conn.execute(
        "UPDATE meta SET value = '4' WHERE key = 'schema_version'",
        [],
    )?;
    Ok(())
}

fn migrate_v4_to_v5(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        ALTER TABLE player_drones ADD COLUMN pos_x REAL NOT NULL DEFAULT 0;
        ALTER TABLE player_drones ADD COLUMN pos_y REAL NOT NULL DEFAULT 0;
        ALTER TABLE player_drones ADD COLUMN pos_z REAL NOT NULL DEFAULT 0;
        ALTER TABLE player_drones ADD COLUMN state TEXT NOT NULL DEFAULT 'idle';
        ALTER TABLE player_drones ADD COLUMN target_asteroid INTEGER NULL;
        "#,
    )?;
    conn.execute(
        "UPDATE meta SET value = '5' WHERE key = 'schema_version'",
        [],
    )?;
    Ok(())
}

fn migrate_v5_to_v6(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        ALTER TABLE player_drones ADD COLUMN vel_x REAL NOT NULL DEFAULT 0;
        ALTER TABLE player_drones ADD COLUMN vel_y REAL NOT NULL DEFAULT 0;
        ALTER TABLE player_drones ADD COLUMN vel_z REAL NOT NULL DEFAULT 0;
        "#,
    )?;
    conn.execute(
        "UPDATE meta SET value = '6' WHERE key = 'schema_version'",
        [],
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
        "UPDATE meta SET value = '3' WHERE key = 'schema_version'",
        [],
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
    pub drones: Vec<Drone>,
    pub factories: Vec<Factory>,
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
    let drones = load_drones_tx(&tx, player_id)?;
    let factories = load_factories_tx(&tx, player_id)?;

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
        drones,
        factories,
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

fn load_drones_tx(tx: &Transaction, player_id: i64) -> Result<Vec<Drone>> {
    let mut stmt = tx.prepare(
        "SELECT id, kind, created_at, pos_x, pos_y, pos_z, vel_x, vel_y, vel_z, state, target_asteroid \
         FROM player_drones WHERE player_id = ?1 ORDER BY id",
    )?;
    let rows = stmt.query_map(params![player_id], |r| {
        Ok(Drone {
            id: r.get(0)?,
            kind: r.get(1)?,
            created_at: r.get(2)?,
            position: [r.get(3)?, r.get(4)?, r.get(5)?],
            velocity: [r.get(6)?, r.get(7)?, r.get(8)?],
            state: r.get(9)?,
            target_asteroid: r.get(10)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

fn load_drones_conn(conn: &Connection, player_id: i64) -> Result<Vec<Drone>> {
    let mut stmt = conn.prepare(
        "SELECT id, kind, created_at, pos_x, pos_y, pos_z, vel_x, vel_y, vel_z, state, target_asteroid \
         FROM player_drones WHERE player_id = ?1 ORDER BY id",
    )?;
    let rows = stmt.query_map(params![player_id], |r| {
        Ok(Drone {
            id: r.get(0)?,
            kind: r.get(1)?,
            created_at: r.get(2)?,
            position: [r.get(3)?, r.get(4)?, r.get(5)?],
            velocity: [r.get(6)?, r.get(7)?, r.get(8)?],
            state: r.get(9)?,
            target_asteroid: r.get(10)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

fn load_factories_tx(tx: &Transaction, player_id: i64) -> Result<Vec<Factory>> {
    let mut stmt = tx.prepare(
        "SELECT id, kind, created_at, pos_x, pos_y, pos_z FROM player_factories WHERE player_id = ?1 ORDER BY id",
    )?;
    let rows = stmt.query_map(params![player_id], |r| {
        Ok(Factory {
            id: r.get(0)?,
            kind: r.get(1)?,
            created_at: r.get(2)?,
            position: [r.get(3)?, r.get(4)?, r.get(5)?],
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

pub enum BuildOutcome {
    Ok {
        inventory: Inventory,
        drones: Vec<Drone>,
        factories: Vec<Factory>,
    },
    Insufficient {
        inventory: Inventory,
        drones: Vec<Drone>,
        factories: Vec<Factory>,
    },
    UnknownItem,
}

pub fn build_item(conn: &mut Connection, player_id: i64, item: &str) -> Result<BuildOutcome> {
    let costs: &[(AsteroidKind, i64)] = match item {
        "drone" => DRONE_COST,
        "factory" => FACTORY_COST,
        _ => return Ok(BuildOutcome::UnknownItem),
    };

    let tx = conn.transaction()?;

    let mut inv = load_inventory_tx(&tx, player_id)?;
    if !inv.try_consume(costs) {
        let drones = load_drones_tx(&tx, player_id)?;
        let factories = load_factories_tx(&tx, player_id)?;
        tx.commit()?;
        return Ok(BuildOutcome::Insufficient {
            inventory: inv,
            drones,
            factories,
        });
    }

    {
        let mut up = tx.prepare(
            "INSERT INTO player_inventory(player_id, kind, amount) VALUES(?1, ?2, ?3)
             ON CONFLICT(player_id, kind) DO UPDATE SET amount = excluded.amount",
        )?;
        for (k, _) in costs {
            up.execute(params![player_id, k.as_str(), inv.get(*k)])?;
        }
    }

    let now = Utc::now().to_rfc3339();
    match item {
        "drone" => {
            let (px, py, pz): (f32, f32, f32) = tx.query_row(
                "SELECT x, y, z FROM player_state WHERE player_id = ?1",
                params![player_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )?;
            tx.execute(
                "INSERT INTO player_drones(player_id, kind, created_at, pos_x, pos_y, pos_z, state) \
                 VALUES(?1, ?2, ?3, ?4, ?5, ?6, 'idle')",
                params![player_id, "miner", now, px, py + DRONE_FORMATION_HEIGHT, pz],
            )?;
        }
        "factory" => {
            let (x, y, z): (f32, f32, f32) = tx.query_row(
                "SELECT x, y, z FROM player_state WHERE player_id = ?1",
                params![player_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )?;
            tx.execute(
                "INSERT INTO player_factories(player_id, kind, created_at, pos_x, pos_y, pos_z) VALUES(?1, ?2, ?3, ?4, ?5, ?6)",
                params![player_id, "drone_factory", now, x, y, z],
            )?;
        }
        _ => unreachable!(),
    }

    let inventory = load_inventory_tx(&tx, player_id)?;
    let drones = load_drones_tx(&tx, player_id)?;
    let factories = load_factories_tx(&tx, player_id)?;
    tx.commit()?;
    Ok(BuildOutcome::Ok {
        inventory,
        drones,
        factories,
    })
}

pub enum OrderOutcome {
    Ok {
        affected: usize,
        drones: Vec<Drone>,
        inventory: Inventory,
    },
    Reject(String),
}

pub fn order_drone(
    conn: &mut Connection,
    player_id: i64,
    drone_id: i64,
    order: &str,
    position: Option<[f32; 3]>,
) -> Result<OrderOutcome> {
    let tx = conn.transaction()?;
    if let Some(p) = position {
        tx.execute(
            "UPDATE player_state SET x = ?1, y = ?2, z = ?3 WHERE player_id = ?4",
            params![p[0], p[1], p[2], player_id],
        )?;
    }
    let player_system: i64 = tx.query_row(
        "SELECT system_id FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| r.get(0),
    )?;
    let drone_row: Option<(i64,)> = tx
        .query_row(
            "SELECT id FROM player_drones WHERE id = ?1 AND player_id = ?2",
            params![drone_id, player_id],
            |r| Ok((r.get(0)?,)),
        )
        .optional()?;
    if drone_row.is_none() {
        tx.commit()?;
        return Ok(OrderOutcome::Reject("drone_not_found".into()));
    }

    let now_secs: f32 = (Utc::now().timestamp_millis() as f64 / 1000.0) as f32;
    let affected = match order {
        "mine_nearest" => {
            let (px, py, pz): (f32, f32, f32) = tx.query_row(
                "SELECT x, y, z FROM player_state WHERE player_id = ?1",
                params![player_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )?;
            let mut exclude = already_targeted_asteroids(&tx, player_id)?;
            exclude.retain(|&aid| {
                tx.query_row(
                    "SELECT target_asteroid FROM player_drones WHERE id = ?1",
                    params![drone_id],
                    |r| r.get::<_, Option<i64>>(0),
                )
                .ok()
                .flatten()
                .map(|own| own != aid)
                .unwrap_or(true)
            });
            match nearest_alive_asteroid_filtered(
                &tx,
                player_system,
                [px, py, pz],
                now_secs,
                &exclude,
                None,
            )? {
                Some(aid) => {
                    let (slot_x, slot_y, slot_z) =
                        compute_slot_pos(&tx, player_id, drone_id, px, py, pz)?;
                    tx.execute(
                        "UPDATE player_drones SET state = 'to_target', target_asteroid = ?1, \
                         pos_x = ?2, pos_y = ?3, pos_z = ?4, vel_x = 0, vel_y = 0, vel_z = 0 WHERE id = ?5",
                        params![aid, slot_x, slot_y, slot_z, drone_id],
                    )?;
                    1usize
                }
                None => {
                    tx.commit()?;
                    return Ok(OrderOutcome::Reject("no_asteroid".into()));
                }
            }
        }
        "idle" => {
            tx.execute(
                "UPDATE player_drones SET state = 'returning', target_asteroid = NULL WHERE id = ?1",
                params![drone_id],
            )?;
            1usize
        }
        _ => {
            tx.commit()?;
            return Ok(OrderOutcome::Reject("unknown_order".into()));
        }
    };
    let drones = load_drones_tx(&tx, player_id)?;
    let inventory = load_inventory_tx(&tx, player_id)?;
    tx.commit()?;
    Ok(OrderOutcome::Ok {
        affected,
        drones,
        inventory,
    })
}

pub fn order_all_drones(
    conn: &mut Connection,
    player_id: i64,
    order: &str,
    kind: Option<&str>,
    position: Option<[f32; 3]>,
) -> Result<OrderOutcome> {
    let tx = conn.transaction()?;
    if let Some(p) = position {
        tx.execute(
            "UPDATE player_state SET x = ?1, y = ?2, z = ?3 WHERE player_id = ?4",
            params![p[0], p[1], p[2], player_id],
        )?;
    }
    let player_system: i64 = tx.query_row(
        "SELECT system_id FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| r.get(0),
    )?;
    let now_secs: f32 = (Utc::now().timestamp_millis() as f64 / 1000.0) as f32;

    let affected: usize = match order {
        "mine_distinct" | "mine_nearest" => assign_strategy(
            &tx,
            player_id,
            player_system,
            now_secs,
            AssignStrategy::Distinct,
        )?,
        "mine_kind" => {
            let kf = kind.unwrap_or("iron");
            if AsteroidKind::from_str(kf).is_none() {
                tx.commit()?;
                return Ok(OrderOutcome::Reject("unknown_kind".into()));
            }
            assign_strategy(
                &tx,
                player_id,
                player_system,
                now_secs,
                AssignStrategy::SameKind(kf.to_string()),
            )?
        }
        "spread_kinds" => assign_strategy(
            &tx,
            player_id,
            player_system,
            now_secs,
            AssignStrategy::SpreadKinds,
        )?,
        "idle" => tx.execute(
            "UPDATE player_drones SET state = 'returning', target_asteroid = NULL \
             WHERE player_id = ?1 AND state IN ('to_target', 'mining')",
            params![player_id],
        )?,
        _ => {
            tx.commit()?;
            return Ok(OrderOutcome::Reject("unknown_order".into()));
        }
    };
    if affected == 0 && order != "idle" {
        let drones = load_drones_tx(&tx, player_id)?;
        let inventory = load_inventory_tx(&tx, player_id)?;
        tx.commit()?;
        return Ok(OrderOutcome::Ok {
            affected,
            drones,
            inventory,
        });
    }
    let drones = load_drones_tx(&tx, player_id)?;
    let inventory = load_inventory_tx(&tx, player_id)?;
    tx.commit()?;
    Ok(OrderOutcome::Ok {
        affected,
        drones,
        inventory,
    })
}

fn compute_slot_pos(
    tx: &Transaction,
    player_id: i64,
    drone_id: i64,
    px: f32,
    py: f32,
    pz: f32,
) -> Result<(f32, f32, f32)> {
    let (idx, total): (i64, i64) = tx.query_row(
        "WITH ordered AS (\
            SELECT id, ROW_NUMBER() OVER (ORDER BY id) - 1 AS rn, COUNT(*) OVER () AS total \
            FROM player_drones WHERE player_id = ?1 \
         ) SELECT rn, total FROM ordered WHERE id = ?2",
        params![player_id, drone_id],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    let total_f = total.max(1) as f32;
    let slot_angle = std::f32::consts::TAU * (idx as f32) / total_f;
    Ok((
        px + slot_angle.cos() * DRONE_FORMATION_RADIUS,
        py + DRONE_FORMATION_HEIGHT,
        pz + slot_angle.sin() * DRONE_FORMATION_RADIUS,
    ))
}

enum AssignStrategy {
    Distinct,
    SameKind(String),
    SpreadKinds,
}

fn assign_strategy(
    tx: &Transaction,
    player_id: i64,
    player_system: i64,
    now_secs: f32,
    strategy: AssignStrategy,
) -> Result<usize> {
    let (px, py, pz): (f32, f32, f32) = tx.query_row(
        "SELECT x, y, z FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
    )?;
    let from = [px, py, pz];

    // Charger tous les drones du joueur dans l'ordre stable (id) pour avoir
    // l'index de slot de formation cohérent avec ce que tick_drones utilise.
    let all_drones: Vec<(i64, String)> = {
        let mut stmt = tx.prepare(
            "SELECT id, state FROM player_drones WHERE player_id = ?1 ORDER BY id",
        )?;
        let it = stmt.query_map(params![player_id], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
        })?;
        let mut v = Vec::new();
        for row in it {
            v.push(row?);
        }
        v
    };
    if all_drones.is_empty() {
        return Ok(0);
    }
    let total = all_drones.len();
    let drone_rows: Vec<(i64, usize)> = all_drones
        .iter()
        .enumerate()
        .filter(|(_, (_, st))| st == "idle" || st == "returning")
        .map(|(idx, (id, _))| (*id, idx))
        .collect();
    if drone_rows.is_empty() {
        return Ok(0);
    }

    let mut already = already_targeted_asteroids(tx, player_id)?;
    let kind_cycle = ["iron", "copper", "silicon", "ice"];
    let mut cycle_idx: usize = 0;
    let mut affected: usize = 0;

    for (did, slot_idx) in drone_rows {
        let kind_filter: Option<String> = match &strategy {
            AssignStrategy::Distinct => None,
            AssignStrategy::SameKind(k) => Some(k.clone()),
            AssignStrategy::SpreadKinds => {
                let mut chosen: Option<String> = None;
                for _ in 0..kind_cycle.len() {
                    let k = kind_cycle[cycle_idx % kind_cycle.len()];
                    cycle_idx += 1;
                    if nearest_alive_asteroid_filtered(
                        tx,
                        player_system,
                        from,
                        now_secs,
                        &already,
                        Some(k),
                    )?
                    .is_some()
                    {
                        chosen = Some(k.to_string());
                        break;
                    }
                }
                chosen
            }
        };
        let aid_opt = nearest_alive_asteroid_filtered(
            tx,
            player_system,
            from,
            now_secs,
            &already,
            kind_filter.as_deref(),
        )?;
        let aid = match aid_opt {
            Some(a) => a,
            None => continue,
        };
        let slot_angle = std::f32::consts::TAU * (slot_idx as f32) / (total.max(1) as f32);
        let slot_x = px + slot_angle.cos() * DRONE_FORMATION_RADIUS;
        let slot_y = py + DRONE_FORMATION_HEIGHT;
        let slot_z = pz + slot_angle.sin() * DRONE_FORMATION_RADIUS;
        tx.execute(
            "UPDATE player_drones SET state = 'to_target', target_asteroid = ?1, \
             pos_x = ?2, pos_y = ?3, pos_z = ?4, vel_x = 0, vel_y = 0, vel_z = 0 WHERE id = ?5",
            params![aid, slot_x, slot_y, slot_z, did],
        )?;
        already.push(aid);
        affected += 1;
    }
    Ok(affected)
}

fn asteroid_world_pos(orbit_radius: f32, orbit_y: f32, phase: f32, omega: f32, t: f32) -> [f32; 3] {
    let angle = phase + omega * t;
    [
        angle.cos() * orbit_radius,
        orbit_y,
        angle.sin() * orbit_radius,
    ]
}

fn nearest_alive_asteroid_filtered(
    tx: &Transaction,
    system_id: i64,
    from: [f32; 3],
    t: f32,
    exclude: &[i64],
    kind_filter: Option<&str>,
) -> Result<Option<i64>> {
    let mut stmt = tx.prepare(
        "SELECT id, orbit_radius, orbit_y, phase, omega, stock, kind FROM asteroids WHERE system_id = ?1",
    )?;
    let rows = stmt.query_map(params![system_id], |r| {
        Ok((
            r.get::<_, i64>(0)?,
            r.get::<_, f32>(1)?,
            r.get::<_, f32>(2)?,
            r.get::<_, f32>(3)?,
            r.get::<_, f32>(4)?,
            r.get::<_, i32>(5)?,
            r.get::<_, String>(6)?,
        ))
    })?;
    let mut best_id: Option<i64> = None;
    let mut best_d2: f32 = f32::INFINITY;
    for row in rows {
        let (id, r, y, phase, omega, stock, kind) = row?;
        if stock <= 0 {
            continue;
        }
        if exclude.contains(&id) {
            continue;
        }
        if let Some(kf) = kind_filter {
            if kind != kf {
                continue;
            }
        }
        let p = asteroid_world_pos(r, y, phase, omega, t);
        let dx = p[0] - from[0];
        let dy = p[1] - from[1];
        let dz = p[2] - from[2];
        let d2 = dx * dx + dy * dy + dz * dz;
        if d2 < best_d2 {
            best_d2 = d2;
            best_id = Some(id);
        }
    }
    Ok(best_id)
}

fn already_targeted_asteroids(tx: &Transaction, player_id: i64) -> Result<Vec<i64>> {
    let mut stmt = tx.prepare(
        "SELECT target_asteroid FROM player_drones WHERE player_id = ?1 AND target_asteroid IS NOT NULL",
    )?;
    let rows = stmt.query_map(params![player_id], |r| r.get::<_, i64>(0))?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

pub struct DroneTickResult {
    pub drones: Vec<Drone>,
    pub inventory: Inventory,
    pub changed: bool,
}

pub fn tick_drones(conn: &mut Connection, player_id: i64, dt: f32) -> Result<DroneTickResult> {
    let tx = conn.transaction()?;
    let (player_system, px, py, pz): (i64, f32, f32, f32) = tx.query_row(
        "SELECT system_id, x, y, z FROM player_state WHERE player_id = ?1",
        params![player_id],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
    )?;
    let now_ms = Utc::now().timestamp_millis();
    let now_secs: f32 = (now_ms as f64 / 1000.0) as f32;

    let mut drones = load_drones_tx(&tx, player_id)?;
    if drones.is_empty() {
        let inventory = load_inventory_tx(&tx, player_id)?;
        tx.commit()?;
        return Ok(DroneTickResult {
            drones,
            inventory,
            changed: false,
        });
    }

    let total = drones.len();
    let mut changed = false;

    #[allow(clippy::needless_range_loop)]
    for i in 0..total {
        let mut d = drones[i].clone();
        let slot_angle = std::f32::consts::TAU * (i as f32) / (total.max(1) as f32);
        let slot_pos: [f32; 3] = [
            px + slot_angle.cos() * DRONE_FORMATION_RADIUS,
            py + DRONE_FORMATION_HEIGHT,
            pz + slot_angle.sin() * DRONE_FORMATION_RADIUS,
        ];

        match d.state.as_str() {
            "idle" => {
                // No-op: client owns the formation animation. Skip emitting.
            }
            "to_target" => {
                let aid = match d.target_asteroid {
                    Some(a) => a,
                    None => {
                        d.state = "returning".into();
                        changed = true;
                        drones[i] = d;
                        continue;
                    }
                };
                let ast: Option<(f32, f32, f32, f32, i32)> = tx
                    .query_row(
                        "SELECT orbit_radius, orbit_y, phase, omega, stock FROM asteroids \
                         WHERE id = ?1 AND system_id = ?2",
                        params![aid, player_system],
                        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
                    )
                    .optional()?;
                let (r, y, phase, omega, stock) = match ast {
                    Some(t) => t,
                    None => {
                        d.state = "returning".into();
                        d.target_asteroid = None;
                        changed = true;
                        drones[i] = d;
                        continue;
                    }
                };
                if stock <= 0 {
                    d.state = "returning".into();
                    d.target_asteroid = None;
                    changed = true;
                    drones[i] = d;
                    continue;
                }
                let target = asteroid_world_pos(r, y, phase, omega, now_secs);
                let (npos, nvel, ndist) = accel_step(d.position, d.velocity, target, dt);
                d.position = npos;
                d.velocity = nvel;
                if ndist <= DRONE_MINE_RANGE {
                    d.state = "mining".into();
                    d.velocity = [0.0, 0.0, 0.0];
                }
                changed = true;
            }
            "mining" => {
                let aid = match d.target_asteroid {
                    Some(a) => a,
                    None => {
                        d.state = "returning".into();
                        changed = true;
                        drones[i] = d;
                        continue;
                    }
                };
                let ast: Option<(String, i32, f32, f32, f32, f32)> = tx
                    .query_row(
                        "SELECT kind, stock, orbit_radius, orbit_y, phase, omega FROM asteroids \
                         WHERE id = ?1 AND system_id = ?2",
                        params![aid, player_system],
                        |r| {
                            Ok((
                                r.get(0)?,
                                r.get(1)?,
                                r.get(2)?,
                                r.get(3)?,
                                r.get(4)?,
                                r.get(5)?,
                            ))
                        },
                    )
                    .optional()?;
                let (kind_str, stock, r, y, phase, omega) = match ast {
                    Some(t) => t,
                    None => {
                        d.state = "returning".into();
                        d.target_asteroid = None;
                        changed = true;
                        drones[i] = d;
                        continue;
                    }
                };
                let target = asteroid_world_pos(r, y, phase, omega, now_secs);
                let dx = target[0] - d.position[0];
                let dy = target[1] - d.position[1];
                let dz = target[2] - d.position[2];
                let dist = (dx * dx + dy * dy + dz * dz).sqrt();
                if dist > DRONE_MINE_RANGE * 1.2 {
                    d.state = "to_target".into();
                    changed = true;
                    drones[i] = d;
                    continue;
                }
                let last_key = format!("drone_last_mine_{}", d.id);
                let last: i64 = tx
                    .query_row(
                        "SELECT value FROM meta WHERE key = ?1",
                        params![&last_key],
                        |r| r.get::<_, String>(0),
                    )
                    .optional()?
                    .and_then(|s| s.parse::<i64>().ok())
                    .unwrap_or(0);
                if now_ms - last >= DRONE_MINE_INTERVAL_MS {
                    let gained = DRONE_MINE_AMOUNT.min(stock);
                    let new_stock = stock - gained;
                    let kind = AsteroidKind::from_str(&kind_str).unwrap_or(AsteroidKind::Iron);
                    tx.execute(
                        "INSERT INTO player_inventory(player_id, kind, amount) VALUES(?1, ?2, ?3) \
                         ON CONFLICT(player_id, kind) DO UPDATE SET amount = amount + excluded.amount",
                        params![player_id, kind.as_str(), gained as i64],
                    )?;
                    if new_stock <= 0 {
                        tx.execute("DELETE FROM asteroids WHERE id = ?1", params![aid])?;
                        d.state = "returning".into();
                        d.target_asteroid = None;
                    } else {
                        tx.execute(
                            "UPDATE asteroids SET stock = ?1 WHERE id = ?2",
                            params![new_stock, aid],
                        )?;
                    }
                    tx.execute(
                        "INSERT INTO meta(key, value) VALUES(?1, ?2) \
                         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                        params![&last_key, now_ms.to_string()],
                    )?;
                    changed = true;
                }
            }
            "returning" => {
                let (npos, nvel, ndist) = accel_step(d.position, d.velocity, slot_pos, dt);
                d.position = npos;
                d.velocity = nvel;
                if ndist <= DRONE_RETURN_TOLERANCE {
                    d.state = "idle".into();
                    d.target_asteroid = None;
                    d.velocity = [0.0, 0.0, 0.0];
                }
                changed = true;
            }
            _ => {
                d.state = "idle".into();
                changed = true;
            }
        }
        drones[i] = d;
    }

    if changed {
        let mut up = tx.prepare(
            "UPDATE player_drones SET pos_x = ?1, pos_y = ?2, pos_z = ?3, vel_x = ?4, vel_y = ?5, vel_z = ?6, state = ?7, target_asteroid = ?8 WHERE id = ?9",
        )?;
        for d in &drones {
            up.execute(params![
                d.position[0],
                d.position[1],
                d.position[2],
                d.velocity[0],
                d.velocity[1],
                d.velocity[2],
                d.state,
                d.target_asteroid,
                d.id
            ])?;
        }
    }

    let inventory = load_inventory_tx(&tx, player_id)?;
    tx.commit()?;
    Ok(DroneTickResult {
        drones,
        inventory,
        changed,
    })
}

fn accel_step(
    pos: [f32; 3],
    vel: [f32; 3],
    target: [f32; 3],
    dt: f32,
) -> ([f32; 3], [f32; 3], f32) {
    let to = [target[0] - pos[0], target[1] - pos[1], target[2] - pos[2]];
    let dist = (to[0] * to[0] + to[1] * to[1] + to[2] * to[2]).sqrt();
    if dist < 0.0001 {
        return (target, [0.0, 0.0, 0.0], 0.0);
    }
    let dir = [to[0] / dist, to[1] / dist, to[2] / dist];
    let brake_speed = (2.0 * DRONE_ACCEL * dist).sqrt();
    let speed_cap = DRONE_SPEED.min(brake_speed);
    let desired_vel = [dir[0] * speed_cap, dir[1] * speed_cap, dir[2] * speed_cap];
    let dvx = desired_vel[0] - vel[0];
    let dvy = desired_vel[1] - vel[1];
    let dvz = desired_vel[2] - vel[2];
    let dvl = (dvx * dvx + dvy * dvy + dvz * dvz).sqrt();
    let max_dv = DRONE_ACCEL * dt;
    let new_vel = if dvl > max_dv && dvl > 0.0001 {
        [
            vel[0] + dvx * max_dv / dvl,
            vel[1] + dvy * max_dv / dvl,
            vel[2] + dvz * max_dv / dvl,
        ]
    } else {
        desired_vel
    };
    let new_pos = [
        pos[0] + new_vel[0] * dt,
        pos[1] + new_vel[1] * dt,
        pos[2] + new_vel[2] * dt,
    ];
    let nx = target[0] - new_pos[0];
    let ny = target[1] - new_pos[1];
    let nz = target[2] - new_pos[2];
    let new_dist = (nx * nx + ny * ny + nz * nz).sqrt();
    (new_pos, new_vel, new_dist)
}

#[allow(dead_code)]
pub fn load_drones(conn: &Connection, player_id: i64) -> Result<Vec<Drone>> {
    load_drones_conn(conn, player_id)
}

pub fn cheat_grant_resources(
    conn: &mut Connection,
    player_id: i64,
    amount: i64,
) -> Result<(Inventory, Vec<Drone>, Vec<Factory>)> {
    let tx = conn.transaction()?;
    {
        let mut up = tx.prepare(
            "INSERT INTO player_inventory(player_id, kind, amount) VALUES(?1, ?2, ?3) \
             ON CONFLICT(player_id, kind) DO UPDATE SET amount = amount + excluded.amount",
        )?;
        for k in ["iron", "copper", "silicon", "ice"] {
            up.execute(params![player_id, k, amount])?;
        }
    }
    let inventory = load_inventory_tx(&tx, player_id)?;
    let drones = load_drones_tx(&tx, player_id)?;
    let factories = load_factories_tx(&tx, player_id)?;
    tx.commit()?;
    Ok((inventory, drones, factories))
}
