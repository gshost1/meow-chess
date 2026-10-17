//! Figures out what a move is *trying* to do: attack, defend, develop, threaten, and so on.
//! Texts are written in neutral third person so they read correctly for either player.

use crate::analysis::{balance, captured_kind, fork_targets, is_loose, settled_balance, walk};
use crate::bitboard::*;
use crate::eval::HUMAN_VALUE;
use crate::notation::to_san;
use crate::position::*;
use crate::search::{mate_in, Limits, Searcher};
use serde::Serialize;

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Idea {
    /// Machine-readable category (used by the app's "what was your idea?" quiz).
    pub kind: &'static str,
    /// Lower-case verb phrase, e.g. "attacks the black queen on d8".
    pub text: String,
}

#[derive(Clone, Debug)]
pub struct Threat {
    pub mv: Move,
    pub san: String,
    pub mate: bool,
    pub gain: i32,
}

pub fn color_name(c: usize) -> &'static str {
    if c == WHITE {
        "white"
    } else {
        "black"
    }
}

pub fn color_title(c: usize) -> &'static str {
    if c == WHITE {
        "White"
    } else {
        "Black"
    }
}

fn desc(pos: &Position, sq: u8) -> String {
    let pc = pos.board[sq as usize];
    format!("the {} {} on {}", color_name(piece_color(pc)), kind_name(piece_kind(pc)), square_name(sq))
}

const CENTER: Bitboard = (1 << 27) | (1 << 28) | (1 << 35) | (1 << 36);

/// What the side *not* to move in `pos` threatens to do if given a free move.
pub fn threat_of(searcher: &mut Searcher, pos: &Position) -> Option<Threat> {
    if pos.in_check() {
        return None;
    }
    let np = pos.make_null();
    let r = searcher.search(&np, &[], Limits { max_depth: 4, time_ms: None, nodes: Some(40_000) });
    if r.best.is_null() {
        return None;
    }
    let attacker = np.side;
    let san = to_san(&np, r.best);
    if let Some(n) = mate_in(r.score) {
        if n > 0 && n <= 2 {
            return Some(Threat { mv: r.best, san, mate: true, gain: 0 });
        }
    }
    let (ps, ms) = walk(&np, &r.pv, 6);
    let gain = settled_balance(&ps, &ms, attacker, 6) - balance(&np, attacker);
    if gain >= 2 {
        Some(Threat { mv: r.best, san, mate: false, gain })
    } else {
        None
    }
}

fn castle_path_clear(p: &Position, us: usize) -> bool {
    let base = if us == WHITE { 0u8 } else { 56u8 };
    if p.king_sq(us) != base + 4 {
        return false;
    }
    let (k, q) = if us == WHITE { (WK, WQ) } else { (BK, BQ) };
    let occ = p.all();
    (p.castling & k != 0 && occ & (bit(base + 5) | bit(base + 6)) == 0)
        || (p.castling & q != 0 && occ & (bit(base + 1) | bit(base + 2) | bit(base + 3)) == 0)
}

fn is_passed(p: &Position, sq: u8, us: usize) -> bool {
    let f = file_of(sq);
    let mut files = file_mask(f);
    if f > 0 {
        files |= file_mask(f - 1);
    }
    if f < 7 {
        files |= file_mask(f + 1);
    }
    let r = rank_of(sq) as u32;
    let ahead = if us == WHITE {
        if r >= 7 { 0 } else { !0u64 << ((r + 1) * 8) }
    } else if r == 0 {
        0
    } else {
        (1u64 << (r * 8)) - 1
    };
    p.pieces(us ^ 1, PAWN) & files & ahead == 0
}

