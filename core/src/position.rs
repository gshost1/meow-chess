//! Board state, move generation and move making.

use crate::bitboard::*;
use std::fmt;
use std::sync::OnceLock;

pub const WHITE: usize = 0;
pub const BLACK: usize = 1;

pub const PAWN: u8 = 0;
pub const KNIGHT: u8 = 1;
pub const BISHOP: u8 = 2;
pub const ROOK: u8 = 3;
pub const QUEEN: u8 = 4;
pub const KING: u8 = 5;

/// Mailbox value for an empty square. Pieces are `color * 6 + kind`.
pub const EMPTY: u8 = 12;

pub const WK: u8 = 1;
pub const WQ: u8 = 2;
pub const BK: u8 = 4;
pub const BQ: u8 = 8;

pub const START_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

#[inline]
pub fn piece_color(p: u8) -> usize {
    (p / 6) as usize
}
#[inline]
pub fn piece_kind(p: u8) -> u8 {
    p % 6
}
#[inline]
pub fn make_piece(color: usize, kind: u8) -> u8 {
    color as u8 * 6 + kind
}

pub fn kind_name(kind: u8) -> &'static str {
    match kind {
        PAWN => "pawn",
        KNIGHT => "knight",
        BISHOP => "bishop",
        ROOK => "rook",
        QUEEN => "queen",
        _ => "king",
    }
}

pub fn kind_letter(kind: u8) -> char {
    ['P', 'N', 'B', 'R', 'Q', 'K'][kind as usize]
}

pub const FLAG_CAPTURE: u8 = 1;
pub const FLAG_EP: u8 = 2;
pub const FLAG_CASTLE: u8 = 4;
pub const FLAG_DOUBLE: u8 = 8;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Hash)]
pub struct Move {
    pub from: u8,
    pub to: u8,
    /// Promotion piece kind, or 0 when not a promotion (PAWN can never be a promotion target).
    pub promo: u8,
    pub flags: u8,
}

impl Move {
    pub const NULL: Move = Move { from: 0, to: 0, promo: 0, flags: 0 };

    #[inline]
    pub fn is_null(self) -> bool {
        self.from == 0 && self.to == 0
    }
    #[inline]
    pub fn is_capture(self) -> bool {
        self.flags & FLAG_CAPTURE != 0
    }
    #[inline]
    pub fn is_promo(self) -> bool {
        self.promo != 0
    }
    #[inline]
    pub fn pack(self) -> u32 {
        self.from as u32 | (self.to as u32) << 6 | (self.promo as u32) << 12 | (self.flags as u32) << 16
    }
    #[inline]
    pub fn unpack(v: u32) -> Move {
        Move {
            from: (v & 63) as u8,
            to: ((v >> 6) & 63) as u8,
            promo: ((v >> 12) & 7) as u8,
            flags: ((v >> 16) & 0xFF) as u8,
        }
    }
    pub fn uci(self) -> String {
        let mut s = format!("{}{}", square_name(self.from), square_name(self.to));
        if self.is_promo() {
            s.push(kind_letter(self.promo).to_ascii_lowercase());
        }
        s
    }
}

impl fmt::Display for Move {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.uci())
    }
}

pub struct MoveList {
    moves: [Move; 256],
    len: usize,
}

impl MoveList {
    pub fn new() -> Self {
        MoveList { moves: [Move::NULL; 256], len: 0 }
    }
    #[inline]
    pub fn push(&mut self, m: Move) {
        self.moves[self.len] = m;
        self.len += 1;
    }
    #[inline]
    pub fn len(&self) -> usize {
        self.len
    }
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    #[inline]
    pub fn as_slice(&self) -> &[Move] {
        &self.moves[..self.len]
    }
    #[inline]
    pub fn as_mut_slice(&mut self) -> &mut [Move] {
        &mut self.moves[..self.len]
    }
}

impl Default for MoveList {
    fn default() -> Self {
        Self::new()
    }
}

struct Zobrist {
    pieces: [[u64; 64]; 12],
    side: u64,
    castle: [u64; 16],
    ep: [u64; 8],
}

fn zobrist() -> &'static Zobrist {
    static Z: OnceLock<Zobrist> = OnceLock::new();
    Z.get_or_init(|| {
        let mut state: u64 = 0x9E37_79B9_7F4A_7C15;
        let mut next = || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let mut z = Zobrist { pieces: [[0; 64]; 12], side: 0, castle: [0; 16], ep: [0; 8] };
        for p in z.pieces.iter_mut() {
            for s in p.iter_mut() {
                *s = next();
            }
        }
        z.side = next();
        for c in z.castle.iter_mut() {
            *c = next();
        }
        for e in z.ep.iter_mut() {
            *e = next();
        }
        z
    })
}

