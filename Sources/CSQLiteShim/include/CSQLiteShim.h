#ifndef ATOLL_CSQLITE_SHIM_H
#define ATOLL_CSQLITE_SHIM_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Wraps `sqlite3_db_config(db, op, int_value, NULL)` because Swift cannot
/// import variadic C functions. Used by AtollCore to apply SQLite hardening
/// flags (DEFENSIVE, TRUSTED_SCHEMA=0, ENABLE_LOAD_EXTENSION=0, DQS_DDL=0,
/// DQS_DML=0) on read-only opens of third-party databases (e.g. Warp's
/// per-user state).
int atoll_sqlite3_db_config_int(sqlite3 *db, int op, int value);

#ifdef __cplusplus
}
#endif

#endif
