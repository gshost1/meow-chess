//! Alpha-beta search: iterative deepening, PVS, transposition table, quiescence,
//! null-move pruning, late-move reductions, killer and history move ordering.

use crate::eval::evaluate;
use crate::position::*;
use std::time::{Duration, Instant};

pub const MATE: i32 = 30_000;
pub const INF: i32 = 32_000;
const MATE_BOUND: i32 = MATE - 1_000;
const MAX_PLY: usize = 128;

const ORDER_VALUE: [i32; 6] = [100, 320, 330, 500, 900, 2000];

pub fn is_mate_score(s: i32) -> bool {
    s.abs() >= MATE_BOUND
}

/// Moves until mate (positive: side to move mates; negative: gets mated).
pub fn mate_in(s: i32) -> Option<i32> {
    if !is_mate_score(s) {
        None
    } else if s > 0 {
        Some((MATE - s + 1) / 2)
    } else {
        Some(-((MATE + s) / 2))
    }
}

#[derive(Clone, Copy, Default)]
struct TTEntry {
    key: u64,
    mv: u32,
    score: i32,
    depth: i8,
    flag: u8,
}

const TT_EXACT: u8 = 1;
const TT_LOWER: u8 = 2;
const TT_UPPER: u8 = 3;

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub max_depth: u32,
    pub time_ms: Option<u64>,
    pub nodes: Option<u64>,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { max_depth: 64, time_ms: None, nodes: None }
    }
}

#[derive(Clone, Debug)]
pub struct SearchResult {
    pub best: Move,
    /// Score from the side to move's point of view, centipawns or mate score.
    pub score: i32,
    pub depth: u32,
    pub pv: Vec<Move>,
    pub nodes: u64,
}

pub struct Searcher {
    tt: Vec<TTEntry>,
    tt_mask: usize,
    killers: [[Move; 2]; MAX_PLY],
    history: Box<[[i32; 64]; 12]>,
    pv: Vec<[Move; MAX_PLY]>,
    pv_len: [usize; MAX_PLY],
    path: Vec<u64>,
    nodes: u64,
    stop: bool,
    deadline: Option<Instant>,
    node_limit: Option<u64>,
}

impl Searcher {
    /// `tt_mb`: transposition table size in megabytes.
    pub fn new(tt_mb: usize) -> Searcher {
        let entries = (tt_mb * 1024 * 1024 / std::mem::size_of::<TTEntry>()).next_power_of_two() / 2;
        let entries = entries.max(1024);
        Searcher {
            tt: vec![TTEntry::default(); entries],
            tt_mask: entries - 1,
            killers: [[Move::NULL; 2]; MAX_PLY],
            history: Box::new([[0; 64]; 12]),
            pv: vec![[Move::NULL; MAX_PLY]; MAX_PLY],
            pv_len: [0; MAX_PLY],
            path: Vec::with_capacity(512),
            nodes: 0,
            stop: false,
            deadline: None,
            node_limit: None,
        }
    }

    pub fn clear(&mut self) {
        self.tt.iter_mut().for_each(|e| *e = TTEntry::default());
        *self.history = [[0; 64]; 12];
        self.killers = [[Move::NULL; 2]; MAX_PLY];
    }

    /// Search `pos`. `prior` holds hashes of earlier positions in the game (for repetition detection).
    pub fn search(&mut self, pos: &Position, prior: &[u64], limits: Limits) -> SearchResult {
        self.nodes = 0;
        self.stop = false;
        self.deadline = limits.time_ms.map(|ms| Instant::now() + Duration::from_millis(ms));
        self.node_limit = limits.nodes;
        self.path.clear();
        self.path.extend_from_slice(prior);
        for h in self.history.iter_mut().flat_map(|r| r.iter_mut()) {
            *h /= 8;
        }

        let legal = pos.legal_moves();
        let mut result = SearchResult {
            best: legal.first().copied().unwrap_or(Move::NULL),
            score: if legal.is_empty() { if pos.in_check() { -MATE } else { 0 } } else { evaluate(pos) },
            depth: 0,
            pv: legal.first().copied().into_iter().collect(),
            nodes: 0,
        };
        if legal.is_empty() {
            return result;
        }

        for depth in 1..=limits.max_depth.min(MAX_PLY as u32 - 8) {
            let score = self.aspiration(pos, depth as i32, result.score, depth);
            if self.stop && depth > 1 {
                break;
            }
            let len = self.pv_len[0];
            let pv: Vec<Move> = self.pv[0][..len].to_vec();
            if let Some(&first) = pv.first() {
                result.best = first;
                result.pv = pv;
            }
            result.score = score;
            result.depth = depth;
            if self.stop {
                break;
            }
            if let Some(m) = mate_in(score) {
                if (m.unsigned_abs() as u32) * 2 < depth {
                    break;
                }
            }
        }
        result.nodes = self.nodes;
        result
    }

