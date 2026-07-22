import GRDB

enum LibraryMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v001_initial") { db in
            try db.execute(sql: Schema.v001)
        }
        migrator.registerMigration("v002_download_queue_position") { db in
            try db.execute(sql: """
                ALTER TABLE download_jobs ADD COLUMN queue_position INTEGER;
                UPDATE download_jobs
                SET queue_position = rowid
                WHERE state = 'queued' AND queue_position IS NULL;
                CREATE INDEX download_jobs_fifo
                    ON download_jobs(device_id, state, queue_position);
                """)
        }
        return migrator
    }
}

private enum Schema {
    static let v001 = """
        CREATE TABLE workspaces (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER
        );
        CREATE INDEX workspaces_active_kind
            ON workspaces(kind, modified_at DESC) WHERE deleted_at IS NULL;

        CREATE TABLE media_items (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            source_url TEXT NOT NULL,
            canonical_url TEXT,
            canonicalization_version INTEGER NOT NULL DEFAULT 1,
            source_type TEXT NOT NULL,
            source_media_id TEXT,
            title TEXT,
            creator TEXT,
            description TEXT,
            duration_seconds REAL,
            thumbnail_url TEXT,
            metadata_status TEXT NOT NULL,
            metadata_error_code TEXT,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER
        );
        CREATE INDEX media_items_workspace_added
            ON media_items(workspace_id, created_at DESC) WHERE deleted_at IS NULL;
        CREATE INDEX media_items_source_identity
            ON media_items(workspace_id, source_type, source_media_id)
            WHERE deleted_at IS NULL AND source_media_id IS NOT NULL;
        CREATE INDEX media_items_canonical_url
            ON media_items(workspace_id, canonical_url)
            WHERE deleted_at IS NULL AND canonical_url IS NOT NULL;
        CREATE INDEX media_items_modified
            ON media_items(workspace_id, modified_at, id);

        CREATE TABLE collections (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            sort_order REAL NOT NULL DEFAULT 0,
            color_token TEXT,
            icon_name TEXT,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER
        );
        CREATE INDEX collections_workspace_order
            ON collections(workspace_id, sort_order, name) WHERE deleted_at IS NULL;

        CREATE TABLE collection_memberships (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE RESTRICT,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            sort_order REAL,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER,
            UNIQUE (workspace_id, collection_id, media_item_id)
        );
        CREATE INDEX collection_memberships_collection
            ON collection_memberships(collection_id, sort_order, created_at)
            WHERE deleted_at IS NULL;
        CREATE INDEX collection_memberships_media
            ON collection_memberships(media_item_id) WHERE deleted_at IS NULL;

        CREATE TABLE tags (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            name TEXT NOT NULL,
            normalized_name TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER
        );
        CREATE INDEX tags_workspace_name
            ON tags(workspace_id, normalized_name) WHERE deleted_at IS NULL;

        CREATE TABLE media_item_tags (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER,
            UNIQUE (workspace_id, media_item_id, tag_id)
        );
        CREATE INDEX media_item_tags_media
            ON media_item_tags(media_item_id) WHERE deleted_at IS NULL;
        CREATE INDEX media_item_tags_tag
            ON media_item_tags(tag_id) WHERE deleted_at IS NULL;

        CREATE TABLE favorites (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER,
            UNIQUE (workspace_id, media_item_id)
        );
        CREATE INDEX favorites_workspace_added
            ON favorites(workspace_id, created_at DESC) WHERE deleted_at IS NULL;

        CREATE TABLE workspace_settings (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            key TEXT NOT NULL,
            value_json TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            revision INTEGER NOT NULL CHECK (revision >= 1),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            modified_by_device TEXT NOT NULL,
            deleted_at INTEGER,
            UNIQUE (workspace_id, key)
        );

        CREATE TABLE devices (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            platform TEXT NOT NULL,
            app_version TEXT,
            created_at INTEGER NOT NULL,
            last_seen_at INTEGER NOT NULL,
            is_current INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1))
        );
        CREATE UNIQUE INDEX devices_one_current
            ON devices(is_current) WHERE is_current = 1;

        CREATE TABLE local_assets (
            id TEXT PRIMARY KEY NOT NULL,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
            file_bookmark BLOB,
            last_known_path TEXT NOT NULL,
            file_size_bytes INTEGER,
            content_type TEXT,
            container TEXT,
            checksum_sha256 TEXT,
            status TEXT NOT NULL,
            downloaded_at INTEGER NOT NULL,
            last_verified_at INTEGER,
            removed_at INTEGER,
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
            CHECK (
                status <> 'available'
                OR (
                    file_bookmark IS NOT NULL
                    AND length(file_bookmark) > 0
                    AND last_verified_at IS NOT NULL
                )
            )
        );
        CREATE INDEX local_assets_media_device
            ON local_assets(media_item_id, device_id, downloaded_at DESC);
        CREATE INDEX local_assets_status
            ON local_assets(device_id, status, last_verified_at);

        CREATE TABLE download_jobs (
            id TEXT PRIMARY KEY NOT NULL,
            media_item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE RESTRICT,
            device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
            parent_job_id TEXT REFERENCES download_jobs(id) ON DELETE RESTRICT,
            backend_id TEXT,
            engine_version TEXT,
            state TEXT NOT NULL,
            media_kind TEXT NOT NULL,
            container TEXT,
            quality_preset TEXT NOT NULL,
            request_json TEXT NOT NULL,
            destination_bookmark BLOB,
            destination_path TEXT NOT NULL,
            progress_fraction REAL,
            downloaded_bytes INTEGER,
            total_bytes INTEGER,
            speed_bytes_per_second REAL,
            estimated_remaining_sec REAL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            retry_after INTEGER,
            error_category TEXT,
            error_summary TEXT,
            technical_detail TEXT,
            backend_resume_data BLOB,
            local_asset_id TEXT REFERENCES local_assets(id) ON DELETE SET NULL,
            created_at INTEGER NOT NULL,
            queued_at INTEGER,
            started_at INTEGER,
            completed_at INTEGER,
            modified_at INTEGER NOT NULL,
            CHECK (state <> 'completed' OR local_asset_id IS NOT NULL),
            CHECK (progress_fraction IS NULL OR (progress_fraction >= 0 AND progress_fraction <= 1)),
            CHECK (downloaded_bytes IS NULL OR downloaded_bytes >= 0),
            CHECK (total_bytes IS NULL OR total_bytes >= 0),
            CHECK (attempt_count >= 0)
        );
        CREATE INDEX download_jobs_queue
            ON download_jobs(device_id, state, queued_at, created_at);
        CREATE INDEX download_jobs_media
            ON download_jobs(media_item_id, created_at DESC);
        CREATE TRIGGER download_jobs_completed_asset_insert
        BEFORE INSERT ON download_jobs
        WHEN NEW.state = 'completed' AND NOT EXISTS (
            SELECT 1 FROM local_assets a
            WHERE a.id = NEW.local_asset_id
              AND a.media_item_id = NEW.media_item_id
              AND a.device_id = NEW.device_id
              AND a.status = 'available'
        )
        BEGIN
            SELECT RAISE(ABORT, 'completed download requires an available local asset');
        END;
        CREATE TRIGGER download_jobs_completed_asset_update
        BEFORE UPDATE OF state, local_asset_id ON download_jobs
        WHEN NEW.state = 'completed' AND NOT EXISTS (
            SELECT 1 FROM local_assets a
            WHERE a.id = NEW.local_asset_id
              AND a.media_item_id = NEW.media_item_id
              AND a.device_id = NEW.device_id
              AND a.status = 'available'
        )
        BEGIN
            SELECT RAISE(ABORT, 'completed download requires an available local asset');
        END;

        CREATE TABLE change_journal (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            change_id TEXT NOT NULL UNIQUE,
            workspace_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            entity_revision INTEGER NOT NULL,
            operation TEXT NOT NULL,
            origin TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX change_journal_entity
            ON change_journal(workspace_id, entity_type, entity_id, sequence DESC);

        CREATE TABLE sync_endpoints (
            id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
            provider_kind TEXT NOT NULL,
            account_scope TEXT,
            enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL
        );

        CREATE TABLE sync_outbox (
            endpoint_id TEXT NOT NULL REFERENCES sync_endpoints(id) ON DELETE CASCADE,
            change_id TEXT NOT NULL REFERENCES change_journal(change_id) ON DELETE CASCADE,
            state TEXT NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER,
            last_error_code TEXT,
            acknowledged_at INTEGER,
            PRIMARY KEY (endpoint_id, change_id)
        );
        CREATE INDEX sync_outbox_pending
            ON sync_outbox(endpoint_id, state, next_attempt_at);

        CREATE TABLE sync_cursors (
            endpoint_id TEXT NOT NULL REFERENCES sync_endpoints(id) ON DELETE CASCADE,
            scope TEXT NOT NULL,
            cursor_data BLOB,
            last_success_at INTEGER,
            last_full_scan_at INTEGER,
            PRIMARY KEY (endpoint_id, scope)
        );

        CREATE TABLE sync_inbox (
            endpoint_id TEXT NOT NULL REFERENCES sync_endpoints(id) ON DELETE CASCADE,
            delivery_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            envelope_json TEXT NOT NULL,
            payload_digest TEXT NOT NULL,
            state TEXT NOT NULL,
            failure_code TEXT,
            received_at INTEGER NOT NULL,
            applied_at INTEGER,
            PRIMARY KEY (endpoint_id, delivery_id)
        );
        CREATE INDEX sync_inbox_work
            ON sync_inbox(endpoint_id, state, received_at);
        CREATE INDEX sync_inbox_entity
            ON sync_inbox(endpoint_id, entity_type, entity_id, received_at DESC);

        CREATE TABLE sync_record_state (
            endpoint_id TEXT NOT NULL REFERENCES sync_endpoints(id) ON DELETE CASCADE,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            provider_metadata BLOB NOT NULL,
            last_seen_at INTEGER NOT NULL,
            PRIMARY KEY (endpoint_id, entity_type, entity_id)
        );

        CREATE TABLE engine_installations (
            version TEXT PRIMARY KEY NOT NULL,
            manifest_json TEXT NOT NULL,
            install_path TEXT NOT NULL,
            state TEXT NOT NULL,
            installed_at INTEGER NOT NULL,
            verified_at INTEGER,
            last_health_at INTEGER,
            failure_summary TEXT
        );
        CREATE UNIQUE INDEX engine_one_active
            ON engine_installations(state) WHERE state = 'active';

        CREATE TABLE migration_state (
            key TEXT PRIMARY KEY NOT NULL,
            value_json TEXT NOT NULL,
            modified_at INTEGER NOT NULL
        );

        CREATE VIRTUAL TABLE media_search USING fts5(
            media_item_id UNINDEXED,
            workspace_id UNINDEXED,
            title,
            creator,
            source_url,
            description,
            collection_names,
            tag_names,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
}
