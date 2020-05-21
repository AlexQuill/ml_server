
-- MySQL Workbench Forward Engineering

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- -----------------------------------------------------
-- Schema mydb
-- -----------------------------------------------------
use `heroku_341a27901840f2f`;
-- -----------------------------------------------------
-- Table `heroku_341a27901840f2f`.`User`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `user`;
CREATE TABLE `user` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `first_name` VARCHAR(45) NULL,
  `last_name` VARCHAR(45) NULL,
  `username` VARCHAR(45) NOT NULL UNIQUE,
  `password` VARCHAR(60) NOT NULL,
  `age` INT NULL,
  `gender` VARCHAR(45) NULL,
  `account_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.0,
  `is_tenant` BOOLEAN NOT NULL DEFAULT true,
  `is_landlord` BOOLEAN NOT NULL DEFAULT false,
  `is_admin` BOOLEAN NOT NULL DEFAULT false, 
  PRIMARY KEY (`id`))
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `Property`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `Property`;
CREATE TABLE IF NOT EXISTS `Property` (
  `property_id` INT NOT NULL AUTO_INCREMENT,
  `address` VARCHAR(250) NOT NULL,
  `city` VARCHAR(45) NOT NULL,
  `owner_id` INT NOT NULL,
  PRIMARY KEY (`property_id`),
  INDEX `fk_Unit_User1_idx` (`owner_id` ASC),
	CONSTRAINT `fk_Property_User1`
		FOREIGN KEY (`owner_id`)
		REFERENCES `User` (`id`)
		ON DELETE NO ACTION
		ON UPDATE NO ACTION)
ENGINE = InnoDB;

-- -----------------------------------------------------
-- Table `Unit`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `Unit`;
CREATE TABLE `Unit` (
  `unit_id` INT NOT NULL AUTO_INCREMENT,
  `property_id` INT NOT NULL,
  `is_occupied` BOOLEAN NOT NULL DEFAULT false,
  `market_price` DECIMAL(10,2) NOT NULL,
  `unit_number` varchar(45) NOT NULL,
  PRIMARY KEY (`unit_id`),
  INDEX `fk_Unit_Property1_idx` (`property_id` ASC),
  UNIQUE INDEX `unit_id_UNIQUE` (`unit_id` ASC),
  CONSTRAINT `fk_Unit_Property1`
    FOREIGN KEY (`property_id`)
    REFERENCES `Property` (`property_id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `Lease`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `Lease`;