/// A slider on `sq` pinning or skewering two enemy pieces: (front, back, is_pin).
pub(crate) fn pin_details(pos: &Position, sq: u8) -> Option<(u8, u8, bool)> {
    let pc = pos.board[sq as usize];
    if pc == EMPTY {
        return None;
    }
    let kind = piece_kind(pc);
    if !matches!(kind, BISHOP | ROOK | QUEEN) {
        return None;
    }
    let me = piece_color(pc);
    let occ = pos.all();
    let direct = pos.attacks_from(sq);
    for front in Squares(direct & pos.occ[me ^ 1]) {
        let without = occ & !bit(front);
        let xray = match kind {
            BISHOP => bishop_attacks(sq, without),
            ROOK => rook_attacks(sq, without),
            _ => bishop_attacks(sq, without) | rook_attacks(sq, without),
        } & !direct
            & pos.occ[me ^ 1];
        for back in Squares(xray) {
            if between(sq, back) & bit(front) == 0 {
                continue;
            }
            let bk = piece_kind(pos.board[back as usize]);
            let fk = piece_kind(pos.board[front as usize]);
            let bv = if bk == KING { 100 } else { HUMAN_VALUE[bk as usize] };
            let fv = if fk == KING { 100 } else { HUMAN_VALUE[fk as usize] };
            if fk == PAWN && bk != KING {
                continue;
            }
            if bv > fv && bv > HUMAN_VALUE[kind as usize].min(fv.max(1)) {
                return Some((front, back, true));
            }
            if fv > bv && (fk == KING || fk == QUEEN) && bk != PAWN {
                return Some((front, back, false));
            }
        }
    }
    None
}

/// Ideas behind move `m` in `pos`.
///
/// `threat_before`: what the opponent was threatening before the move.
/// `reply_wins`: whether the opponent's best reply still wins material / mates.
pub fn move_ideas(
    pos: &Position,
    m: Move,
    prev: Option<Move>,
    threat_before: Option<&Threat>,
    reply_wins: bool,
    searcher: &mut Searcher,
) -> Vec<Idea> {
    let us = pos.side;
    let them = us ^ 1;
    let Some(after) = pos.try_make(m) else { return vec![] };
    let kind = piece_kind(pos.board[m.from as usize]);
    let kname = kind_name(kind);
    let mut ideas: Vec<Idea> = Vec::new();

    if after.is_checkmate() {
        add(&mut ideas, "checkmate", "delivers checkmate".into());
        return ideas;
    }

    let was_in_check = pos.in_check();
    if was_in_check {
        let text = if kind == KING {
            "steps the king out of check".to_string()
        } else if m.is_capture() {
            "gets out of check by capturing the checking piece".to_string()
        } else {
            format!("blocks the check with the {kname}")
        };
        add(&mut ideas, "defend", text);
    }

    if let Some(v) = captured_kind(pos, m) {
        let occ = after.all();
        let recapturers = after.attackers_to(m.to, them, occ);
        let landing = if m.is_promo() { m.promo } else { kind };
        let lv = HUMAN_VALUE[landing as usize];
        let vv = HUMAN_VALUE[v as usize];
        let victim = format!("the {} {} on {}", color_name(them), kind_name(v), square_name(m.to));
        if prev.is_some_and(|p| p.to == m.to && p.is_capture()) {
            add(&mut ideas, "capture", format!("takes back on {} to win back the material", square_name(m.to)));
        } else if recapturers == 0 {
            add(&mut ideas, "capture", format!("wins {victim} for free"));
        } else if vv > lv {
            add(&mut ideas, "capture", format!("captures {victim}, which is worth more than the {kname}"));
        } else if vv == lv && kind != KING {
            if v == landing {
                add(&mut ideas, "trade", format!("offers a trade of {}s", kind_name(v)));
            } else {
                add(&mut ideas, "trade", format!("trades the {kname} for {victim}"));
            }
        } else {
            add(&mut ideas, "capture", format!("takes {victim}, although the {kname} can be taken back"));
        }
    }

    if m.is_promo() {
        add(&mut ideas, "promote", format!("promotes the pawn to a {}", kind_name(m.promo)));
    }
    if m.flags & FLAG_CASTLE != 0 {
        add(&mut ideas, "castle", "castles, tucking the king away and bringing the rook toward the center".into());
    }
    let gives_check = after.in_check();
    if gives_check {
        add(&mut ideas, "check", format!("gives check to the {} king", color_name(them)));
    }

    // Tactics created by the moved piece.
    let fork = fork_targets(&after, m.to);
    if fork.len() >= 2 {
        add(&mut ideas, "fork", format!("forks {} and {}", desc(&after, fork[0]), desc(&after, fork[1])));
    }
    if let Some((front, back, is_pin)) = pin_details(&after, m.to) {
        if is_pin {
            add(&mut ideas, "pin", format!("pins {} to {}", desc(&after, front), desc(&after, back)));
        } else {
            add(&mut ideas, "pin", format!("skewers {}, winning {} behind it", desc(&after, front), desc(&after, back)));
        }
    }

    // New attacks by the moved piece.
    let before_attacks = if kind == PAWN { 0 } else { pos.attacks_from(m.from) };
    let new_targets = after.attacks_from(m.to) & after.occ[them] & !before_attacks & !after.pieces(them, KING);
    let mut best_target: Option<(u8, i32, bool)> = None;
    for t in Squares(new_targets) {
        let tk = piece_kind(after.board[t as usize]);
        let loose = is_loose(&after, t);
        if tk == PAWN && !loose {
            continue;
        }
        let score = HUMAN_VALUE[tk as usize] * 10 + if loose { 50 } else { 0 };
        if best_target.map_or(true, |(_, s, _)| score > s) {
            best_target = Some((t, score, loose));
        }
    }
    if let Some((t, _, loose)) = best_target {
        let tk = piece_kind(after.board[t as usize]);
        if loose {
            add(&mut ideas, "attack", format!("attacks {}, threatening to win it", desc(&after, t)));
        } else if HUMAN_VALUE[tk as usize] > HUMAN_VALUE[kind as usize] {
            add(&mut ideas, "attack", format!("attacks {} with a cheaper piece", desc(&after, t)));
        } else {
            add(&mut ideas, "attack", format!("puts pressure on {}", desc(&after, t)));
        }
    }

    // Discovered attacks: another of our pieces sees something new because this one moved.
    let sliders = (after.pieces(us, BISHOP) | after.pieces(us, ROOK) | after.pieces(us, QUEEN)) & !bit(m.to);
    for s in Squares(sliders) {
        let gained = after.attacks_from(s) & !pos.attacks_from(s) & after.occ[them];
        if let Some(t) = Squares(gained).find(|&t| {
            let tk = piece_kind(after.board[t as usize]);
            tk == KING || is_loose(&after, t) || HUMAN_VALUE[tk as usize] > HUMAN_VALUE[piece_kind(after.board[s as usize]) as usize]
        }) {
            let tk = piece_kind(after.board[t as usize]);
            if tk == KING {
                add(&mut ideas, "check", format!("uncovers a check from the {}", kind_name(piece_kind(after.board[s as usize]))));
            } else {
                add(&mut ideas, 
                    "attack",
                    format!("opens a line so the {} attacks {}", kind_name(piece_kind(after.board[s as usize])), desc(&after, t)),
                );
            }
            break;
        }
    }

    // What the move threatens next.
    if !gives_check {
        if let Some(t) = threat_of(searcher, &after) {
            if t.mate {
                add(&mut ideas, "king_attack", format!("threatens checkmate with {}", t.san));
            } else {
                add(&mut ideas, "attack", format!("threatens {} next, winning material", t.san));
            }
        }
    }

    // Defensive ideas.
    if kind != KING && !was_in_check && is_loose(pos, m.from) && !is_loose(&after, m.to) {
        add(&mut ideas, "save_piece", format!("moves the attacked {kname} to safety"));
    }
    let defended_now = after.attacks_from(m.to) & after.occ[us];
    for s in Squares(pos.occ[us] & !bit(m.from) & defended_now) {
        if is_loose(pos, s) && !is_loose(&after, s) {
            add(&mut ideas, "defend", format!("protects the {} on {}", kind_name(piece_kind(pos.board[s as usize])), square_name(s)));
            break;
        }
    }
    if let Some(t) = threat_before {
        if !reply_wins && !was_in_check {
            let what = if t.mate { format!("checkmate with {}", t.san) } else { t.san.clone() };
            add(&mut ideas, "defend", format!("stops {}'s threat of {what}", color_title(them)));
        }
    }

    // Going after the king.
    let ek = after.king_sq(them);
    let zone = king_attacks(ek) | bit(ek);
    let npm: u32 = [KNIGHT, BISHOP, ROOK, QUEEN].iter().map(|&k| (after.pieces(0, k) | after.pieces(1, k)).count_ones()).sum();
    if !matches!(kind, KING | PAWN)
        && (after.attacks_from(m.to) & zone).count_ones() >= 2
        && (pos.attacks_from(m.from) & zone).count_ones() < 2
    {
        add(&mut ideas, "king_attack", format!("aims the {kname} at the {} king", color_name(them)));
    }
    if kind == PAWN && npm >= 8 && pos.fullmove > 8 {
        let rel = if us == WHITE { rank_of(m.to) } else { 7 - rank_of(m.to) };
        if (file_of(m.to) as i32 - file_of(ek) as i32).abs() <= 1 && rel >= 3 && CENTER & bit(m.to) == 0 {
            add(&mut ideas, "king_attack", format!("advances a pawn toward the {} king", color_name(them)));
        }
    }

    // Opening principles.
    let back = if us == WHITE { RANK_1 } else { RANK_8 };
    if matches!(kind, KNIGHT | BISHOP) && bit(m.from) & back != 0 && pos.fullmove <= 15 {
        add(&mut ideas, "develop", format!("develops the {kname}"));
    }
    if kind != KING && !castle_path_clear(pos, us) && castle_path_clear(&after, us) {
        add(&mut ideas, "prepare_castle", "clears the way for castling".into());
    }
    if kind == PAWN && CENTER & bit(m.to) != 0 {
        add(&mut ideas, "center", "claims space in the center".into());
    } else if !matches!(kind, PAWN | KING)
        && (after.attacks_from(m.to) & CENTER).count_ones() >= 2
        && (before_attacks & CENTER).count_ones() < 2
    {
        add(&mut ideas, "center", "controls central squares".into());
    }

    // Piece improvement.
    if kind == ROOK {
        let fm = file_mask(file_of(m.to));
        let own = after.pieces(us, PAWN) & fm;
        let theirs = after.pieces(them, PAWN) & fm;
        let letter = (b'a' + file_of(m.to)) as char;
        let seventh = if us == WHITE { 6 } else { 1 };
        if rank_of(m.to) == seventh {
            add(&mut ideas, "improve", "puts the rook on the seventh rank, where it attacks pawns".into());
        } else if own == 0 && theirs == 0 && file_of(m.from) != file_of(m.to) {
            add(&mut ideas, "improve", format!("puts the rook on the open {letter}-file"));
        } else if own == 0 && file_of(m.from) != file_of(m.to) {
            add(&mut ideas, "improve", format!("puts the rook on the half-open {letter}-file"));
        }
    }
    if kind == PAWN && is_passed(&after, m.to, us) {
        let rel = if us == WHITE { rank_of(m.to) } else { 7 - rank_of(m.to) };
        if rel >= 3 {
            add(&mut ideas, "pawn_push", "pushes the passed pawn toward promotion".into());
        }
    }
    if kind == KING && m.flags & FLAG_CASTLE == 0 && !was_in_check && npm <= 4 {
        add(&mut ideas, "improve", "activates the king, which is a strong piece in the endgame".into());
    }
    if kind == QUEEN && pos.fullmove <= 8 && ideas.is_empty() {
        add(&mut ideas, "improve", "brings the queen out early".into());
    }

    if kind == PAWN && ideas.len() < 3 {
        // Squares the pawn now guards that an enemy knight or bishop wanted to use (like h3 stopping ...Bg4).
        let occ = pos.all();
        let mut wanted = 0u64;
        for s in Squares(pos.pieces(them, KNIGHT)) {
            wanted |= knight_attacks(s);
        }
        for s in Squares(pos.pieces(them, BISHOP)) {
            wanted |= bishop_attacks(s, occ);
        }
        let newly_guarded = pawn_attacks(us, m.to) & !pawn_attacks(us, m.from) & wanted & !occ;
        if let Some(sq) = Squares(newly_guarded).next() {
            add(&mut ideas, "prevent", format!("stops enemy pieces from using the {} square", square_name(sq)));
        }
        let lines = Squares(after.pieces(us, BISHOP))
            .chain(Squares(after.pieces(us, QUEEN)))
            .chain(Squares(after.pieces(us, ROOK)));
        for s in lines {
            let gained = (after.attacks_from(s) & !pos.attacks_from(s)).count_ones();
            if gained >= 2 {
                let k = kind_name(piece_kind(after.board[s as usize]));
                add(&mut ideas, "improve", format!("opens a line for the {k} on {}", square_name(s)));
                break;
            }
        }
    }

    if ideas.is_empty() {
        if kind == PAWN {
            add(&mut ideas, "pawn_push", "pushes a pawn".into());
        } else if kind == KING {
            add(&mut ideas, "king_safety", "moves the king".into());
        } else {
            add(&mut ideas, "improve", format!("repositions the {kname} to {}", square_name(m.to)));
        }
    }
    ideas.truncate(4);
    ideas
}

