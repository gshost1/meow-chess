//! Bitboard helpers and precomputed attack tables.
//!
//! Squares are numbered 0 = a1, 1 = b1, ... 63 = h8.

use std::sync::OnceLock;

pub type Bitboard = u64;

pub const FILE_A: Bitboard = 0x0101_0101_0101_0101;
pub const FILE_H: Bitboard = FILE_A << 7;
pub const RANK_1: Bitboard = 0xFF;
pub const RANK_2: Bitboard = RANK_1 << 8;
pub const RANK_7: Bitboard = RANK_1 << 48;
pub const RANK_8: Bitboard = RANK_1 << 56;

#[inline]
pub fn bit(sq: u8) -> Bitboard {
    1u64 << sq
}

#[inline]
pub fn lsb(b: Bitboard) -> u8 {
    b.trailing_zeros() as u8
}

#[inline]
pub fn msb(b: Bitboard) -> u8 {
    63 - b.leading_zeros() as u8
}

/// Iterate over the set squares of a bitboard.
pub struct Squares(pub Bitboard);

impl Iterator for Squares {
    type Item = u8;
    #[inline]
    fn next(&mut self) -> Option<u8> {
        if self.0 == 0 {
            None
        } else {
            let s = lsb(self.0);
            self.0 &= self.0 - 1;
            Some(s)
        }
    }
}

#[inline]
pub fn file_of(sq: u8) -> u8 {
    sq & 7
}

#[inline]
pub fn rank_of(sq: u8) -> u8 {
    sq >> 3
}

pub fn file_mask(file: u8) -> Bitboard {
    FILE_A << file
}

// Direction order: N, NE, E, SE, S, SW, W, NW.
const DIRS: [(i8, i8); 8] = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)];
const POSITIVE: [bool; 8] = [true, true, true, false, false, false, false, true];

pub struct Tables {
    pub knight: [Bitboard; 64],
    pub king: [Bitboard; 64],
    /// pawn[color][sq]: squares a pawn of `color` on `sq` attacks.
    pub pawn: [[Bitboard; 64]; 2],
    pub rays: [[Bitboard; 64]; 8],
    /// Squares strictly between two squares on a shared line (0 otherwise).
    pub between: Vec<[Bitboard; 64]>,
}

fn build() -> Tables {
    let mut t = Tables {
        knight: [0; 64],
        king: [0; 64],
        pawn: [[0; 64]; 2],
        rays: [[0; 64]; 8],
        between: vec![[0; 64]; 64],
    };
    let on = |f: i8, r: i8| (0..8).contains(&f) && (0..8).contains(&r);
    for sq in 0..64u8 {
        let f = file_of(sq) as i8;
        let r = rank_of(sq) as i8;
        for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
            if on(f + df, r + dr) {
                t.knight[sq as usize] |= bit(((r + dr) * 8 + f + df) as u8);
            }
        }
        for (df, dr) in DIRS {
            if on(f + df, r + dr) {
                t.king[sq as usize] |= bit(((r + dr) * 8 + f + df) as u8);
            }
        }
        for df in [-1, 1] {
            if on(f + df, r + 1) {
                t.pawn[0][sq as usize] |= bit(((r + 1) * 8 + f + df) as u8);
            }
            if on(f + df, r - 1) {
                t.pawn[1][sq as usize] |= bit(((r - 1) * 8 + f + df) as u8);
            }
        }
        for (d, (df, dr)) in DIRS.iter().enumerate() {
            let (mut cf, mut cr) = (f + df, r + dr);
            let mut acc = 0u64;
            while on(cf, cr) {
                let target = (cr * 8 + cf) as u8;
                t.between[sq as usize][target as usize] = acc;
                acc |= bit(target);
                cf += df;
                cr += dr;
            }
            t.rays[d][sq as usize] = acc;
        }
    }
    t
}

static TABLES: OnceLock<Tables> = OnceLock::new();

#[inline]
pub fn tables() -> &'static Tables {
    TABLES.get_or_init(build)
}

#[inline]
fn ray_attacks(t: &Tables, dir: usize, sq: u8, occ: Bitboard) -> Bitboard {
    let ray = t.rays[dir][sq as usize];
    let blockers = ray & occ;
    if blockers == 0 {
        return ray;
    }
    let b = if POSITIVE[dir] { lsb(blockers) } else { msb(blockers) };
    ray ^ t.rays[dir][b as usize]
}

#[inline]
pub fn rook_attacks(sq: u8, occ: Bitboard) -> Bitboard {
    let t = tables();
    ray_attacks(t, 0, sq, occ) | ray_attacks(t, 2, sq, occ) | ray_attacks(t, 4, sq, occ) | ray_attacks(t, 6, sq, occ)
}

#[inline]
pub fn bishop_attacks(sq: u8, occ: Bitboard) -> Bitboard {
    let t = tables();
    ray_attacks(t, 1, sq, occ) | ray_attacks(t, 3, sq, occ) | ray_attacks(t, 5, sq, occ) | ray_attacks(t, 7, sq, occ)
}

#[inline]
pub fn knight_attacks(sq: u8) -> Bitboard {
    tables().knight[sq as usize]
}

#[inline]
pub fn king_attacks(sq: u8) -> Bitboard {
    tables().king[sq as usize]
}

#[inline]
pub fn pawn_attacks(color: usize, sq: u8) -> Bitboard {
    tables().pawn[color][sq as usize]
}

#[inline]
pub fn between(a: u8, b: u8) -> Bitboard {
    tables().between[a as usize][b as usize]
}

pub fn square_name(sq: u8) -> String {
    let f = (b'a' + file_of(sq)) as char;
    let r = (b'1' + rank_of(sq)) as char;
    format!("{f}{r}")
}

pub fn parse_square(s: &str) -> Option<u8> {
    let b = s.as_bytes();
    if b.len() != 2 {
        return None;
    }
    let f = b[0].wrapping_sub(b'a');
    let r = b[1].wrapping_sub(b'1');
    if f < 8 && r < 8 {
        Some(r * 8 + f)
    } else {
        None
    }
}
