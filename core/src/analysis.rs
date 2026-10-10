//! Game review: grade every move and explain mistakes in beginner-friendly language.

use crate::bitboard::*;
use crate::eval::{material_points, HUMAN_VALUE};
use crate::notation::{parse_pgn, to_san, PgnGame};
use crate::position::*;
use crate::search::{is_mate_score, mate_in, Limits, SearchResult, Searcher, MATE};
use crate::ideas::{color_title, ideas_body, ideas_sentence, move_ideas, threat_of, Idea};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug)]
pub struct AnalysisOptions {
    pub ms_per_move: u64,
    pub max_depth: u32,
    /// Username of the player we are coaching; explanations address them as "you".
    pub perspective: Option<usize>,
}

impl Default for AnalysisOptions {
    fn default() -> Self {
        AnalysisOptions { ms_per_move: 150, max_depth: 14, perspective: None }
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct Eval {
    /// Centipawns from White's point of view (None when there is a forced mate).
    pub cp: Option<i32>,
    /// Moves to mate: positive = White mates, negative = Black mates.
    pub mate: Option<i32>,
}

#[derive(Serialize, Clone, Debug)]
pub struct MoveReview {
    pub ply: usize,
    pub move_number: u16,
    pub color: &'static str,
    pub san: String,
    pub uci: String,
    pub from: String,
    pub to: String,
    pub fen_before: String,
    pub fen_after: String,
    pub eval_before: Eval,
    pub eval_after: Eval,
    pub best_san: String,
    pub best_uci: String,
    pub best_line: Vec<String>,
    pub reply_san: Option<String>,
    pub reply_uci: Option<String>,
    pub reply_line: Vec<String>,
    pub class: &'static str,
    pub win_drop: f64,
    pub accuracy: f64,
    pub phase: &'static str,
    pub headline: String,
    pub explanation: String,
    pub tags: Vec<&'static str>,
    /// What the played move is trying to do.
    pub ideas: Vec<Idea>,
    pub ideas_text: String,
    /// What the engine's move would have done (same as `ideas` when the best move was played).
    pub best_ideas: Vec<Idea>,
    pub best_text: Option<String>,
    /// What the opponent was threatening before this move.
    pub opponent_threat: Option<String>,
    pub best_line_moves: Vec<LineMove>,
    pub reply_line_moves: Vec<LineMove>,
    pub cp_loss: i32,
}

#[derive(Serialize, Clone, Debug)]
pub struct LineMove {
    pub san: String,
    pub uci: String,
    /// Position after this move.
    pub fen: String,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct PlanSummary {
    /// "Attacker", "Defender", "Builder" or "Balanced".
    pub style: String,
    pub style_detail: String,
    /// Which side of the board most of the activity was aimed at.
    pub focus: String,
    pub highlights: Vec<String>,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct SideSummary {
    pub accuracy: f64,
    pub best: u32,
    pub excellent: u32,
    pub good: u32,
    pub inaccuracy: u32,
    pub mistake: u32,
    pub blunder: u32,
    pub castled_on_move: Option<u16>,
    /// Average centipawn loss per move.
    pub acpl: f64,
    /// Rough playing strength implied by the accuracy of this game.
    pub estimated_rating: u32,
    pub plan: PlanSummary,
    pub idea_counts: BTreeMap<&'static str, u32>,
}

#[derive(Serialize, Clone, Debug)]
pub struct GameAnalysis {
    pub white: String,
    pub black: String,
    pub white_elo: Option<String>,
    pub black_elo: Option<String>,
    pub result: String,
    pub date: Option<String>,
    pub termination: Option<String>,
    pub start_fen: String,
    pub moves: Vec<MoveReview>,
    pub white_summary: SideSummary,
    pub black_summary: SideSummary,
    pub depth_reached: u32,
}

/// How explanations refer to the player who moved and to their opponent.
struct Voice {
    /// The player who moved, as a sentence subject ("You") and mid-sentence ("you").
    s_cap: &'static str,
    s: &'static str,
    /// The mover's possessive ("your" / "their").
    p: &'static str,
    p_cap: &'static str,
    /// The opponent of the mover.
    o_cap: &'static str,
    o: &'static str,
    op: &'static str,
    op_cap: &'static str,
}

impl Voice {
    fn new(mover: usize, perspective: Option<usize>) -> Voice {
        let v = |s_cap, s, p, p_cap, o_cap, o, op, op_cap| Voice { s_cap, s, p, p_cap, o_cap, o, op, op_cap };
        match perspective {
            Some(me) if me == mover => {
                v("You", "you", "your", "Your", "Your opponent", "your opponent", "their", "Their")
            }
            Some(_) => v("Your opponent", "your opponent", "their", "Their", "You", "you", "your", "Your"),
            None if mover == WHITE => v("White", "White", "their", "Their", "Black", "Black", "their", "Their"),
            None => v("Black", "Black", "their", "Their", "White", "White", "their", "Their"),
        }
    }
}

fn win_pct(cp: i32) -> f64 {
    let x = (cp as f64).clamp(-10_000.0, 10_000.0);
    50.0 + 50.0 * (2.0 / (1.0 + (-0.003_682_08 * x).exp()) - 1.0)
}

pub(crate) fn score_to_cp(score: i32) -> i32 {
    if is_mate_score(score) {
        if score > 0 { 10_000 } else { -10_000 }
    } else {
        score
    }
}

fn to_eval(score_stm: i32, side: usize) -> Eval {
    let white = if side == WHITE { score_stm } else { -score_stm };
    match mate_in(white) {
        Some(m) => Eval { cp: None, mate: Some(m) },
        None => Eval { cp: Some(white), mate: None },
    }
}

fn move_accuracy(drop: f64) -> f64 {
    (103.1668 * (-0.04354 * drop).exp() - 3.1669).clamp(0.0, 100.0)
}

fn describe(score_mover: i32) -> &'static str {
    if is_mate_score(score_mover) {
        return if score_mover > 0 { "a forced checkmate" } else { "getting checkmated" };
    }
    match score_mover {
        s if s >= 300 => "winning",
        s if s >= 150 => "clearly better",
        s if s >= 50 => "slightly better",
        s if s > -50 => "about equal",
        s if s > -150 => "slightly worse",
        s if s > -300 => "clearly worse",
        _ => "losing",
    }
}

pub(crate) fn balance(pos: &Position, color: usize) -> i32 {
    material_points(pos, color) - material_points(pos, color ^ 1)
}

/// Play out `line` from `start`, returning the visited positions (start included) and moves.
pub(crate) fn walk(start: &Position, line: &[Move], max: usize) -> (Vec<Position>, Vec<Move>) {
    let mut positions = vec![*start];
    let mut moves = vec![];
    let mut p = *start;
    for &m in line.iter().take(max) {
        match p.try_make(m) {
            Some(n) => {
                p = n;
                positions.push(p);
                moves.push(m);
            }
            None => break,
        }
    }
    (positions, moves)
}

/// Material balance (for `color`) once the captures at the start of a line have settled.
pub(crate) fn settled_balance(positions: &[Position], moves: &[Move], color: usize, max: usize) -> i32 {
    let k = moves.len();
    // A line that ended on its own already resolved its captures (the search ends in quiescence).
    if k < max {
        return balance(&positions[k], color);
    }
    // Truncated line: back up to the last position not reached by a capture, so we never stop mid-exchange.
    for j in (1..=k).rev() {
        if !moves[j - 1].is_capture() {
            return balance(&positions[j], color);
        }
    }
    balance(&positions[k], color)
}

pub(crate) fn san_line(start: &Position, line: &[Move], max: usize) -> Vec<String> {
    let mut p = *start;
    let mut out = vec![];
    for &m in line.iter().take(max) {
        match p.try_make(m) {
            Some(n) => {
                out.push(to_san(&p, m));
                p = n;
            }
            None => break,
        }
    }
    out
}

pub(crate) fn captured_kind(pos: &Position, m: Move) -> Option<u8> {
    if !m.is_capture() {
        None
    } else if m.flags & FLAG_EP != 0 {
        Some(PAWN)
    } else {
        Some(piece_kind(pos.board[m.to as usize]))
    }
}

/// True if the piece on `sq` can be won: attacked and either undefended or attacked by something cheaper.
pub(crate) fn is_loose(pos: &Position, sq: u8) -> bool {
    let pc = pos.board[sq as usize];
    if pc == EMPTY || piece_kind(pc) == KING {
        return false;
    }
    let c = piece_color(pc);
    let occ = pos.all();
    let attackers = pos.attackers_to(sq, c ^ 1, occ);
    if attackers == 0 {
        return false;
    }
    let defenders = pos.attackers_to(sq, c, occ);
    if defenders == 0 {
        return true;
    }
    let cheapest = Squares(attackers).map(|s| HUMAN_VALUE[piece_kind(pos.board[s as usize]) as usize]).min().unwrap_or(99);
    cheapest < HUMAN_VALUE[piece_kind(pc) as usize]
}

/// Pieces of the side not to move that the piece on `sq` attacks in a forking way.
pub(crate) fn fork_targets(pos: &Position, sq: u8) -> Vec<u8> {
    let pc = pos.board[sq as usize];
    if pc == EMPTY {
        return vec![];
    }
    let me = piece_color(pc);
    let my_value = HUMAN_VALUE[piece_kind(pc) as usize];
    // A forking piece that just gets taken for free is not a real fork.
    let occ = pos.all();
    if pos.attackers_to(sq, me ^ 1, occ) != 0 && pos.attackers_to(sq, me, occ) == 0 && !pos.in_check() {
        return vec![];
    }
    let mut targets: Vec<u8> = Squares(pos.attacks_from(sq) & pos.occ[me ^ 1])
        .filter(|&t| {
            let k = piece_kind(pos.board[t as usize]);
            if k == KING {
                return true;
            }
            if k == PAWN {
                return false;
            }
            HUMAN_VALUE[k as usize] > my_value || pos.attackers_to(t, me ^ 1, occ) == 0
        })
        .collect();
    targets.sort_by_key(|&t| {
        let k = piece_kind(pos.board[t as usize]);
        if k == KING { -100 } else { -HUMAN_VALUE[k as usize] }
    });
    if targets.len() >= 2 {
        targets
    } else {
        vec![]
    }
}

fn list_targets(pos: &Position, targets: &[u8], owner: &str) -> String {
    let names: Vec<String> = targets
        .iter()
        .take(2)
        .map(|&t| {
            let k = piece_kind(pos.board[t as usize]);
            if k == KING { format!("{owner} king") } else { format!("{owner} {}", kind_name(k)) }
        })
        .collect();
    names.join(" and ")
}

pub(crate) fn game_phase(pos: &Position, move_number: u16) -> &'static str {
    let npm: i32 = [WHITE, BLACK]
        .iter()
        .map(|&c| {
            pos.pieces(c, KNIGHT).count_ones() as i32 * 3
                + pos.pieces(c, BISHOP).count_ones() as i32 * 3
                + pos.pieces(c, ROOK).count_ones() as i32 * 5
                + pos.pieces(c, QUEEN).count_ones() as i32 * 9
        })
        .sum();
    if move_number <= 10 && npm >= 56 {
        "opening"
    } else if npm <= 26 {
        "endgame"
    } else {
        "middlegame"
    }
}

struct Explained {
    headline: String,
    text: String,
    tags: Vec<&'static str>,
}

struct Ctx<'a> {
    pos: &'a Position,
    after: &'a Position,
    played: Move,
    best: &'a SearchResult,
    reply: &'a SearchResult,
    before_score: i32,
    after_score: i32,
    class: &'static str,
    voice: Voice,
    move_number: u16,
}

fn explain(c: &Ctx) -> Explained {
    let v = &c.voice;
    let mover = c.pos.side;
    let opp = mover ^ 1;
    let best_san = to_san(c.pos, c.best.best);
    let played_san = to_san(c.pos, c.played);
    let mut tags: Vec<&'static str> = vec![];
    let bad = matches!(c.class, "inaccuracy" | "mistake" | "blunder");
    let label = match c.class {
        "blunder" => "Blunder",
        "mistake" => "Mistake",
        "inaccuracy" => "Inaccuracy",
        _ => "",
    };

    // Habit: early queen adventures.
    let moved_kind = piece_kind(c.pos.board[c.played.from as usize]);
    if moved_kind == QUEEN && c.move_number <= 7 {
        let back = if mover == WHITE { RANK_1 } else { RANK_8 };
        let undeveloped = ((c.pos.pieces(mover, KNIGHT) | c.pos.pieces(mover, BISHOP)) & back).count_ones();
        if undeveloped >= 3 {
            tags.push("early_queen");
        }
    }
    if moved_kind == KING && c.played.flags & FLAG_CASTLE == 0 && c.move_number <= 15 && c.pos.pieces(opp, QUEEN) != 0
    {
        tags.push("early_king_move");
    }

    if c.after.is_checkmate() {
        return Explained { headline: "Checkmate!".into(), text: format!("{} delivered checkmate. Game over.", v.s_cap), tags };
    }

    if !bad {
        let gained = captured_kind(c.pos, c.played);
        let headline = match c.class {
            "forced" => "Only move".to_string(),
            "best" => match gained {
                Some(k) => format!("Best move, takes the {}", kind_name(k)),
                _ => "Best move".to_string(),
            },
            "excellent" => "Excellent".to_string(),
            _ => "Good move".to_string(),
        };
        let text = match c.class {
            "best" | "forced" => {
                if let Some(t) = forks_after(c.after, c.played.to) {
                    tags.push("found_fork");
                    format!("Nice fork: the {} attacks {} at once.", kind_name(moved_kind), list_targets(c.after, &t, v.op))
                } else {
                    "This is what the engine would play too.".to_string()
                }
            }
            _ => format!("Solid. The engine slightly preferred {best_san}."),
        };
        return Explained { headline, text, tags };
    }

    let before_desc = describe(c.before_score);
    let after_desc = describe(c.after_score);
    let swing = if before_desc == after_desc {
        let slip = if c.before_score > 50 { "let some of the advantage slip" } else { "made things harder" };
        format!("The position is still {after_desc} for {}, but this {slip}.", v.s)
    } else {
        format!("The position went from {before_desc} to {after_desc} for {}.", v.s)
    };

    // 1. Walked into a forced mate.
    if let Some(n) = mate_in(c.reply.score).filter(|&n| n > 0) {
        tags.push("allowed_mate");
        let reply_san = to_san(c.after, c.reply.best);
        let text = if n == 1 {
            format!("This lets {} checkmate right away with {reply_san}. Before every move, look at the checks and captures the other side gets. {best_san} was needed.", v.o)
        } else {
            format!("This allows a forced checkmate in {n}, starting with {reply_san}. {best_san} would have kept {} safe.", format!("{} king", v.p))
        };
        return Explained { headline: format!("{label}: allows checkmate"), text, tags };
    }

    // 2. Missed a forced mate.
    if let Some(n) = mate_in(c.before_score).filter(|&n| n > 0) {
        if mate_in(c.after_score).map_or(true, |m| m <= 0) {
            tags.push("missed_mate");
            let text = if n == 1 {
                format!("{} had checkmate in one move with {best_san}! Look for checks first: they're the most forcing moves.", v.s_cap)
            } else {
                format!("{} had a forced checkmate in {n}, starting with {best_san}.", v.s_cap)
            };
            return Explained { headline: format!("{label}: missed checkmate"), text, tags };
        }
    }

    // 3. Material: what the opponent's best reply wins.
    let (r_pos, r_moves) = walk(c.after, &c.reply.pv, 8);
    let before_bal = balance(c.pos, mover);
    let reply_bal = settled_balance(&r_pos, &r_moves, mover, 8);
    let lost = before_bal - reply_bal;

    let mut best_line = vec![c.best.best];
    best_line.extend(c.best.pv.iter().skip(1).copied());
    let (b_pos, b_moves) = walk(c.pos, &best_line, 8);
    let best_bal = settled_balance(&b_pos, &b_moves, mover, 8);
    let could_gain = best_bal - before_bal;

    let better = format!("{best_san} was better.");
    // A bigger missed win is the real lesson, even if the played move also lost something.
    let prefer_missed = could_gain >= 2 && could_gain > lost;

    if lost >= 2 && !prefer_missed {
        // First capture of one of the mover's pieces in the opponent's line.
        let first_cap = r_moves.iter().enumerate().step_by(2).find_map(|(i, &m)| {
            captured_kind(&r_pos[i], m).filter(|&k| k != PAWN || lost <= 2).map(|k| (i, m, k))
        });
        if let Some((i, m, kind)) = first_cap {
            let cap_san = to_san(&r_pos[i], m);
            let sq = square_name(m.to);
            let kname = kind_name(kind);

            if i == 0 {
                // Did the reply fork rather than capture? Handled below; this is a direct capture.
                let defended = c.after.attackers_to(m.to, mover, c.after.all()) != 0;
                let attacker_kind = piece_kind(c.after.board[m.from as usize]);
                let cheaper_attacker = HUMAN_VALUE[attacker_kind as usize] < HUMAN_VALUE[kind as usize];
                if m.to == c.played.to && c.played.flags & FLAG_CASTLE == 0 && (!defended || cheaper_attacker) {
                    tags.push("hung_piece");
                    let text = if defended {
                        let attacker = kind_name(attacker_kind);
                        format!(
                            "{} moved {} {kname} to {sq}, where {} {attacker} can take it. It's protected, but a {kname} is worth more than a {attacker}, so this loses material. {better}",
                            v.s_cap, v.p, v.op
                        )
                    } else {
                        format!(
                            "{} moved {} {kname} to {sq}, where nothing protects it. {} can just take it with {cap_san}. Before each move, ask: can this piece be captured? {better}",
                            v.s_cap, v.p, v.o_cap
                        )
                    };
                    return Explained { headline: format!("{label}: hangs the {kname}"), text, tags };
                }

                let was_protector = c.pos.attacks_from(c.played.from) & bit(m.to) != 0
                    && c.after.attackers_to(m.to, mover, c.after.all()) == 0;
                if was_protector {
                    tags.push("hung_piece");
                    let text = format!(
                        "Moving {} {} away left {} {kname} on {sq} unprotected, and {cap_san} wins it. {better}",
                        v.p,
                        kind_name(moved_kind),
                        v.p
                    );
                    return Explained { headline: format!("{label}: leaves the {kname} unprotected"), text, tags };
                }

                if c.pos.board[m.to as usize] == c.after.board[m.to as usize] && is_loose(c.pos, m.to) {
                    tags.push("ignored_threat");
                    let text = format!(
                        "{} {kname} on {sq} was already under attack, and this move didn't save it. {} can take it with {cap_san}. When a piece is attacked, move it, protect it, or counter-attack something bigger. {better}",
                        v.p_cap,
                        v.o_cap
                    );
                    return Explained { headline: format!("{label}: ignores a threat"), text, tags };
                }

                tags.push("hung_piece");
                let text = format!(
                    "This leaves {} {kname} on {sq} hanging. {} can win it with {cap_san}. {better}",
                    v.p, v.o_cap
                );
                return Explained { headline: format!("{label}: loses the {kname}"), text, tags };
            }

            // Capture comes later: look for a fork / tactic on the first reply move.
            let first = r_moves[0];
            let after_reply = &r_pos[1];
            let fork = fork_targets(after_reply, first.to);
            let reply_san = to_san(c.after, first);
            if !fork.is_empty() {
                tags.push("allowed_fork");
                let forker = kind_name(piece_kind(after_reply.board[first.to as usize]));
                let text = format!(
                    "This allows {reply_san}, a fork: {} {forker} attacks {} at the same time, so {} can't save both. {better}",
                    v.op,
                    list_targets(after_reply, &fork, v.p),
                    v.s
                );
                return Explained { headline: format!("{label}: allows a fork"), text, tags };
            }
            if pins_or_skewers(after_reply, first.to) {
                tags.push("allowed_pin");
                let text = format!(
                    "This allows {reply_san}, which attacks one of {} pieces with a more valuable piece lined up behind it. That costs {} {kname}. {better}",
                    v.p, v.p
                );
                return Explained { headline: format!("{label}: allows a pin"), text, tags };
            }
            tags.push("lost_material");
            let line = san_line(c.after, &c.reply.pv, (i + 1).min(5)).join(" ");
            let text = format!(
                "This lets {} win material. After {line}, {} {kname} falls. {better}",
                v.o, v.p
            );
            return Explained { headline: format!("{label}: loses the {kname}"), text, tags };
        }
    }

    // 4. Missed a chance to win material.
    if could_gain >= 2 {
        let best_m = c.best.best;
        let after_best = &b_pos[1.min(b_pos.len() - 1)];
        let fork = if b_pos.len() > 1 { fork_targets(after_best, best_m.to) } else { vec![] };
        if !fork.is_empty() && !best_m.is_capture() {
            tags.push("missed_fork");
            let text = format!(
                "{} missed a fork. {best_san} would attack {} at once.",
                v.s_cap,
                list_targets(after_best, &fork, v.op)
            );
            return Explained { headline: format!("{label}: missed a fork"), text, tags };
        }
        let first_win = b_moves.iter().enumerate().step_by(2).find_map(|(i, &m)| captured_kind(&b_pos[i], m).map(|k| (i, m, k)));
        if let Some((i, m, kind)) = first_win {
            tags.push("missed_win");
            let kname = kind_name(kind);
            let text = if i == 0 && c.pos.attackers_to(m.to, opp, c.pos.all()) == 0 {
                format!(
                    "{} {kname} on {} was unprotected. {best_san} wins it for free. Before each move, check whether anything can be captured.",
                    v.op_cap,
                    square_name(m.to)
                )
            } else {
                let line = san_line(c.pos, &best_line, (i + 1).min(5)).join(" ");
                format!("{} could have won {} {kname} with {line}.", v.s_cap, v.op)
            };
            return Explained { headline: format!("{label}: missed winning the {kname}"), text, tags };
        }
    }

    // 5. Allowed a fork even when the material count looks fine at the end.
    if let Some(&first) = c.reply.pv.first() {
        if let Some(after_reply) = c.after.try_make(first) {
            let fork = fork_targets(&after_reply, first.to);
            if fork.len() >= 2 && c.class != "inaccuracy" {
                tags.push("allowed_fork");
                let text = format!(
                    "This allows {}, attacking {} at once. {better}",
                    to_san(c.after, first),
                    list_targets(&after_reply, &fork, v.p)
                );
                return Explained { headline: format!("{label}: allows a fork"), text, tags };
            }
        }
    }

    // 6. Positional fallback.
    tags.push("positional");
    let hint = if tags.contains(&"early_queen") {
        " Bringing the queen out early lets the other side develop with tempo by attacking it."
    } else if tags.contains(&"early_king_move") {
        " Moving the king early (without castling) usually leaves it exposed."
    } else if played_san.starts_with('f') && c.move_number <= 12 {
        tags.push("weakened_king");
        " Pushing the f-pawn early weakens the squares around the king."
    } else {
        ""
    };
    let best_m = c.best.best;
    let why = if let Some(k) = captured_kind(c.pos, best_m) {
        format!("{best_san} would have taken {} {}.", v.op, kind_name(k))
    } else if c.pos.board[best_m.from as usize] != EMPTY && is_loose(c.pos, best_m.from) {
        format!(
            "{best_san} would have moved {} attacked {} to safety.",
            v.p,
            kind_name(piece_kind(c.pos.board[best_m.from as usize]))
        )
    } else if c.pos.try_make(best_m).is_some_and(|p| p.in_check()) {
        format!("{best_san}, a check, was stronger and keeps the pressure on.")
    } else if best_m.flags & FLAG_CASTLE != 0 {
        format!("Castling ({best_san}) was better: it gets the king safe and the rook into play.")
    } else {
        format!("{best_san} was the stronger move here.")
    };
    Explained { headline: format!("{label}: {best_san} was better"), text: format!("{swing}{hint} {why}"), tags }
}

fn forks_after(pos: &Position, sq: u8) -> Option<Vec<u8>> {
    let t = fork_targets(pos, sq);
    // Only celebrate forks that include the king or a queen/rook.
    let big = t.iter().filter(|&&s| matches!(piece_kind(pos.board[s as usize]), KING | QUEEN | ROOK)).count();
    if t.len() >= 2 && big >= 1 {
        Some(t)
    } else {
        None
    }
}

/// Slider on `sq` attacks an enemy piece with another enemy piece directly behind it on the same line.
fn pins_or_skewers(pos: &Position, sq: u8) -> bool {
    let pc = pos.board[sq as usize];
    if pc == EMPTY {
        return false;
    }
    let kind = piece_kind(pc);
    if !matches!(kind, BISHOP | ROOK | QUEEN) {
        return false;
    }
    let me = piece_color(pc);
    let occ = pos.all();
    let direct = pos.attacks_from(sq) & pos.occ[me ^ 1];
    for front in Squares(direct) {
        let without = occ & !bit(front);
        let xray = match kind {
            BISHOP => bishop_attacks(sq, without),
            ROOK => rook_attacks(sq, without),
            _ => bishop_attacks(sq, without) | rook_attacks(sq, without),
        } & !pos.attacks_from(sq)
            & pos.occ[me ^ 1];
        for back in Squares(xray) {
            if between(sq, back) & bit(front) != 0 {
                let bk = piece_kind(pos.board[back as usize]);
                let fk = piece_kind(pos.board[front as usize]);
                if bk == KING || HUMAN_VALUE[bk as usize] > HUMAN_VALUE[kind as usize] || fk == KING || fk == QUEEN {
                    return true;
                }
            }
        }
    }
    false
}

fn classify(drop: f64, played_is_best: bool, only_move: bool) -> &'static str {
    if only_move {
        "forced"
    } else if played_is_best {
        "best"
    } else if drop < 2.0 {
        "excellent"
    } else if drop < 10.0 {
        "good"
    } else if drop < 20.0 {
        "inaccuracy"
    } else if drop < 30.0 {
        "mistake"
    } else {
        "blunder"
    }
}

