//! C interface used by the iOS app. Every result is a JSON string the caller frees with `cc_free_string`.

use crate::analysis::analyze_pgn;
use crate::bitboard::square_name;
use crate::notation::to_san;
use crate::position::{Position, PAWN};
use crate::search::{Limits, Searcher};
use std::ffi::{c_char, c_void, CStr, CString};

pub type ProgressCallback = Option<extern "C" fn(done: u32, total: u32, ctx: *mut c_void)>;

fn into_c(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":\"nul byte\"}").unwrap()).into_raw()
}

unsafe fn read(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        Some(CStr::from_ptr(p).to_string_lossy().into_owned())
    }
}

/// Analyse a PGN. `username` may be null. Returns `{"ok":true,"analysis":{...}}` or `{"ok":false,"error":"..."}`.
///
/// # Safety
/// `pgn` must be a valid NUL-terminated string; `username` must be null or NUL-terminated.
#[no_mangle]
pub unsafe extern "C" fn cc_analyze_pgn(
    pgn: *const c_char,
    username: *const c_char,
    ms_per_move: u32,
    progress: ProgressCallback,
    ctx: *mut c_void,
) -> *mut c_char {
    let Some(pgn) = read(pgn) else {
        return into_c("{\"ok\":false,\"error\":\"no PGN\"}".into());
    };
    let user = read(username);
    let ctx_addr = ctx as usize;
    let result = analyze_pgn(&pgn, user.as_deref(), ms_per_move.max(10) as u64, |done, total| {
        if let Some(cb) = progress {
            cb(done as u32, total as u32, ctx_addr as *mut c_void);
        }
    });
    let json = match result {
        Ok(a) => serde_json::json!({ "ok": true, "analysis": a }),
        Err(e) => serde_json::json!({ "ok": false, "error": e }),
    };
    into_c(json.to_string())
}

/// Legal moves in a position: `{"ok":true,"moves":[{"uci","san","from","to","fen"}]}`.
///
/// # Safety
/// `fen` must be a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn cc_legal_moves(fen: *const c_char) -> *mut c_char {
    let Some(fen) = read(fen) else {
        return into_c("{\"ok\":false,\"error\":\"no FEN\"}".into());
    };
    let json = match Position::from_fen(&fen) {
        Ok(pos) => {
            let moves: Vec<_> = pos
                .legal_moves()
                .into_iter()
                .map(|m| {
                    serde_json::json!({
                        "uci": m.uci(),
                        "san": to_san(&pos, m),
                        "from": square_name(m.from),
                        "to": square_name(m.to),
                        "fen": pos.make(m).to_fen(),
                    })
                })
                .collect();
            serde_json::json!({ "ok": true, "moves": moves })
        }
        Err(e) => serde_json::json!({ "ok": false, "error": e.to_string() }),
    };
    into_c(json.to_string())
}

/// Best reply for a puzzle attempt. Terminal positions return `move: null`.
/// # Safety
/// `fen` must be null or a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn cc_best_move(fen: *const c_char, ms: u32) -> *mut c_char {
    let Some(fen) = read(fen) else {
        return into_c(serde_json::json!({"ok": false, "error": "no FEN"}).to_string());
    };
    let json = match Position::from_fen(&fen) {
        Ok(pos) if pos.is_attacked(pos.king_sq(pos.side ^ 1), pos.side)
            || (pos.pieces(0, PAWN) | pos.pieces(1, PAWN)) & 0xff00_0000_0000_00ff != 0
            || pos.occ.iter().any(|pieces| pieces.count_ones() > 16) => {
            serde_json::json!({"ok": false, "error": "not a legal game position"})
        }
        Ok(pos) => {
            let mut searcher = Searcher::new(8);
            let result = searcher.search(&pos, &[], Limits {
                time_ms: Some(ms.clamp(10, 2_000) as u64), ..Limits::default()
            });
            if result.best.is_null() {
                serde_json::json!({"ok": true, "move": null})
            } else {
                let m = result.best;
                serde_json::json!({"ok": true, "move": {
                    "uci": m.uci(), "san": to_san(&pos, m), "fen": pos.make(m).to_fen()
                }})
            }
        }
        Err(e) => serde_json::json!({"ok": false, "error": e.to_string()}),
    };
    into_c(json.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn reply(fen: Option<&str>) -> serde_json::Value {
        let input = fen.map(|f| CString::new(f).unwrap());
        let raw = cc_best_move(input.as_ref().map_or(std::ptr::null(), |f| f.as_ptr()), 40);
        let value = serde_json::from_str(CStr::from_ptr(raw).to_str().unwrap()).unwrap();
        cc_free_string(raw);
        value
    }

    #[test]
    fn best_reply_is_legal_and_applied() {
        unsafe {
            let fen = "6k1/8/8/3q4/8/8/8/3R2K1 b - - 0 1";
            let value = reply(Some(fen));
            assert_eq!(value["ok"], true);
            let pos = Position::from_fen(fen).unwrap();
            let m = pos.legal_moves().into_iter().find(|m| m.uci() == value["move"]["uci"]).unwrap();
            assert_eq!(value["move"]["san"], to_san(&pos, m));
            assert_eq!(value["move"]["fen"], pos.make(m).to_fen());
        }
    }

    #[test]
    fn best_reply_handles_invalid_and_terminal_positions() {
        unsafe {
            for fen in [None, Some("bad"), Some("8/8/8/8/8/8/8/8 w - - 0 1"),
                Some("6k1/8/8/8/8/8/4q3/4K3 b - - 0 1")] {
                assert_eq!(reply(fen)["ok"], false);
            }
            for fen in ["7k/6Q1/6K1/8/8/8/8/8 b - - 0 1", "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"] {
                let value = reply(Some(fen));
                assert_eq!(value["ok"], true);
                assert!(value["move"].is_null());
            }
        }
    }
}

/// # Safety
/// `s` must come from one of this library's functions and be freed only once.
#[no_mangle]
pub unsafe extern "C" fn cc_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