    fn aspiration(&mut self, pos: &Position, depth: i32, prev: i32, iter: u32) -> i32 {
        if iter < 5 || is_mate_score(prev) {
            return self.negamax(pos, depth, -INF, INF, 0, true);
        }
        let mut delta = 30;
        let mut alpha = (prev - delta).max(-INF);
        let mut beta = (prev + delta).min(INF);
        loop {
            let s = self.negamax(pos, depth, alpha, beta, 0, true);
            if self.stop {
                return s;
            }
            if s <= alpha {
                alpha = (alpha - delta).max(-INF);
            } else if s >= beta {
                beta = (beta + delta).min(INF);
            } else {
                return s;
            }
            delta *= 2;
            if delta > 600 {
                alpha = -INF;
                beta = INF;
            }
        }
    }

    #[inline]
    fn check_time(&mut self) {
        if self.nodes & 2047 == 0 {
            if let Some(d) = self.deadline {
                if Instant::now() >= d {
                    self.stop = true;
                }
            }
            if let Some(n) = self.node_limit {
                if self.nodes >= n {
                    self.stop = true;
                }
            }
        }
    }

    fn is_repetition(&self, pos: &Position) -> bool {
        let n = self.path.len();
        let limit = (pos.halfmove as usize).min(n);
        let mut i = 2;
        while i <= limit {
            if self.path[n - i] == pos.hash {
                return true;
            }
            i += 2;
        }
        false
    }

    fn score_moves(&self, pos: &Position, moves: &[Move], tt_move: Move, ply: usize, out: &mut [i32]) {
        for (i, &m) in moves.iter().enumerate() {
            out[i] = if m == tt_move {
                10_000_000
            } else if m.is_capture() || m.is_promo() {
                let victim = if m.flags & FLAG_EP != 0 { PAWN } else { piece_kind(pos.board[m.to as usize]) };
                let victim_v = if m.is_capture() { ORDER_VALUE[victim as usize] } else { 0 };
                let attacker = piece_kind(pos.board[m.from as usize]);
                let promo_v = if m.is_promo() { ORDER_VALUE[m.promo as usize] } else { 0 };
                1_000_000 + victim_v * 10 + promo_v - ORDER_VALUE[attacker as usize] / 10
            } else if ply < MAX_PLY && self.killers[ply][0] == m {
                900_000
            } else if ply < MAX_PLY && self.killers[ply][1] == m {
                800_000
            } else {
                self.history[pos.board[m.from as usize] as usize][m.to as usize]
            };
        }
    }