/// Analyse a full game. `progress(done, total)` is called after each position.
pub fn analyze_game(game: &PgnGame, opts: AnalysisOptions, mut progress: impl FnMut(usize, usize)) -> GameAnalysis {
    let mut positions = vec![game.start];
    for &m in &game.moves {
        let p = positions.last().unwrap().make(m);
        positions.push(p);
    }
    let hashes: Vec<u64> = positions.iter().map(|p| p.hash).collect();

    let mut searcher = Searcher::new(32);
    let total = positions.len();
    let mut results: Vec<SearchResult> = Vec::with_capacity(total);
    let mut depth_sum = 0u32;
    for (i, p) in positions.iter().enumerate() {
        let r = searcher.search(p, &hashes[..i], Limits { max_depth: opts.max_depth, time_ms: Some(opts.ms_per_move), nodes: None });
        depth_sum += r.depth;
        results.push(r);
        progress(i + 1, total);
    }

    let mut moves = Vec::with_capacity(game.moves.len());
    let mut sums = [SideSummary::default(), SideSummary::default()];
    let mut idea_searcher = Searcher::new(8);
    let mut tallies = [PlanTally::default(), PlanTally::default()];
    let mut acc_total = [0.0f64; 2];
    let mut acc_count = [0u32; 2];

    for (i, &m) in game.moves.iter().enumerate() {
        let pos = &positions[i];
        let after = &positions[i + 1];
        let mover = pos.side;
        let before_score = results[i].score;
        let mut after_score = if after.is_checkmate() {
            MATE - 1
        } else {
            -results[i + 1].score
        };
        let played_is_best = m == results[i].best;
        if played_is_best && !is_mate_score(before_score) {
            // Same move as the engine: differences are search noise, not the player's fault.
            after_score = after_score.max(before_score);
        }
        let only_move = pos.legal_moves().len() == 1;
        let drop = (win_pct(score_to_cp(before_score)) - win_pct(score_to_cp(after_score))).max(0.0);
        let class = classify(drop, played_is_best, only_move);
        let acc = move_accuracy(drop);
        acc_total[mover] += acc;
        acc_count[mover] += 1;
        let s = &mut sums[mover];
        match class {
            "best" | "forced" => s.best += 1,
            "excellent" => s.excellent += 1,
            "good" => s.good += 1,
            "inaccuracy" => s.inaccuracy += 1,
            "mistake" => s.mistake += 1,
            _ => s.blunder += 1,
        }
        if m.flags & FLAG_CASTLE != 0 && s.castled_on_move.is_none() {
            s.castled_on_move = Some(pos.fullmove);
        }

        let ctx = Ctx {
            pos,
            after,
            played: m,
            best: &results[i],
            reply: &results[i + 1],
            before_score,
            after_score,
            class,
            voice: Voice::new(mover, opts.perspective),
            move_number: pos.fullmove,
        };
        let ex = explain(&ctx);

        let best_line = san_line(pos, &results[i].pv, 6);
        let reply_moves: Vec<Move> = if after.legal_moves().is_empty() { vec![] } else { results[i + 1].pv.clone() };
        let reply_line = san_line(after, &reply_moves, 6);

        // Ideas behind the played move and the engine's move.
        let threat_before = threat_of(&mut idea_searcher, pos);
        let reply_wins = mate_in(results[i + 1].score).is_some_and(|n| n > 0) || {
            let (rp, rm) = walk(after, &reply_moves, 8);
            balance(pos, mover) - settled_balance(&rp, &rm, mover, 8) >= 2
        };
        let prev = if i > 0 { Some(game.moves[i - 1]) } else { None };
        let san = to_san(pos, m);
        let best_san = to_san(pos, results[i].best);
        let ideas = move_ideas(pos, m, prev, threat_before.as_ref(), reply_wins, &mut idea_searcher);
        let best_ideas = if played_is_best {
            ideas.clone()
        } else {
            move_ideas(pos, results[i].best, prev, threat_before.as_ref(), false, &mut idea_searcher)
        };
        let ideas_text = ideas_sentence(&san, &ideas);
        let best_text = (!played_is_best).then(|| {
            let mut t = format!("The engine's choice was {best_san}, which {}.", ideas_body(&best_ideas));
            if best_line.len() > 1 {
                t.push_str(&format!(" A likely continuation: {}.", best_line.iter().take(5).cloned().collect::<Vec<_>>().join(" ")));
            }
            t
        });
        let opponent_threat = threat_before.as_ref().map(|t| {
            let what = if t.mate { "checkmate" } else { "winning material" };
            format!("{} was threatening {} ({what}).", color_title(mover ^ 1), t.san)
        });
        let cap = |s: i32| score_to_cp(s).clamp(-1000, 1000);
        let cp_loss = if played_is_best { 0 } else { (cap(before_score) - cap(after_score)).max(0) };

        let tally = &mut tallies[mover];
        tally.moves += 1;
        tally.cp_loss += cp_loss as i64;
        for idea in &ideas {
            *sums[mover].idea_counts.entry(idea.kind).or_insert(0) += 1;
        }
        let has = |k: &[&str]| ideas.iter().any(|i| k.contains(&i.kind));
        if has(&["attack", "fork", "pin", "king_attack", "check", "checkmate"]) {
            tally.attacking += 1;
        }
        if has(&["king_attack", "check", "checkmate"]) {
            tally.king_hunting += 1;
        }
        if has(&["defend", "save_piece"]) {
            tally.defending += 1;
        }
        if has(&["develop", "center", "castle", "prepare_castle", "improve"]) {
            tally.building += 1;
        }
        if pos.fullmove <= 10 && has(&["develop"]) {
            tally.developed_early += 1;
        }
        if threat_before.is_some() && reply_wins && matches!(class, "mistake" | "blunder") {
            tally.missed_threats += 1;
        }
        if game_phase(pos, pos.fullmove) != "opening" {
            tally.file_sum += file_of(m.to) as u32;
            tally.file_n += 1;
        }
        *tally.piece_moves.entry(kind_name(piece_kind(pos.board[m.from as usize]))).or_insert(0) += 1;

        moves.push(MoveReview {
            ply: i + 1,
            move_number: pos.fullmove,
            color: if mover == WHITE { "white" } else { "black" },
            san,
            uci: m.uci(),
            from: square_name(m.from),
            to: square_name(m.to),
            fen_before: pos.to_fen(),
            fen_after: after.to_fen(),
            eval_before: to_eval(before_score, mover),
            eval_after: to_eval(after_score, mover),
            best_san,
            best_uci: results[i].best.uci(),
            best_line,
            reply_san: reply_line.first().cloned(),
            reply_uci: reply_moves.first().map(|m| m.uci()),
            reply_line,
            class,
            win_drop: (drop * 10.0).round() / 10.0,
            accuracy: (acc * 10.0).round() / 10.0,
            phase: game_phase(pos, pos.fullmove),
            headline: ex.headline,
            explanation: ex.text,
            tags: ex.tags,
            ideas,
            ideas_text,
            best_ideas,
            best_text,
            opponent_threat,
            best_line_moves: line_moves(pos, &results[i].pv, 6),
            reply_line_moves: line_moves(after, &reply_moves, 6),
            cp_loss,
        });
    }

    for c in [WHITE, BLACK] {
        sums[c].accuracy = if acc_count[c] > 0 { ((acc_total[c] / acc_count[c] as f64) * 10.0).round() / 10.0 } else { 0.0 };
        let t = &tallies[c];
        let acpl = if t.moves > 0 { t.cp_loss as f64 / t.moves as f64 } else { 0.0 };
        sums[c].acpl = (acpl * 10.0).round() / 10.0;
        sums[c].estimated_rating = rating_from_acpl(acpl);
        sums[c].plan = plan_summary(t, sums[c].castled_on_move);
    }
    let [white_summary, black_summary] = sums;
    let h = |k: &str| game.header(k).map(|s| s.to_string());
    GameAnalysis {
        white: h("White").unwrap_or_else(|| "White".into()),
        black: h("Black").unwrap_or_else(|| "Black".into()),
        white_elo: h("WhiteElo"),
        black_elo: h("BlackElo"),
        result: h("Result").unwrap_or_else(|| "*".into()),
        date: h("Date"),
        termination: h("Termination"),
        start_fen: game.start.to_fen(),
        moves,
        white_summary,
        black_summary,
        depth_reached: if total > 0 { depth_sum / total as u32 } else { 0 },
    }
}

