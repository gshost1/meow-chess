//! Standard algebraic notation (SAN) and PGN parsing.

use crate::bitboard::*;
use crate::position::*;

/// SAN for a legal move, including `+` / `#` suffix.
pub fn to_san(pos: &Position, m: Move) -> String {
    let mut s = san_core(pos, m);
    if let Some(after) = pos.try_make(m) {
        if after.in_check() {
            s.push(if after.legal_moves().is_empty() { '#' } else { '+' });
        }
    }
    s
}

fn san_core(pos: &Position, m: Move) -> String {
    let pc = pos.board[m.from as usize];
    let kind = piece_kind(pc);
    if m.flags & FLAG_CASTLE != 0 {
        return if file_of(m.to) == 6 { "O-O".into() } else { "O-O-O".into() };
    }
    let mut s = String::new();
    if kind == PAWN {
        if m.is_capture() {
            s.push((b'a' + file_of(m.from)) as char);
            s.push('x');
        }
        s.push_str(&square_name(m.to));
        if m.is_promo() {
            s.push('=');
            s.push(kind_letter(m.promo));
        }
        return s;
    }
    s.push(kind_letter(kind));
    let others: Vec<Move> = pos
        .legal_moves()
        .into_iter()
        .filter(|o| o.to == m.to && o.from != m.from && pos.board[o.from as usize] == pc)
        .collect();
    if !others.is_empty() {
        let same_file = others.iter().any(|o| file_of(o.from) == file_of(m.from));
        let same_rank = others.iter().any(|o| rank_of(o.from) == rank_of(m.from));
        if !same_file {
            s.push((b'a' + file_of(m.from)) as char);
        } else if !same_rank {
            s.push((b'1' + rank_of(m.from)) as char);
        } else {
            s.push_str(&square_name(m.from));
        }
    }
    if m.is_capture() {
        s.push('x');
    }
    s.push_str(&square_name(m.to));
    s
}

fn normalize(s: &str) -> String {
    s.trim()
        .replace("0-0-0", "O-O-O")
        .replace("0-0", "O-O")
        .chars()
        .filter(|c| !matches!(c, '+' | '#' | '!' | '?' | '='))
        .collect::<String>()
        .replace("e.p.", "")
}

/// Parse a SAN (or UCI) move in the given position.
pub fn parse_move(pos: &Position, text: &str) -> Option<Move> {
    let want = normalize(text);
    let legal = pos.legal_moves();
    for &m in &legal {
        if normalize(&san_core(pos, m)) == want {
            return Some(m);
        }
    }
    // Fallbacks: UCI, or over-specified SAN like "Ngf3" where none was needed.
    for &m in &legal {
        if m.uci() == text.trim() {
            return Some(m);
        }
    }
    for &m in &legal {
        let pc = pos.board[m.from as usize];
        let full = format!(
            "{}{}{}{}",
            if piece_kind(pc) == PAWN { String::new() } else { kind_letter(piece_kind(pc)).to_string() },
            square_name(m.from),
            if m.is_capture() { "x" } else { "" },
            square_name(m.to)
        );
        let promo = if m.is_promo() { kind_letter(m.promo).to_string() } else { String::new() };
        if normalize(&(full.clone() + &promo)) == want || normalize(&(full.replace('x', "") + &promo)) == want {
            return Some(m);
        }

        if piece_kind(pc) != PAWN {
            let piece = kind_letter(piece_kind(pc)).to_string();
            let suffix = format!(
                "{}{}",
                if m.is_capture() { "x" } else { "" },
                square_name(m.to)
            );
            if let Some(disambiguation) = want
                .strip_prefix(&piece)
                .and_then(|rest| rest.strip_suffix(&suffix))
            {
                let from_file = b'a' + file_of(m.from);
                let from_rank = b'1' + rank_of(m.from);
                let matches_from_square = match disambiguation.as_bytes() {
                    [file, rank] => *file == from_file && *rank == from_rank,
                    [file @ b'a'..=b'h'] => *file == from_file,
                    [rank @ b'1'..=b'8'] => *rank == from_rank,
                    _ => false,
                };
                if !disambiguation.is_empty() && matches_from_square {
                    return Some(m);
                }
            }
        }
    }
    None
}

#[derive(Debug, Clone)]
pub struct PgnGame {
    pub headers: Vec<(String, String)>,
    pub start: Position,
    pub moves: Vec<Move>,
}

impl PgnGame {
    pub fn header(&self, key: &str) -> Option<&str> {
        self.headers.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }
}