    fn negamax(&mut self, pos: &Position, mut depth: i32, mut alpha: i32, mut beta: i32, ply: usize, allow_null: bool) -> i32 {
        self.pv_len[ply] = ply;
        if ply > 0 {
            if pos.halfmove >= 100 || self.is_repetition(pos) || pos.insufficient_material() {
                return 0;
            }
            alpha = alpha.max(-MATE + ply as i32);
            beta = beta.min(MATE - ply as i32 - 1);
            if alpha >= beta {
                return alpha;
            }
        }
        if ply >= MAX_PLY - 2 {
            return evaluate(pos);
        }

        let in_check = pos.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 {
            return self.qsearch(pos, alpha, beta, ply);
        }

        self.nodes += 1;
        self.check_time();
        if self.stop {
            return 0;
        }

        let pv_node = beta - alpha > 1;
        let idx = pos.hash as usize & self.tt_mask;
        let entry = self.tt[idx];
        let mut tt_move = Move::NULL;
        if entry.key == pos.hash {
            tt_move = Move::unpack(entry.mv);
            if ply > 0 && !pv_node && entry.depth as i32 >= depth {
                let s = from_tt(entry.score, ply);
                match entry.flag {
                    TT_EXACT => return s,
                    TT_LOWER if s >= beta => return s,
                    TT_UPPER if s <= alpha => return s,
                    _ => {}
                }
            }
        }

        let static_eval = if in_check { -INF } else { evaluate(pos) };

        if !pv_node && !in_check && ply > 0 {
            // Reverse futility pruning.
            if depth <= 6 && static_eval - 90 * depth >= beta && !is_mate_score(beta) {
                return static_eval;
            }
            // Null-move pruning.
            if allow_null && depth >= 3 && static_eval >= beta && pos.has_non_pawn_material(pos.side) {
                let r = 3 + depth / 6;
                let child = pos.make_null();
                self.path.push(pos.hash);
                let s = -self.negamax(&child, depth - 1 - r, -beta, -beta + 1, ply + 1, false);
                self.path.pop();
                if self.stop {
                    return 0;
                }
                if s >= beta && !is_mate_score(s) {
                    return beta;
                }
            }
        }

        let mut list = MoveList::new();
        pos.gen_pseudo(&mut list, false);
        let mut scores = [0i32; 256];
        self.score_moves(pos, list.as_slice(), tt_move, ply, &mut scores);
        let n = list.len();
        let moves = list.as_mut_slice();

        let orig_alpha = alpha;
        let mut best = -INF;
        let mut best_move = Move::NULL;
        let mut legal = 0;

        for i in 0..n {
            // Selection sort: bring the best-scored remaining move forward.
            let mut bi = i;
            for j in i + 1..n {
                if scores[j] > scores[bi] {
                    bi = j;
                }
            }
            moves.swap(i, bi);
            scores.swap(i, bi);
            let m = moves[i];

            let Some(child) = pos.try_make(m) else { continue };
            legal += 1;
            let quiet = !m.is_capture() && !m.is_promo();
            let gives_check = child.in_check();

            // Futility pruning of quiet moves near the leaves.
            if !pv_node && !in_check && quiet && !gives_check && legal > 1 && depth <= 2 && !is_mate_score(alpha) {
                if static_eval + 120 * depth <= alpha {
                    continue;
                }
            }
            // Late move pruning.
            if !pv_node && !in_check && quiet && !gives_check && depth <= 3 && legal > 4 + 4 * depth as usize {
                continue;
            }

            self.path.push(pos.hash);
            let score = if legal == 1 {
                -self.negamax(&child, depth - 1, -beta, -alpha, ply + 1, true)
            } else {
                let mut r = 0;
                if depth >= 3 && legal > 3 && quiet && !in_check && !gives_check {
                    r = 1 + (legal > 8) as i32 + depth / 8;
                    if pv_node {
                        r -= 1;
                    }
                    r = r.clamp(0, depth - 2);
                }
                let mut s = -self.negamax(&child, depth - 1 - r, -alpha - 1, -alpha, ply + 1, true);
                if s > alpha && r > 0 {
                    s = -self.negamax(&child, depth - 1, -alpha - 1, -alpha, ply + 1, true);
                }
                if s > alpha && s < beta {
                    s = -self.negamax(&child, depth - 1, -beta, -alpha, ply + 1, true);
                }
                s
            };
            self.path.pop();
            if self.stop {
                return 0;
            }

            if score > best {
                best = score;
                best_move = m;
                if score > alpha {
                    alpha = score;
                    self.pv[ply][ply] = m;
                    let child_len = self.pv_len[ply + 1];
                    for k in ply + 1..child_len {
                        self.pv[ply][k] = self.pv[ply + 1][k];
                    }
                    self.pv_len[ply] = child_len.max(ply + 1);
                    if score >= beta {
                        if quiet {
                            if self.killers[ply][0] != m {
                                self.killers[ply][1] = self.killers[ply][0];
                                self.killers[ply][0] = m;
                            }
                            let h = &mut self.history[pos.board[m.from as usize] as usize][m.to as usize];
                            *h = (*h + depth * depth).min(500_000);
                        }
                        break;
                    }
                }
            }
        }

        if legal == 0 {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }

        let flag = if best >= beta {
            TT_LOWER
        } else if best > orig_alpha {
            TT_EXACT
        } else {
            TT_UPPER
        };
        self.tt[idx] = TTEntry { key: pos.hash, mv: best_move.pack(), score: to_tt(best, ply), depth: depth as i8, flag };
        best
    }

