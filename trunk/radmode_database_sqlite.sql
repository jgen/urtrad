-- ------------------------------------------------------
-- urtRAD Database Creation
-- Sept. 2009
-- ------------------------------------------------------

--CREATE SCHEMA IF NOT EXISTS `urt_rad` DEFAULT CHARACTER SET latin5;
--USE `urt_rad`;

-- -----------------------------------------------------
-- Table `urt_rad`.`weapons`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `weapons` (
  `weapon_id` INTEGER PRIMARY KEY ,
  `internal_name` VARCHAR(45) NOT NULL ,
  `weapon_name` VARCHAR(64) NOT NULL ,
  `kills` BIGINT UNSIGNED NOT NULL );


-- -----------------------------------------------------
-- Table `urt_rad`.`gametypes`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `gametypes` (
  `game_id` INTEGER PRIMARY KEY ,
  `game_name` VARCHAR(45) NOT NULL ,
  `total_rounds` BIGINT UNSIGNED NOT NULL ,
  `total_time` BIGINT UNSIGNED NOT NULL ,
  `longest_round` BIGINT UNSIGNED NOT NULL ,
  `shortest_round` BIGINT UNSIGNED NOT NULL ,
  `avg_round` BIGINT UNSIGNED NOT NULL );


-- -----------------------------------------------------
-- Table `urt_rad`.`maps`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `maps` (
  `map_id` INTEGER PRIMARY KEY ,
  `map_name` VARCHAR(144) NOT NULL ,
  `times_played` INTEGER UNSIGNED NULL ,
  `duration` BIGINT UNSIGNED NOT NULL DEFAULT 0 );


-- -----------------------------------------------------
-- Table `urt_rad`.`current_players`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `current_players` (
  `slot_num` INTEGER PRIMARY KEY ,
  `score` SMALLINT NOT NULL ,
  `ping` SMALLINT UNSIGNED NOT NULL ,
  `name` CHAR(32) NOT NULL ,
  `ip` INTEGER UNSIGNED NOT NULL ,
  `qport` SMALLINT UNSIGNED NOT NULL ,
  `rate` SMALLINT UNSIGNED NOT NULL );


-- -----------------------------------------------------
-- Table `urt_rad`.`status`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `status` (
  `backend_status` TINYINT NULL DEFAULT 0 ,
  `client_request` TINYINT UNSIGNED NULL DEFAULT 0 ,
  `log_lines_processed` BIGINT UNSIGNED NULL DEFAULT 0 ,
  `log_bytes_processed` BIGINT UNSIGNED NULL DEFAULT 0 ,
  `log_last_check` INTEGER UNSIGNED NULL DEFAULT 0 ,
  `last_update` DATETIME NULL );


-- -----------------------------------------------------
-- Table `urt_rad`.`players`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `players` (
  `player_id` INTEGER PRIMARY KEY ,
  `name` VARCHAR(32) NOT NULL ,
  `duration` BIGINT UNSIGNED NOT NULL DEFAULT 0 ,
  `creation` DATETIME NULL );


-- -----------------------------------------------------
-- Table `urt_rad`.`ips`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `ips` (
  `ip` INTEGER UNSIGNED NOT NULL ,
  `ip_text` CHAR(15) NOT NULL ,
  `player_id` INTEGER UNSIGNED NULL ,
  `creation` DATETIME NULL );

CREATE INDEX IF NOT EXISTS `ips_ip_index` ON `ips` (`ip` ASC);
CREATE INDEX IF NOT EXISTS `ips_pid_index` ON `ips` (`player_id` ASC);


-- -----------------------------------------------------
-- Table `urt_rad`.`guids`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `guids` (
  `guid_id` INTEGER PRIMARY KEY ,
  `guid` CHAR(32) NOT NULL ,
  `player_id` INTEGER UNSIGNED NULL );

CREATE INDEX IF NOT EXISTS `guid_pid_index` ON `guids` (`player_id` ASC);

-- -----------------------------------------------------
-- Table `urt_rad`.`rcon_log`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_log` (
  `log_id` INTEGER PRIMARY KEY ,
  `datetime` DATETIME NOT NULL ,
  `player_id` INTEGER UNSIGNED NOT NULL ,
  `ip` INTEGER UNSIGNED NULL ,
  `slot` TINYINT UNSIGNED NULL ,
  `action` TINYINT UNSIGNED NULL );

CREATE INDEX IF NOT EXISTS `rconlog_pid_index` ON `rcon_log` (`player_id` ASC);
CREATE INDEX IF NOT EXISTS `rconlog_ip_index` ON `rcon_log` (`ip` ASC);


-- -----------------------------------------------------
-- Table `urt_rad`.`servers`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `servers` (
  `server_id` INTEGER PRIMARY KEY ,
  `status` TINYINT NULL DEFAULT 0 ,
  `ip` INTEGER UNSIGNED NULL ,
  `port` MEDIUMINT UNSIGNED NULL DEFAULT 27960 ,
  `name` VARCHAR(64) NULL ,
  `current_map` VARCHAR(45) NULL ,
  `timeouts` INTEGER UNSIGNED NULL DEFAULT 0 ,
  `timeout_last` DATETIME NULL ,
  `timeout_delay` INTEGER UNSIGNED NULL DEFAULT 5 ,
  `timeout_wait_delay` INTEGER UNSIGNED NULL DEFAULT 10 ,
  `rcon_pw` VARCHAR(32) NULL ,
  `svars` TEXT(1024) NULL );