#[derive(Debug)]
pub struct PgnError(pub String);

impl std::fmt::Display for PgnError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Parse a single PGN game (headers + movetext). Comments, NAGs and variations are skipped.
pub fn parse_pgn(text: &str) -> Result<PgnGame, PgnError> {
    let mut headers = Vec::new();
    let mut movetext = String::new();
    for line in text.lines() {
        let l = line.trim();
        if l.starts_with('[') && l.ends_with(']') && movetext.trim().is_empty() {
            let inner = &l[1..l.len() - 1];
            if let Some(sp) = inner.find(' ') {
                let key = inner[..sp].to_string();
                let val = inner[sp + 1..].trim().trim_matches('"').to_string();
                headers.push((key, val));
            }
        } else {
            movetext.push_str(line);
            movetext.push('\n');
        }
    }

    let start = match headers.iter().find(|(k, _)| k == "FEN") {
        Some((_, fen)) => Position::from_fen(fen).map_err(|e| PgnError(e.to_string()))?,
        None => Position::startpos(),
    };

    // Strip comments and variations.
    let mut clean = String::new();
    let mut depth_paren = 0;
    let mut in_brace = false;
    let mut in_line_comment = false;
    for c in movetext.chars() {
        if in_line_comment {
            if c == '\n' {
                in_line_comment = false;
            }
            continue;
        }
        if in_brace {
            if c == '}' {
                in_brace = false;
            }
            continue;
        }
        match c {
            '{' => in_brace = true,
            ';' => in_line_comment = true,
            '(' => depth_paren += 1,
            ')' => depth_paren -= 1,
            _ if depth_paren > 0 => {}
            _ => clean.push(c),
        }
        if depth_paren < 0 {
            depth_paren = 0;
        }
        if matches!(c, '{' | '(' | ')') {
            clean.push(' ');
        }
    }

    let mut pos = start;
    let mut moves = Vec::new();
    for raw in clean.split_whitespace() {
        // Drop leading move numbers such as "12." or "12..." (possibly glued to the move).
        let tok = if raw.starts_with("0-0") {
            raw
        } else {
            raw.trim_start_matches(|c: char| c.is_ascii_digit()).trim_start_matches('.')
        };
        if tok.is_empty() || tok.starts_with('$') {
            continue;
        }
        if matches!(tok, "1-0" | "0-1" | "1/2-1/2" | "*" | "-0" | "-1" | "/2-1/2") || raw == "1-0" || raw == "0-1" {
            break;
        }
        let m = parse_move(&pos, tok)
            .ok_or_else(|| PgnError(format!("could not read move '{tok}' at move {}", pos.fullmove)))?;
        pos = pos.make(m);
        moves.push(m);
    }
    Ok(PgnGame { headers, start, moves })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn san_roundtrip() {
        let pgn = r#"[Event "Live Chess"]
[White "a"]
[Black "b"]

1. e4 {[%clk 0:09:58]} 1... e5 2. Nf3 Nc6 3. Bb5 a6 (3... Nf6 4. O-O) 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 1-0"#;
        let g = parse_pgn(pgn).unwrap();
        assert_eq!(g.moves.len(), 20);
        let mut pos = g.start;
        let mut sans = vec![];
        for &m in &g.moves {
            sans.push(to_san(&pos, m));
            pos = pos.make(m);
        }
        assert_eq!(sans[18], "d4");
        assert_eq!(sans[19], "Nbd7");
        assert_eq!(sans[8], "O-O");
    }

    #[test]
    fn accepts_file_and_rank_move_disambiguation() {
        let mut pos = Position::startpos();
        for text in ["e4", "e5"] {
            let m = parse_move(&pos, text).unwrap();
            pos = pos.make(m);
        }

        for text in ["Ngf3", "N1f3", "Ng1f3", "Nf3"] {
            assert_eq!(
                parse_move(&pos, text).map(|m| m.uci()),
                Some("g1f3".to_string()),
                "{text} should resolve to g1f3"
            );
        }
        assert!(parse_move(&pos, "Nbf3").is_none());
    }

    #[test]
    fn mate_suffix() {
        let g = parse_pgn("1. f3 e5 2. g4 Qh4# 0-1").unwrap();
        let mut pos = g.start;
        for &m in &g.moves[..3] {
            pos = pos.make(m);
        }
        assert_eq!(to_san(&pos, g.moves[3]), "Qh4#");
        assert!(pos.make(g.moves[3]).is_checkmate());
    }
}