    fn qsearch(&mut self, pos: &Position, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        self.check_time();
        self.pv_len[ply] = ply;
        if self.stop {
            return 0;
        }
        let stand = evaluate(pos);
        if ply >= MAX_PLY - 2 {
            return stand;
        }
        if stand >= beta {
            return stand;
        }
        if stand > alpha {
            alpha = stand;
        }
        let mut list = MoveList::new();
        pos.gen_pseudo(&mut list, true);
        let mut scores = [0i32; 256];
        self.score_moves(pos, list.as_slice(), Move::NULL, MAX_PLY, &mut scores);
        let n = list.len();
        let moves = list.as_mut_slice();
        let mut best = stand;
        for i in 0..n {
            let mut bi = i;
            for j in i + 1..n {
                if scores[j] > scores[bi] {
                    bi = j;
                }
            }
            moves.swap(i, bi);
            scores.swap(i, bi);
            let m = moves[i];
            let victim = if m.flags & FLAG_EP != 0 { PAWN } else { piece_kind(pos.board[m.to as usize]) };
            if !m.is_promo() && m.is_capture() && stand + ORDER_VALUE[victim as usize] + 200 < alpha {
                continue;
            }
            let Some(child) = pos.try_make(m) else { continue };
            let s = -self.qsearch(&child, -beta, -alpha, ply + 1);
            if self.stop {
                return 0;
            }
            if s > best {
                best = s;
                if s > alpha {
                    alpha = s;
                    self.pv[ply][ply] = m;
                    let child_len = self.pv_len[ply + 1];
                    for k in ply + 1..child_len {
                        self.pv[ply][k] = self.pv[ply + 1][k];
                    }
                    self.pv_len[ply] = child_len.max(ply + 1);
                    if s >= beta {
                        break;
                    }
                }
            }
        }
        best
    }
}

fn to_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s + ply as i32
    } else if s <= -MATE_BOUND {
        s - ply as i32
    } else {
        s
    }
}

fn from_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s - ply as i32
    } else if s <= -MATE_BOUND {
        s + ply as i32
    } else {
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::notation::to_san;

    fn best(fen: &str, depth: u32) -> (String, i32) {
        let p = Position::from_fen(fen).unwrap();
        let mut s = Searcher::new(16);
        let r = s.search(&p, &[], Limits { max_depth: depth, ..Default::default() });
        (to_san(&p, r.best), r.score)
    }

    #[test]
    fn finds_mate_in_one() {
        let (m, s) = best("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", 4);
        assert_eq!(m, "Ra8#");
        assert_eq!(mate_in(s), Some(1));
    }

    #[test]
    fn finds_mate_in_two() {
        // Classic back-rank: 1. Qd8+ Rxd8 2. Rxd8#
        let (m, s) = best("3r2k1/5ppp/8/8/8/8/5PPP/3RQ1K1 w - - 0 1", 6);
        assert!(mate_in(s).is_some(), "score {s} move {m}");
    }

    #[test]
    fn wins_hanging_queen() {
        let (m, _) = best("rnb1kbnr/pppp1ppp/8/4p1q1/4P3/3P4/PPP2PPP/RNBQKBNR w KQkq - 0 3", 5);
        assert_eq!(m, "Bxg5");
    }

    #[test]
    fn knight_fork() {
        // Nc7+ forks king and rook.
        let (m, _) = best("r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1", 6);
        assert_eq!(m, "Nc7+");
    }
}