#[derive(Default)]
struct PlanTally {
    moves: u32,
    cp_loss: i64,
    attacking: u32,
    king_hunting: u32,
    defending: u32,
    building: u32,
    developed_early: u32,
    missed_threats: u32,
    file_sum: u32,
    file_n: u32,
    piece_moves: BTreeMap<&'static str, u32>,
}

/// Map average centipawn loss to an approximate rating. Lower loss = stronger play.
/// Calibrated on real ~400-rated Chess.com games reviewed by this engine (median loss ~60).
/// Losses are capped at 10 pawns per move, so decided games understate errors; the curve is
/// steeper than published Stockfish-based fits to compensate.
pub fn rating_from_acpl(acpl: f64) -> u32 {
    let r = 4000.0 * (-0.035 * acpl).exp();
    ((r / 25.0).round() * 25.0).clamp(100.0, 2800.0) as u32
}

fn plan_summary(t: &PlanTally, castled: Option<u16>) -> PlanSummary {
    if t.moves == 0 {
        return PlanSummary::default();
    }
    let pct = |n: u32| n * 100 / t.moves;
    let (style, detail) = if pct(t.attacking) >= 40 {
        ("Attacker", format!("{}% of the moves created threats or attacked something.", pct(t.attacking)))
    } else if pct(t.defending) >= 25 {
        ("Defender", format!("{}% of the moves were spent defending or saving pieces.", pct(t.defending)))
    } else if pct(t.building) >= 40 {
        ("Builder", format!("{}% of the moves developed, improved pieces or took the center.", pct(t.building)))
    } else {
        ("Balanced", format!("A mix: {}% attacking, {}% defending.", pct(t.attacking), pct(t.defending)))
    };
    let focus = if t.file_n == 0 {
        "the center".to_string()
    } else {
        let avg = t.file_sum as f64 / t.file_n as f64;
        if avg < 2.8 {
            "the queenside".into()
        } else if avg > 4.2 {
            "the kingside".into()
        } else {
            "the center".into()
        }
    };
    let mut highlights = vec![];
    highlights.push(match t.developed_early {
        0 => "Developed no knights or bishops in the first 10 moves.".to_string(),
        1 => "Developed only 1 minor piece in the first 10 moves.".to_string(),
        n => format!("Developed {n} minor pieces in the first 10 moves."),
    });
    highlights.push(match castled {
        Some(m) if m <= 10 => format!("Castled early, on move {m}."),
        Some(m) => format!("Castled late, on move {m}."),
        None => "Never castled.".to_string(),
    });
    if t.king_hunting > 0 {
        highlights.push(format!("Made {} moves aimed at the enemy king.", t.king_hunting));
    }
    if t.missed_threats > 0 {
        highlights.push(format!(
            "Missed {} threat{} from the opponent.",
            t.missed_threats,
            if t.missed_threats == 1 { "" } else { "s" }
        ));
    }
    if let Some((piece, n)) = t.piece_moves.iter().filter(|(k, _)| **k != "pawn").max_by_key(|(_, n)| **n) {
        highlights.push(format!("Busiest piece: the {piece} ({n} moves)."));
    }
    PlanSummary { style: style.into(), style_detail: detail, focus, highlights }
}