fn add(ideas: &mut Vec<Idea>, kind: &'static str, text: String) {
    if !ideas.iter().any(|i| i.kind == kind) {
        ideas.push(Idea { kind, text });
    }
}

/// "Nf3 develops the knight, attacks the black pawn on e5 and clears the way for castling."
pub fn ideas_sentence(san: &str, ideas: &[Idea]) -> String {
    format!("{san} {}.", ideas_body(ideas))
}

/// "develops the knight, attacks the black pawn on e5 and clears the way for castling"
pub fn ideas_body(ideas: &[Idea]) -> String {
    let parts: Vec<&str> = ideas.iter().take(3).map(|i| i.text.as_str()).collect();
    match parts.len() {
        0 => "makes a quiet move".to_string(),
        1 => parts[0].to_string(),
        n => format!("{} and {}", parts[..n - 1].join(", "), parts[n - 1]),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::notation::parse_move;

    fn ideas(fen: &str, mv: &str) -> Vec<Idea> {
        let p = Position::from_fen(fen).unwrap();
        let m = parse_move(&p, mv).unwrap();
        let mut s = Searcher::new(4);
        move_ideas(&p, m, None, None, false, &mut s)
    }

    fn kinds(v: &[Idea]) -> Vec<&'static str> {
        v.iter().map(|i| i.kind).collect()
    }

    #[test]
    fn develops_and_attacks() {
        let v = ideas("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "Nf3");
        let k = kinds(&v);
        assert!(k.contains(&"develop"), "{v:?}");
        assert!(k.contains(&"attack"), "{v:?}");
    }

    #[test]
    fn pawn_prophylaxis_and_lines() {
        // h3 stops ...Bg4 pinning the knight.
        let v = ideas("r1bqkbnr/ppp2ppp/2np4/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 4", "h3");
        assert!(v.iter().any(|i| i.kind == "prevent" && i.text.contains("g4")), "{v:?}");
        // e3 opens the f1-a6 diagonal for the bishop.
        let v = ideas("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e3");
        assert!(v.iter().any(|i| i.kind == "improve" && i.text.contains("bishop")), "{v:?}");
    }

    #[test]
    fn castles() {
        let v = ideas("r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", "O-O");
        assert_eq!(v[0].kind, "castle");
    }

    #[test]
    fn knight_fork_detected() {
        let v = ideas("r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1", "Nc7+");
        let k = kinds(&v);
        assert!(k.contains(&"fork") && k.contains(&"check"), "{v:?}");
    }

    #[test]
    fn fork_rejected_when_checker_capturable() {
        // The knight gives check, but it has no defender and Black can just take it with Qxc7.
        let v = ideas("r2qk3/8/8/1N6/8/8/8/4K3 w - - 0 1", "Nc7+");
        assert!(kinds(&v).contains(&"check"), "{v:?}");
        assert!(!kinds(&v).contains(&"fork"), "{v:?}");
        assert!(!v.iter().any(|i| i.text.contains("fork")), "{v:?}");
    }

    #[test]
    fn mate_threat_detected() {
        // Qh5 with Bc4 threatens Qxf7#.
        let v = ideas("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3", "Qh5");
        assert!(v.iter().any(|i| i.kind == "king_attack" && i.text.contains("Qxf7#")), "{v:?}");
    }
}
