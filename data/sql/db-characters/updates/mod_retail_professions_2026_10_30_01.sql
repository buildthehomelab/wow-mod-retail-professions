-- mod-retail-professions: profession equipment slots belong to the account
-- (RetailProfessions.Gear.AccountWide). The account's rows have owner_guid 0 and the account id;
-- a character's own rows (a challenge that keeps gear to the character, or AccountWide off) have
-- its guid and account 0, as every row had so far. The module moves a character's own rows to the
-- account at its login. Safe to run again: each change is made only when it isn't there yet.

SET @rpr_has_account := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mod_retail_professions_gear_slot' AND COLUMN_NAME = 'account');
SET @sql := IF(@rpr_has_account = 0,
    'ALTER TABLE `mod_retail_professions_gear_slot` ADD COLUMN `account` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `owner_guid`',
    'DO 0');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- The unique key gets the account: (owner_guid, account, skill, slot).
SET @rpr_key_has_account := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mod_retail_professions_gear_slot' AND INDEX_NAME = 'idx_owner_slot'
    AND COLUMN_NAME = 'account');
SET @sql := IF(@rpr_key_has_account = 0,
    'ALTER TABLE `mod_retail_professions_gear_slot` DROP INDEX `idx_owner_slot`, ADD UNIQUE KEY `idx_owner_slot` (`owner_guid`, `account`, `skill`, `slot`)',
    'DO 0');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @rpr_has_account_key := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mod_retail_professions_gear_slot' AND INDEX_NAME = 'idx_account');
SET @sql := IF(@rpr_has_account_key = 0,
    'ALTER TABLE `mod_retail_professions_gear_slot` ADD KEY `idx_account` (`account`)',
    'DO 0');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
