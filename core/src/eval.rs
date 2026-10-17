//! Static evaluation: tapered material + piece-square tables + a few positional terms.
//! Scores are in centipawns from the side to move's point of view.

use crate::bitboard::*;
use crate::position::*;

const MG_VALUE: [i32; 6] = [100, 320, 330, 500, 900, 0];
const EG_VALUE: [i32; 6] = [120, 300, 315, 530, 950, 0];
const PHASE_WEIGHT: [i32; 6] = [0, 1, 1, 2, 4, 0];

/// Simple piece values used for describing material to a human (pawn = 1).
pub const HUMAN_VALUE: [i32; 6] = [1, 3, 3, 5, 9, 0];

/// Piece values used when asking "can this attacker win that target?".
/// The king is priceless: a king never wins a defended piece and is never a bargain attacker.
pub const ATTACKER_VALUE: [i32; 6] = [1, 3, 3, 5, 9, 10_000];

// Tables are written from White's point of view with rank 8 on top,
// so a White piece on `sq` reads index `sq ^ 56`.
#[rustfmt::skip]
const PST_PAWN: [i32; 64] = [
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0,
];
#[rustfmt::skip]
const PST_KNIGHT: [i32; 64] = [
   -50,-40,-30,-30,-30,-30,-40,-50,
   -40,-20,  0,  0,  0,  0,-20,-40,
   -30,  0, 10, 15, 15, 10,  0,-30,
   -30,  5, 15, 20, 20, 15,  5,-30,
   -30,  0, 15, 20, 20, 15,  0,-30,
   -30,  5, 10, 15, 15, 10,  5,-30,
   -40,-20,  0,  5,  5,  0,-20,-40,
   -50,-40,-30,-30,-30,-30,-40,-50,
];
#[rustfmt::skip]
const PST_BISHOP: [i32; 64] = [
   -20,-10,-10,-10,-10,-10,-10,-20,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -10,  0,  5, 10, 10,  5,  0,-10,
   -10,  5,  5, 10, 10,  5,  5,-10,
   -10,  0, 10, 10, 10, 10,  0,-10,
   -10, 10, 10, 10, 10, 10, 10,-10,
   -10,  5,  0,  0,  0,  0,  5,-10,
   -20,-10,-10,-10,-10,-10,-10,-20,
];
#[rustfmt::skip]
const PST_ROOK: [i32; 64] = [
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0,
];
#[rustfmt::skip]
const PST_QUEEN: [i32; 64] = [
   -20,-10,-10, -5, -5,-10,-10,-20,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -10,  0,  5,  5,  5,  5,  0,-10,
    -5,  0,  5,  5,  5,  5,  0, -5,
     0,  0,  5,  5,  5,  5,  0, -5,
   -10,  5,  5,  5,  5,  5,  0,-10,
   -10,  0,  5,  0,  0,  0,  0,-10,
   -20,-10,-10, -5, -5,-10,-10,-20,
];
#[rustfmt::skip]
const PST_KING_MG: [i32; 64] = [
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -20,-30,-30,-40,-40,-30,-30,-20,
   -10,-20,-20,-20,-20,-20,-20,-10,
    20, 20,  0,  0,  0,  0, 20, 20,
    20, 30, 10,  0,  0, 10, 30, 20,
];
#[rustfmt::skip]
const PST_KING_EG: [i32; 64] = [
   -50,-40,-30,-20,-20,-30,-40,-50,
   -30,-20,-10,  0,  0,-10,-20,-30,
   -30,-10, 20, 30, 30, 20,-10,-30,
   -30,-10, 30, 40, 40, 30,-10,-30,
   -30,-10, 30, 40, 40, 30,-10,-30,
   -30,-10, 20, 30, 30, 20,-10,-30,
   -30,-30,  0,  0,  0,  0,-30,-30,
   -50,-30,-30,-30,-30,-30,-30,-50,
];

const PASSED_MG: [i32; 8] = [0, 5, 10, 15, 25, 40, 60, 0];
const PASSED_EG: [i32; 8] = [0, 10, 20, 35, 60, 90, 130, 0];

fn pst(kind: u8, idx: usize) -> (i32, i32) {
    match kind {
        PAWN => (PST_PAWN[idx], PST_PAWN[idx]),
        KNIGHT => (PST_KNIGHT[idx], PST_KNIGHT[idx]),
        BISHOP => (PST_BISHOP[idx], PST_BISHOP[idx]),
        ROOK => (PST_ROOK[idx], PST_ROOK[idx]),
        QUEEN => (PST_QUEEN[idx], PST_QUEEN[idx]),
        _ => (PST_KING_MG[idx], PST_KING_EG[idx]),
    }
}

fn adjacent_files(file: u8) -> Bitboard {
    let mut m = 0;
    if file > 0 {
        m |= file_mask(file - 1);
    }
    if file < 7 {
        m |= file_mask(file + 1);
    }
    m
}