fn line_moves(start: &Position, line: &[Move], max: usize) -> Vec<LineMove> {
    let mut p = *start;
    let mut out = vec![];
    for &m in line.iter().take(max) {
        match p.try_make(m) {
            Some(n) => {
                out.push(LineMove { san: to_san(&p, m), uci: m.uci(), fen: n.to_fen() });
                p = n;
            }
            None => break,
        }
    }
    out
}

/// Parse a PGN and analyse it. `username` (case-insensitive) picks whose point of view to explain from.
pub fn analyze_pgn(
    pgn: &str,
    username: Option<&str>,
    ms_per_move: u64,
    progress: impl FnMut(usize, usize),
) -> Result<GameAnalysis, String> {
    let game = parse_pgn(pgn).map_err(|e| e.to_string())?;
    let perspective = username.and_then(|u| {
        let u = u.to_lowercase();
        if game.header("White").map(|w| w.to_lowercase()) == Some(u.clone()) {
            Some(WHITE)
        } else if game.header("Black").map(|b| b.to_lowercase()) == Some(u) {
            Some(BLACK)
        } else {
            None
        }
    });
    let opts = AnalysisOptions { ms_per_move, perspective, ..Default::default() };
    Ok(analyze_game(&game, opts, progress))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn review(pgn: &str) -> GameAnalysis {
        let g = parse_pgn(pgn).unwrap();
        analyze_game(&g, AnalysisOptions { ms_per_move: 60, max_depth: 8, perspective: Some(WHITE) }, |_, _| {})
    }

    #[test]
    fn scholars_mate_is_explained() {
        let a = review("1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0");
        let nf6 = &a.moves[5];
        assert_eq!(nf6.class, "blunder");
        assert!(nf6.tags.contains(&"allowed_mate"), "{:?}", nf6);
        assert!(nf6.explanation.contains("Qxf7#"));
        assert_eq!(a.moves[6].headline, "Checkmate!");
    }

    #[test]
    fn hanging_queen_is_explained() {
        let a = review("1. e4 e5 2. Bc4 Nf6 3. Qh5 Nxh5 0-1");
        let qh5 = &a.moves[4];
        assert_eq!(qh5.class, "blunder");
        assert!(qh5.tags.contains(&"hung_piece"), "{:?}", qh5);
        assert!(qh5.explanation.starts_with("You moved your queen to h5"), "{}", qh5.explanation);
    }
}
