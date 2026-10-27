# Database changes: migration path, backup, way back

Every change to a database's schema or stored data shape (table, column, index, constraint,
key, or a data migration) gets a migration path, a backup before it runs, and a way back.
This repository deploys infrastructure and has no database of its own; the steps apply to
any database a later change adds. `scripts/db/sqlite_backup.py` does the backup mechanics for
SQLite; another database or tool follows the same steps with its own commands.

## The steps

| Step | What | SQLite |
|---|---|---|
| 1. Write | A migration in the project's mechanism (EF Core, Alembic, a versioned SQL script), never a hand edit, with its `Down` or rollback script. Additive first: add, copy, switch the code, drop later. | |
| 2. Review | The SQL it will run. | |
| 3. Back up | A checked, WAL-safe copy named `<db>_Backup_<yyyyMMdd_HHmmss>_before-<what>.db`. | `sqlite_backup.py backup` |
| 4. Try | Migrate a copy first; compare row counts with the backup. | `sqlite_backup.py copy`, then `compare` |
| 5. Apply | The real database, after confirmation; checked after. | `sqlite_backup.py verify` |
| 6. On failure | The backup is restored and checked; nothing is left half-migrated. | `sqlite_backup.py restore` |
| 7. Way back | Migrate down, or restore the backup. | `sqlite_backup.py restore` |

Before step 3, check that no other worktree, branch or service uses the same database file:
one branch's schema can break another's.

Row counts catch lost rows and tables, not a dropped or narrowed column: read the migration
and its rollback (and the review SQL) for those, and keep the backup until the change has
been used for a while.

## Commands (PowerShell, repository root)

```powershell
# 3. Back up (prints BACKUP_PATH=...)
.venv\Scripts\python scripts/db/sqlite_backup.py backup data/app.db --reason card-history

# 4. Try: migrate a working copy, then compare it with the backup
.venv\Scripts\python scripts/db/sqlite_backup.py copy data/app.db artifacts/migrations/app.db
#    (run the migration against artifacts/migrations/app.db)
.venv\Scripts\python scripts/db/sqlite_backup.py compare data/app_Backup_20261026_101500_before-card-history.db artifacts/migrations/app.db

# 6-7. Way back: restore the backup (makes a safety backup first)
.venv\Scripts\python scripts/db/sqlite_backup.py restore data/app_Backup_20261026_101500_before-card-history.db data/app.db
```

Trial copies and review SQL go to `artifacts/migrations/` (gitignored).

## sqlite_backup.py

| Command | Does |
|---|---|
| `backup <db> --reason <what>` | Backup next to the database (or `--dest`), integrity check, row counts equal to the source. Prints `BACKUP_PATH=...`. |
| `copy <db> <target>` | Checked working copy (`--force` replaces the target). |
| `verify <db>` | `PRAGMA integrity_check` and row counts per table. |
| `compare <before> <after>` | Row counts per table; exit 1 when a table lost rows or vanished. |
| `restore <backup> <db>` | Safety backup of `<db>`, then the restore, checked; keeps the database's journal mode (WAL). |

It uses SQLite's online backup API: a plain file copy of a database in WAL mode misses the
changes still in the `-wal` file.

## In the PR

A `## Database` section: the migration's name, what it changes, additive or destructive, the
backup command, the rollback steps, and how it was tested (a copy of the real database, an
empty database, an older backup restored through the app if it has a restore).