CREATE TABLE `Lease` (
  `lease_id` INT NOT NULL AUTO_INCREMENT,
  `unit_id` INT NOT NULL,
  `start_date` DATETIME NOT NULL,
  `end_date` DATETIME NOT NULL,
  `price_monthly` DECIMAL(10,2) NOT NULL,
  `leasing_user_id` INT NOT NULL,
  PRIMARY KEY (`lease_id`),
  INDEX `fk_Lease_Unit1_idx` (`unit_id` ASC),
  INDEX `fk_Lease_User1_idx` (`leasing_user_id` ASC),
  CONSTRAINT `fk_Lease_Unit1`
    FOREIGN KEY (`unit_id`)
    REFERENCES `Unit` (`unit_id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Lease_User1`
    FOREIGN KEY (`leasing_user_id`)
    REFERENCES `User` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `Rating`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `Rating`;
CREATE TABLE  `Rating` (
  `rating_id` INT NOT NULL AUTO_INCREMENT,
  `text` VARCHAR(400) NULL,
  `score` INT NULL,
  `rater_id` INT NOT NULL,
  `being_rated_id` INT NOT NULL,
  `being_rated_as` VARCHAR(45) NULL,
  PRIMARY KEY (`rating_id`),
  INDEX `fk_Rating_User1_idx` (`rater_id` ASC),
  INDEX `fk_Rating_User2_idx` (`being_rated_id` ASC),
  CONSTRAINT `fk_Rating_User1`
    FOREIGN KEY (`rater_id`)
    REFERENCES `User` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Rating_User2`
    FOREIGN KEY (`being_rated_id`)
    REFERENCES `User` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `Debt`
-- -----------------------------------------------------
DROP TABLE IF EXISTS `Debt`;
CREATE TABLE `Debt` (
  `creditor_id` INT NOT NULL,
  `debtor_id` INT NOT NULL,
  `amount_owed` DECIMAL(10,2) NULL,
  INDEX `fk_Debt_User1_idx` (`creditor_id` ASC),
  INDEX `fk_Debt_User2_idx` (`debtor_id` ASC),
  PRIMARY KEY (`creditor_id`, `debtor_id`),
  CONSTRAINT `fk_Debt_User1`
    FOREIGN KEY (`creditor_id`)
    REFERENCES `User` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Debt_User2`
    FOREIGN KEY (`debtor_id`)
    REFERENCES `User` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
	      

-- -----------------------------------------------------
-- Triggers:
-- PerformTransaction
-- CheckExpired
-- SetOccupied
-- -----------------------------------------------------

DROP EVENT IF EXISTS PerformTransaction;   
DROP EVENT IF EXISTS CheckExpired;
DROP TRIGGER IF EXISTS SetOccupied;

-- ---------------
-- Called on insert into lease table
-- Goes to unit and swap occupied boolean
-- ---------------

DELIMITER $$
CREATE TRIGGER SetOccupied
	AFTER INSERT ON Lease
    FOR EACH ROW
    BEGIN
      IF (count(SELECT * FROM Unit u WHERE u.unit_id == new.unit_id AND u.occupied == 1) == 0) THEN
        UPDATE Unit SET 
          occupied = 1 
          WHERE unit_id == new.unit_id;
      END IF;
    END$$
DELIMITER ;

-- new.unit_id
-- OR
-- Put the business logic in API rather than triggers, easier to separate and edit modification logic when contained in a controller
-- Use triggers sparingly. 

-- Don't be afraid to put data checks in front end 


-- ---------------
-- Check_expired
-- Once a day, on whatever second we build the schema, runs over all leases and checks if any one expired the previous day. 
-- If so, set occupied = 0
-- ---------------

CREATE EVENT checkExpired
    ON SCHEDULE EVERY 1 DAY
    STARTS CURRENT_TIMESTAMP
    ENDS CURRENT_TIMESTAMP + INTERVAL 1 MONTH
    DO
      UPDATE unit SET occupied = 0
      WHERE unit_id IN (
        SELECT unit_id FROM Lease l 
          WHERE Datediff(l.end_date, CURRENT_TIMESTAMP()) >= 0 
          AND Datediff(l.end_date, CURRENT_TIMESTAMP()) < 1
        )
      ); 

-- ---------------
-- Perform_transaction
-- Once a month
-- subtract active lease cost from tenant 
-- add active lease cost to renter
-- ---------------

CREATE EVENT PerformTransaction
    ON SCHEDULE EVERY 1 MONTH
    STARTS CURRENT_TIMESTAMP
    ENDS CURRENT_TIMESTAMP + INTERVAL 1 MONTH -- be kind to sunapee
    DO
      START TRANSACTION;
        UPDATE user u SET u.account_balance = u.account_balance - sum( -- Charge
          SELECT price_monthly FROM Lease l (
            WHERE l.leasing_user_id == u.id
            AND (GETDATE() > l.start_date AND GETDATE() < l.end_date)
          )
        );
        UPDATE User u SET u.account_balance = u.account_balance + sum( -- Pay
          SELECT market_price FROM Unit k ( -- could cause inconsistencies? Maybe fix later. 
            WHERE k.owner_id == u.id
            AND (GETDATE() > l.start_date AND GETDATE() < l.end_date) 
          )
        )
      COMMIT;
