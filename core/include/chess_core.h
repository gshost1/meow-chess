#ifndef CHESS_CORE_H
#define CHESS_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*cc_progress_cb)(uint32_t done, uint32_t total, void *ctx);

/// Analyse a PGN game. `username` may be NULL. Returns JSON; free it with cc_free_string.
char *cc_analyze_pgn(const char *pgn, const char *username, uint32_t ms_per_move, cc_progress_cb progress, void *ctx);

/// Legal moves for a FEN position: {"ok":true,"moves":[{uci,san,from,to,fen}]}. Free with cc_free_string.
char *cc_legal_moves(const char *fen);

void cc_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif
