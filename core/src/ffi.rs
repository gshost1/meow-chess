//! C interface used by the iOS app. Every result is a JSON string the caller frees with `cc_free_string`.

use crate::analysis::analyze_pgn;
use crate::bitboard::square_name;
use crate::notation::to_san;
use crate::position::Position;
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

/// # Safety
/// `s` must come from one of this library's functions and be freed only once.
#[no_mangle]
pub unsafe extern "C" fn cc_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