/// Ranks strictly ahead of `sq` from `color`'s point of view.
fn ahead(color: usize, sq: u8) -> Bitboard {
    let r = rank_of(sq) as u32;
    if color == WHITE {
        if r >= 7 {
            0
        } else {
            !0u64 << ((r + 1) * 8)
        }
    } else if r == 0 {
        0
    } else {
        (1u64 << (r * 8)) - 1
    }
}

pub fn evaluate(pos: &Position) -> i32 {
    let mut mg = [0i32; 2];
    let mut eg = [0i32; 2];
    let mut phase = 0;
    let occ = pos.all();

    for color in [WHITE, BLACK] {
        let them = color ^ 1;
        let own_pawns = pos.pieces(color, PAWN);
        let their_pawns = pos.pieces(them, PAWN);
        let their_pawn_attacks = {
            let mut a = 0;
            for s in Squares(their_pawns) {
                a |= pawn_attacks(them, s);
            }
            a
        };
        let safe = !pos.occ[color] & !their_pawn_attacks;

        for kind in PAWN..=KING {
            for sq in Squares(pos.pieces(color, kind)) {
                let idx = if color == WHITE { (sq ^ 56) as usize } else { sq as usize };
                let (pm, pe) = pst(kind, idx);
                mg[color] += MG_VALUE[kind as usize] + pm;
                eg[color] += EG_VALUE[kind as usize] + pe;
                phase += PHASE_WEIGHT[kind as usize];

                match kind {
                    PAWN => {
                        let f = file_of(sq);
                        let rel_rank = if color == WHITE { rank_of(sq) } else { 7 - rank_of(sq) } as usize;
                        let front = ahead(color, sq);
                        if their_pawns & front & (file_mask(f) | adjacent_files(f)) == 0 {
                            mg[color] += PASSED_MG[rel_rank];
                            eg[color] += PASSED_EG[rel_rank];
                        }
                        if own_pawns & adjacent_files(f) == 0 {
                            mg[color] -= 12;
                            eg[color] -= 15;
                        }
                        if own_pawns & front & file_mask(f) != 0 {
                            mg[color] -= 10;
                            eg[color] -= 20;
                        }
                    }
                    KNIGHT => {
                        let n = (knight_attacks(sq) & safe).count_ones() as i32;
                        mg[color] += 4 * (n - 4);
                        eg[color] += 4 * (n - 4);
                    }
                    BISHOP => {
                        let n = (bishop_attacks(sq, occ) & safe).count_ones() as i32;
                        mg[color] += 4 * (n - 6);
                        eg[color] += 5 * (n - 6);
                    }
                    ROOK => {
                        let n = (rook_attacks(sq, occ) & safe).count_ones() as i32;
                        mg[color] += 2 * (n - 7);
                        eg[color] += 4 * (n - 7);
                        let fm = file_mask(file_of(sq));
                        if (own_pawns | their_pawns) & fm == 0 {
                            mg[color] += 20;
                            eg[color] += 10;
                        } else if own_pawns & fm == 0 {
                            mg[color] += 10;
                            eg[color] += 5;
                        }
                    }
                    QUEEN => {
                        let n = ((bishop_attacks(sq, occ) | rook_attacks(sq, occ)) & safe).count_ones() as i32;
                        mg[color] += n - 14;
                        eg[color] += 2 * (n - 14);
                    }
                    _ => {
                        // Pawn shield in front of the king matters in the middlegame.
                        let shield = king_attacks(sq) & ahead(color, sq) & own_pawns;
                        mg[color] += 12 * shield.count_ones() as i32;
                    }
                }
            }
        }
        if pos.pieces(color, BISHOP).count_ones() >= 2 {
            mg[color] += 30;
            eg[color] += 50;
        }
    }

    let phase = phase.min(24);
    let mg_score = mg[WHITE] - mg[BLACK];
    let eg_score = eg[WHITE] - eg[BLACK];
    let mut score = (mg_score * phase + eg_score * (24 - phase)) / 24;

    // Drawish: no pawns and a minor-piece-or-less advantage.
    for color in [WHITE, BLACK] {
        if pos.pieces(color, PAWN) == 0 && score.signum() == if color == WHITE { 1 } else { -1 } {
            let mat = material_points(pos, color) - material_points(pos, color ^ 1);
            if mat <= 3 {
                score /= 4;
            }
        }
    }

    let rel = if pos.side == WHITE { score } else { -score };
    rel + 10
}

/// Material in human points (pawn = 1, knight/bishop = 3, rook = 5, queen = 9).
pub fn material_points(pos: &Position, color: usize) -> i32 {
    (PAWN..KING).map(|k| pos.pieces(color, k).count_ones() as i32 * HUMAN_VALUE[k as usize]).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symmetric() {
        let a = Position::from_fen("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3").unwrap();
        let b = Position::from_fen("rnbqkb1r/pppp1ppp/5n2/4p3/4P3/2N5/PPPP1PPP/R1BQKBNR b KQkq - 2 3").unwrap();
        assert_eq!(evaluate(&a), evaluate(&b));
    }
}
