use chess_core::analysis::analyze_pgn;
use chess_core::notation::to_san;
use chess_core::position::Position;
use chess_core::search::{Limits, Searcher};
use std::time::Instant;

fn usage() -> ! {
    eprintln!(
        "usage:\n  chess-coach perft <depth> [fen]\n  chess-coach bestmove <ms> [fen]\n  chess-coach review <file.pgn> [username] [ms-per-move] [--json]"
    );
    std::process::exit(2)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("perft") => {
            let depth: u32 = args.get(1).and_then(|d| d.parse().ok()).unwrap_or_else(|| usage());
            let pos = args.get(2).map(|f| Position::from_fen(f).expect("bad fen")).unwrap_or_else(Position::startpos);
            let t = Instant::now();
            let n = pos.perft(depth);
            let secs = t.elapsed().as_secs_f64();
            println!("perft({depth}) = {n}  in {secs:.2}s  ({:.1} M moves/s)", n as f64 / secs / 1e6);
        }
        Some("bestmove") => {
            let ms: u64 = args.get(1).and_then(|d| d.parse().ok()).unwrap_or(1000);
            let pos = args.get(2).map(|f| Position::from_fen(f).expect("bad fen")).unwrap_or_else(Position::startpos);
            let mut s = Searcher::new(64);
            let t = Instant::now();
            let r = s.search(&pos, &[], Limits { time_ms: Some(ms), ..Default::default() });
            let secs = t.elapsed().as_secs_f64();
            println!(
                "best {} score {} depth {} nodes {} ({:.2} M nodes/s)",
                to_san(&pos, r.best),
                r.score,
                r.depth,
                r.nodes,
                r.nodes as f64 / secs / 1e6
            );
        }
        Some("review") => {
            let path = args.get(1).unwrap_or_else(|| usage());
            let user = args.get(2).filter(|a| !a.starts_with("--")).map(String::as_str);
            let ms: u64 = args.get(3).and_then(|d| d.parse().ok()).unwrap_or(150);
            let json = args.iter().any(|a| a == "--json");
            let pgn = std::fs::read_to_string(path).expect("read pgn");
            let t = Instant::now();
            let a = analyze_pgn(&pgn, user, ms, |_, _| {}).unwrap_or_else(|e| {
                eprintln!("error: {e}");
                std::process::exit(1)
            });
            if json {
                println!("{}", serde_json::to_string_pretty(&a).unwrap());
                return;
            }
            println!(
                "{} ({}) vs {} ({})  {}   [{:.1}s, avg depth {}]",
                a.white,
                a.white_elo.clone().unwrap_or_default(),
                a.black,
                a.black_elo.clone().unwrap_or_default(),
                a.result,
                t.elapsed().as_secs_f64(),
                a.depth_reached
            );
            println!(
                "Accuracy  White {:.1}%  Black {:.1}%",
                a.white_summary.accuracy, a.black_summary.accuracy
            );
            for m in &a.moves {
                let num = if m.color == "white" { format!("{}.", m.move_number) } else { format!("{}...", m.move_number) };
                let marker = match m.class {
                    "blunder" => "??",
                    "mistake" => "? ",
                    "inaccuracy" => "?!",
                    _ => "  ",
                };
                if matches!(m.class, "blunder" | "mistake" | "inaccuracy") || m.headline == "Checkmate!" {
                    println!("{num:>6} {:<8}{marker} {}", m.san, m.headline);
                    println!("{:>17}{}", "", m.explanation);
                    println!("{:>17}tags: {:?}", "", m.tags);
                } else {
                    println!("{num:>6} {:<8}   {}", m.san, m.class);
                }
            }
        }
        _ => usage(),
    }
}
