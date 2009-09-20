-- ------------------------------------------------------
-- urtRAD Database Creation
-- Sept. 2009
-- ------------------------------------------------------

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='TRADITIONAL';

CREATE SCHEMA IF NOT EXISTS `rcon_db` DEFAULT CHARACTER SET latin5;
USE `rcon_db`;

-- -----------------------------------------------------
-- Table `rcon_db`.`weapons`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`weapons` (
  `weapon_id` TINYINT UNSIGNED NOT NULL ,
  `internal_name` VARCHAR(45) NOT NULL ,
  `weapon_name` VARCHAR(64) NOT NULL ,
  `kills` BIGINT UNSIGNED NOT NULL ,
  PRIMARY KEY (`weapon_id`) )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`gametypes`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`gametypes` (
  `game_id` TINYINT UNSIGNED NOT NULL ,
  `game_name` VARCHAR(45) NOT NULL ,
  `total_rounds` BIGINT UNSIGNED NOT NULL ,
  `total_time` BIGINT UNSIGNED NOT NULL ,
  `longest_round` BIGINT UNSIGNED NOT NULL ,
  `shortest_round` BIGINT UNSIGNED NOT NULL ,
  `avg_round` BIGINT UNSIGNED NOT NULL ,
  PRIMARY KEY (`game_id`) )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`maps`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`maps` (
  `map_id` INT UNSIGNED NOT NULL AUTO_INCREMENT ,
  `map_name` VARCHAR(144) NOT NULL ,
  `times_played` INT UNSIGNED NULL ,
  `duration` BIGINT UNSIGNED NOT NULL DEFAULT 0 ,
  PRIMARY KEY (`map_id`) )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`current_players`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`current_players` (
  `slot_num` TINYINT UNSIGNED NOT NULL ,
  `score` SMALLINT NOT NULL ,
  `ping` SMALLINT UNSIGNED NOT NULL ,
  `name` CHAR(32) NOT NULL ,
  `ip` INT UNSIGNED NOT NULL ,
  `qport` SMALLINT UNSIGNED NOT NULL ,
  `rate` SMALLINT UNSIGNED NOT NULL ,
  PRIMARY KEY (`slot_num`) )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`status`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`status` (
  `backend_status` TINYINT NULL DEFAULT 0 ,
  `client_request` TINYINT UNSIGNED NULL DEFAULT 0 ,
  `log_lines_processed` BIGINT UNSIGNED NULL DEFAULT 0 ,
  `log_bytes_processed` BIGINT UNSIGNED NULL DEFAULT 0 ,
  `log_last_check` INT UNSIGNED NULL DEFAULT 0 ,
  `last_update` DATETIME NULL )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`players`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`players` (
  `player_id` INT UNSIGNED NOT NULL AUTO_INCREMENT ,
  `name` VARCHAR(32) NOT NULL ,
  `duration` BIGINT UNSIGNED NOT NULL DEFAULT 0 ,
  `creation` DATETIME NOT NULL DEFAULT NOW(),
  PRIMARY KEY (`player_id`) )
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`ips`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`ips` (
  `ip` INT UNSIGNED NOT NULL ,
  `ip_text` CHAR(15) ASCII NOT NULL ,
  `player_id` INT UNSIGNED NULL ,
  `creation` DATETIME NOT NULL DEFAULT NOW() ,
  INDEX `ip` (`ip` ASC) ,
  INDEX `player_id` (`player_id` ASC) ,
  CONSTRAINT `player_id`
    FOREIGN KEY (`player_id` )
    REFERENCES `rcon_db`.`players` (`player_id` )
    ON DELETE CASCADE
    ON UPDATE NO ACTION)
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`guids`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`guids` (
  `guid_id` INT UNSIGNED NOT NULL AUTO_INCREMENT ,
  `guid` CHAR(32) ASCII NOT NULL ,
  `player_id` INT UNSIGNED NULL ,
  PRIMARY KEY (`guid_id`) ,
  INDEX `player_id` (`player_id` ASC) ,
  CONSTRAINT `player_id`
    FOREIGN KEY (`player_id` )
    REFERENCES `rcon_db`.`players` (`player_id` )
    ON DELETE CASCADE
    ON UPDATE NO ACTION)
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`rcon_log`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`rcon_log` (
  `log_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT ,
  `datetime` DATETIME NOT NULL ,
  `player_id` INT UNSIGNED NOT NULL ,
  `ip` INT UNSIGNED NULL ,
  `slot` TINYINT UNSIGNED NULL ,
  `action` TINYINT UNSIGNED NULL ,
  PRIMARY KEY (`log_id`) ,
  INDEX `player_id` (`player_id` ASC) ,
  INDEX `ip` (`ip` ASC) ,
  CONSTRAINT `player_id`
    FOREIGN KEY (`player_id` )
    REFERENCES `rcon_db`.`players` (`player_id` )
    ON DELETE CASCADE
    ON UPDATE NO ACTION,
  CONSTRAINT `ip`
    FOREIGN KEY (`ip` )
    REFERENCES `rcon_db`.`ips` (`ip` )
    ON DELETE CASCADE
    ON UPDATE NO ACTION)
ENGINE = MyISAM  ROW_FORMAT = FIXED;


-- -----------------------------------------------------
-- Table `rcon_db`.`servers`
-- -----------------------------------------------------
CREATE  TABLE IF NOT EXISTS `rcon_db`.`servers` (
  `server_id` TINYINT UNSIGNED NOT NULL AUTO_INCREMENT ,
  `status` TINYINT NULL DEFAULT 0 ,
  `ip` INT UNSIGNED NULL ,
  `port` MEDIUMINT UNSIGNED NULL DEFAULT 27960 ,
  `name` VARCHAR(64) NULL ,
  `current_map` VARCHAR(45) NULL ,
  `timeouts` INT UNSIGNED NULL DEFAULT 0 ,
  `timeout_last` INT UNSIGNED NULL ,
  `timeout_delay` INT UNSIGNED NULL DEFAULT 5 ,
  `timeout_wait_delay` INT UNSIGNED NULL DEFAULT 10 ,
  `rcon_pw` VARCHAR(32) NULL ,
  `svars` TEXT(1024) NULL ,
  PRIMARY KEY (`server_id`) )
ENGINE = MyISAM;


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
