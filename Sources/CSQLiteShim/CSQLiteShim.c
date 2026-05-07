#include "CSQLiteShim.h"

int atoll_sqlite3_db_config_int(sqlite3 *db, int op, int value) {
    return sqlite3_db_config(db, op, value, (int *)0);
}
