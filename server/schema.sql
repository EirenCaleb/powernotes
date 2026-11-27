-- PowerNotes database schema. Safe to run more than once.
-- Run in hPanel > Databases > phpMyAdmin on the PowerNotes database.

CREATE TABLE IF NOT EXISTS pn_users (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pn_tokens (
  token_hash CHAR(64) PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at DATETIME NULL,
  INDEX idx_tokens_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pn_notes (
  user_id INT UNSIGNED NOT NULL,
  uuid CHAR(36) NOT NULL,
  title MEDIUMTEXT NOT NULL,
  body MEDIUMTEXT NOT NULL,
  folder_uuid CHAR(36) NULL,
  tags VARCHAR(1000) NOT NULL DEFAULT '',
  pinned TINYINT(1) NOT NULL DEFAULT 0,
  private TINYINT(1) NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  deleted TINYINT(1) NOT NULL DEFAULT 0,
  server_ts BIGINT NOT NULL,
  PRIMARY KEY (user_id, uuid),
  INDEX idx_notes_sync (user_id, server_ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pn_folders (
  user_id INT UNSIGNED NOT NULL,
  uuid CHAR(36) NOT NULL,
  name VARCHAR(255) NOT NULL,
  updated_at BIGINT NOT NULL,
  deleted TINYINT(1) NOT NULL DEFAULT 0,
  server_ts BIGINT NOT NULL,
  PRIMARY KEY (user_id, uuid),
  INDEX idx_folders_sync (user_id, server_ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pn_shares (
  token CHAR(32) PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  note_uuid CHAR(36) NOT NULL,
  title VARCHAR(500) NOT NULL,
  body MEDIUMTEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_share_note (user_id, note_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