/// Which castling rights survive a move touching a square.
fn castle_mask(sq: u8) -> u8 {
    match sq {
        0 => !WQ,
        4 => !(WK | WQ),
        7 => !WK,
        56 => !BQ,
        60 => !(BK | BQ),
        63 => !BK,
        _ => 0xF,
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Position {
    pub bb: [Bitboard; 12],
    pub occ: [Bitboard; 2],
    pub board: [u8; 64],
    pub side: usize,
    pub castling: u8,
    pub ep: Option<u8>,
    pub halfmove: u16,
    pub fullmove: u16,
    pub hash: u64,
}

#[derive(Debug)]
pub struct FenError(pub String);

impl fmt::Display for FenError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "bad FEN: {}", self.0)
    }
}

impl Position {
    pub fn startpos() -> Position {
        Position::from_fen(START_FEN).expect("valid start FEN")
    }

    fn empty() -> Position {
        Position {
            bb: [0; 12],
            occ: [0; 2],
            board: [EMPTY; 64],
            side: WHITE,
            castling: 0,
            ep: None,
            halfmove: 0,
            fullmove: 1,
            hash: 0,
        }
    }

    pub fn from_fen(fen: &str) -> Result<Position, FenError> {
        let mut p = Position::empty();
        let parts: Vec<&str> = fen.split_whitespace().collect();
        if parts.len() < 4 {
            return Err(FenError(fen.to_string()));
        }
        let mut rank: i32 = 7;
        let mut file: i32 = 0;
        for c in parts[0].chars() {
            match c {
                '/' => {
                    rank -= 1;
                    file = 0;
                }
                '1'..='8' => file += c as i32 - '0' as i32,
                _ => {
                    let color = if c.is_ascii_uppercase() { WHITE } else { BLACK };
                    let kind = match c.to_ascii_lowercase() {
                        'p' => PAWN,
                        'n' => KNIGHT,
                        'b' => BISHOP,
                        'r' => ROOK,
                        'q' => QUEEN,
                        'k' => KING,
                        _ => return Err(FenError(fen.to_string())),
                    };
                    if !(0..8).contains(&rank) || !(0..8).contains(&file) {
                        return Err(FenError(fen.to_string()));
                    }
                    p.put(make_piece(color, kind), (rank * 8 + file) as u8);
                    file += 1;
                }
            }
        }
        p.side = match parts[1] {
            "w" => WHITE,
            "b" => BLACK,
            _ => return Err(FenError(fen.to_string())),
        };
        for c in parts[2].chars() {
            p.castling |= match c {
                'K' => WK,
                'Q' => WQ,
                'k' => BK,
                'q' => BQ,
                _ => 0,
            };
        }
        p.ep = if parts[3] == "-" { None } else { parse_square(parts[3]) };
        p.halfmove = parts.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
        p.fullmove = parts.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);
        if (p.bb[make_piece(WHITE, KING) as usize]).count_ones() != 1
            || (p.bb[make_piece(BLACK, KING) as usize]).count_ones() != 1
        {
            return Err(FenError("each side needs exactly one king".into()));
        }
        p.hash = p.compute_hash();
        Ok(p)
    }

    pub fn to_fen(&self) -> String {
        let mut s = String::new();
        for rank in (0..8).rev() {
            let mut empty = 0;
            for file in 0..8 {
                let pc = self.board[rank * 8 + file];
                if pc == EMPTY {
                    empty += 1;
                } else {
                    if empty > 0 {
                        s.push_str(&empty.to_string());
                        empty = 0;
                    }
                    let l = kind_letter(piece_kind(pc));
                    s.push(if piece_color(pc) == WHITE { l } else { l.to_ascii_lowercase() });
                }
            }
            if empty > 0 {
                s.push_str(&empty.to_string());
            }
            if rank > 0 {
                s.push('/');
            }
        }
        s.push_str(if self.side == WHITE { " w " } else { " b " });
        let mut c = String::new();
        if self.castling & WK != 0 {
            c.push('K');
        }
        if self.castling & WQ != 0 {
            c.push('Q');
        }
        if self.castling & BK != 0 {
            c.push('k');
        }
        if self.castling & BQ != 0 {
            c.push('q');
        }
        if c.is_empty() {
            c.push('-');
        }
        s.push_str(&c);
        s.push(' ');
        s.push_str(&self.ep.map(square_name).unwrap_or_else(|| "-".into()));
        s.push_str(&format!(" {} {}", self.halfmove, self.fullmove));
        s
    }

    fn compute_hash(&self) -> u64 {
        let z = zobrist();
        let mut h = 0;
        for sq in 0..64 {
            let pc = self.board[sq];
            if pc != EMPTY {
                h ^= z.pieces[pc as usize][sq];
            }
        }
        if self.side == BLACK {
            h ^= z.side;
        }
        h ^= z.castle[self.castling as usize];
        if let Some(e) = self.ep {
            h ^= z.ep[file_of(e) as usize];
        }
        h
    }

    #[inline]
    fn put(&mut self, pc: u8, sq: u8) {
        self.bb[pc as usize] |= bit(sq);
        self.occ[piece_color(pc)] |= bit(sq);
        self.board[sq as usize] = pc;
        self.hash ^= zobrist().pieces[pc as usize][sq as usize];
    }

    #[inline]
    fn remove(&mut self, sq: u8) {
        let pc = self.board[sq as usize];
        self.bb[pc as usize] &= !bit(sq);
        self.occ[piece_color(pc)] &= !bit(sq);
        self.board[sq as usize] = EMPTY;
        self.hash ^= zobrist().pieces[pc as usize][sq as usize];
    }

    #[inline]
    pub fn all(&self) -> Bitboard {
        self.occ[0] | self.occ[1]
    }

    #[inline]
    pub fn pieces(&self, color: usize, kind: u8) -> Bitboard {
        self.bb[make_piece(color, kind) as usize]
    }

    #[inline]
    pub fn king_sq(&self, color: usize) -> u8 {
        lsb(self.pieces(color, KING))
    }

    /// All pieces of `by` that attack `sq`, given occupancy `occ`.
    pub fn attackers_to(&self, sq: u8, by: usize, occ: Bitboard) -> Bitboard {
        let diag = self.pieces(by, BISHOP) | self.pieces(by, QUEEN);
        let orth = self.pieces(by, ROOK) | self.pieces(by, QUEEN);
        (pawn_attacks(by ^ 1, sq) & self.pieces(by, PAWN))
            | (knight_attacks(sq) & self.pieces(by, KNIGHT))
            | (king_attacks(sq) & self.pieces(by, KING))
            | (bishop_attacks(sq, occ) & diag)
            | (rook_attacks(sq, occ) & orth)
    }

    #[inline]
    pub fn is_attacked(&self, sq: u8, by: usize) -> bool {
        self.attackers_to(sq, by, self.all()) != 0
    }

    #[inline]
    pub fn in_check(&self) -> bool {
        self.is_attacked(self.king_sq(self.side), self.side ^ 1)
    }

    /// Squares attacked by the piece standing on `sq`.
    pub fn attacks_from(&self, sq: u8) -> Bitboard {
        let pc = self.board[sq as usize];
        if pc == EMPTY {
            return 0;
        }
        let occ = self.all();
        match piece_kind(pc) {
            PAWN => pawn_attacks(piece_color(pc), sq),
            KNIGHT => knight_attacks(sq),
            BISHOP => bishop_attacks(sq, occ),
            ROOK => rook_attacks(sq, occ),
            QUEEN => bishop_attacks(sq, occ) | rook_attacks(sq, occ),
            _ => king_attacks(sq),
        }
    }

    pub fn has_non_pawn_material(&self, color: usize) -> bool {
        (self.pieces(color, KNIGHT) | self.pieces(color, BISHOP) | self.pieces(color, ROOK) | self.pieces(color, QUEEN))
            != 0
    }

    /// Generate pseudo-legal moves. When `captures_only` is set, only captures and queen promotions.
    pub fn gen_pseudo(&self, list: &mut MoveList, captures_only: bool) {
        let us = self.side;
        let them = us ^ 1;
        let own = self.occ[us];
        let enemy = self.occ[them];
        let occ = own | enemy;
        let targets = if captures_only { enemy } else { !own };

        // Pawns
        let pawns = self.pieces(us, PAWN);
        let (fwd, start_rank, promo_rank): (i8, Bitboard, Bitboard) =
            if us == WHITE { (8, RANK_2, RANK_8) } else { (-8, RANK_7, RANK_1) };
        for from in Squares(pawns) {
            let one = (from as i8 + fwd) as u8;
            if occ & bit(one) == 0 {
                if bit(one) & promo_rank != 0 {
                    for promo in [QUEEN, KNIGHT, ROOK, BISHOP] {
                        if !captures_only || promo == QUEEN {
                            list.push(Move { from, to: one, promo, flags: 0 });
                        }
                    }
                } else if !captures_only {
                    list.push(Move { from, to: one, promo: 0, flags: 0 });
                    if bit(from) & start_rank != 0 {
                        let two = (one as i8 + fwd) as u8;
                        if occ & bit(two) == 0 {
                            list.push(Move { from, to: two, promo: 0, flags: FLAG_DOUBLE });
                        }
                    }
                }
            }
            let atk = pawn_attacks(us, from);
            for to in Squares(atk & enemy) {
                if bit(to) & promo_rank != 0 {
                    for promo in [QUEEN, KNIGHT, ROOK, BISHOP] {
                        if !captures_only || promo == QUEEN {
                            list.push(Move { from, to, promo, flags: FLAG_CAPTURE });
                        }
                    }
                } else {
                    list.push(Move { from, to, promo: 0, flags: FLAG_CAPTURE });
                }
            }
            if let Some(ep) = self.ep {
                if atk & bit(ep) != 0 {
                    list.push(Move { from, to: ep, promo: 0, flags: FLAG_CAPTURE | FLAG_EP });
                }
            }
        }

        let mut add = |from: u8, attacks: Bitboard| {
            for to in Squares(attacks & targets) {
                let flags = if enemy & bit(to) != 0 { FLAG_CAPTURE } else { 0 };
                list.push(Move { from, to, promo: 0, flags });
            }
        };
        for from in Squares(self.pieces(us, KNIGHT)) {
            add(from, knight_attacks(from));
        }
        for from in Squares(self.pieces(us, BISHOP)) {
            add(from, bishop_attacks(from, occ));
        }
        for from in Squares(self.pieces(us, ROOK)) {
            add(from, rook_attacks(from, occ));
        }
        for from in Squares(self.pieces(us, QUEEN)) {
            add(from, bishop_attacks(from, occ) | rook_attacks(from, occ));
        }
        let ksq = self.king_sq(us);
        add(ksq, king_attacks(ksq));

        if !captures_only {
            let (kside, qside, base) = if us == WHITE { (WK, WQ, 0u8) } else { (BK, BQ, 56u8) };
            if self.castling & (kside | qside) != 0 && ksq == base + 4 && !self.is_attacked(ksq, them) {
                if self.castling & kside != 0
                    && occ & (bit(base + 5) | bit(base + 6)) == 0
                    && self.board[(base + 7) as usize] == make_piece(us, ROOK)
                    && !self.is_attacked(base + 5, them)
                {
                    list.push(Move { from: ksq, to: base + 6, promo: 0, flags: FLAG_CASTLE });
                }
                if self.castling & qside != 0
                    && occ & (bit(base + 1) | bit(base + 2) | bit(base + 3)) == 0
                    && self.board[base as usize] == make_piece(us, ROOK)
                    && !self.is_attacked(base + 3, them)
                {
                    list.push(Move { from: ksq, to: base + 2, promo: 0, flags: FLAG_CASTLE });
                }
            }
        }
    }

    /// Play a pseudo-legal move and return the new position (does not check legality).
    pub fn make(&self, m: Move) -> Position {
        let z = zobrist();
        let mut p = *self;
        let us = self.side;
        let them = us ^ 1;
        let moving = self.board[m.from as usize];

        if let Some(e) = p.ep {
            p.hash ^= z.ep[file_of(e) as usize];
            p.ep = None;
        }

        p.halfmove += 1;
        if m.flags & FLAG_EP != 0 {
            let cap_sq = if us == WHITE { m.to - 8 } else { m.to + 8 };
            p.remove(cap_sq);
            p.halfmove = 0;
        } else if p.board[m.to as usize] != EMPTY {
            p.remove(m.to);
            p.halfmove = 0;
        }
        if piece_kind(moving) == PAWN {
            p.halfmove = 0;
        }

        p.remove(m.from);
        let placed = if m.is_promo() { make_piece(us, m.promo) } else { moving };
        p.put(placed, m.to);

        if m.flags & FLAG_CASTLE != 0 {
            let (rf, rt) = match m.to {
                6 => (7, 5),
                2 => (0, 3),
                62 => (63, 61),
                _ => (56, 59),
            };
            p.remove(rf);
            p.put(make_piece(us, ROOK), rt);
        }

        if m.flags & FLAG_DOUBLE != 0 {
            let ep_sq = (m.from + m.to) / 2;
            // Only record en passant when it can actually be taken; keeps repetition hashing honest.
            if pawn_attacks(us, ep_sq) & p.pieces(them, PAWN) != 0 {
                p.ep = Some(ep_sq);
                p.hash ^= z.ep[file_of(ep_sq) as usize];
            }
        }

        let new_castle = p.castling & castle_mask(m.from) & castle_mask(m.to);
        if new_castle != p.castling {
            p.hash ^= z.castle[p.castling as usize] ^ z.castle[new_castle as usize];
            p.castling = new_castle;
        }

        p.side = them;
        p.hash ^= z.side;
        if us == BLACK {
            p.fullmove += 1;
        }
        p
    }

    /// Pass the turn (used by null-move pruning).
    pub fn make_null(&self) -> Position {
        let z = zobrist();
        let mut p = *self;
        if let Some(e) = p.ep {
            p.hash ^= z.ep[file_of(e) as usize];
            p.ep = None;
        }
        p.side ^= 1;
        p.hash ^= z.side;
        p.halfmove += 1;
        p
    }

    /// Returns the position after `m` if `m` is legal.
    #[inline]
    pub fn try_make(&self, m: Move) -> Option<Position> {
        let p = self.make(m);
        if p.is_attacked(p.king_sq(self.side), p.side) {
            None
        } else {
            Some(p)
        }
    }

    pub fn legal_moves(&self) -> Vec<Move> {
        let mut list = MoveList::new();
        self.gen_pseudo(&mut list, false);
        list.as_slice().iter().copied().filter(|&m| self.try_make(m).is_some()).collect()
    }

    pub fn is_checkmate(&self) -> bool {
        self.in_check() && self.legal_moves().is_empty()
    }

    pub fn is_stalemate(&self) -> bool {
        !self.in_check() && self.legal_moves().is_empty()
    }

    pub fn insufficient_material(&self) -> bool {
        let majors = self.pieces(0, PAWN)
            | self.pieces(1, PAWN)
            | self.pieces(0, ROOK)
            | self.pieces(1, ROOK)
            | self.pieces(0, QUEEN)
            | self.pieces(1, QUEEN);
        if majors != 0 {
            return false;
        }
        let minors = self.pieces(0, KNIGHT) | self.pieces(1, KNIGHT) | self.pieces(0, BISHOP) | self.pieces(1, BISHOP);
        minors.count_ones() <= 1
    }

    pub fn perft(&self, depth: u32) -> u64 {
        if depth == 0 {
            return 1;
        }
        let mut list = MoveList::new();
        self.gen_pseudo(&mut list, false);
        let mut n = 0;
        for &m in list.as_slice() {
            if let Some(p) = self.try_make(m) {
                n += if depth == 1 { 1 } else { p.perft(depth - 1) };
            }
        }
        n
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn perft_start() {
        let p = Position::startpos();
        assert_eq!(p.perft(1), 20);
        assert_eq!(p.perft(2), 400);
        assert_eq!(p.perft(3), 8902);
        assert_eq!(p.perft(4), 197_281);
    }

    #[test]
    fn perft_kiwipete() {
        let p = Position::from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1").unwrap();
        assert_eq!(p.perft(1), 48);
        assert_eq!(p.perft(2), 2039);
        assert_eq!(p.perft(3), 97_862);
    }

    #[test]
    fn perft_pos3() {
        let p = Position::from_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1").unwrap();
        assert_eq!(p.perft(4), 43_238);
        assert_eq!(p.perft(5), 674_624);
    }

    #[test]
    fn perft_pos4() {
        let p = Position::from_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1").unwrap();
        assert_eq!(p.perft(3), 9467);
    }

    #[test]
    fn perft_pos5() {
        let p = Position::from_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8").unwrap();
        assert_eq!(p.perft(3), 62_379);
    }

    #[test]
    fn fen_roundtrip() {
        let f = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        assert_eq!(Position::from_fen(f).unwrap().to_fen(), f);
    }

    #[test]
    fn hash_is_incremental() {
        let p = Position::from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1").unwrap();
        for m in p.legal_moves() {
            let q = p.make(m);
            assert_eq!(q.hash, q.compute_hash(), "move {m}");
        }
    }
}
