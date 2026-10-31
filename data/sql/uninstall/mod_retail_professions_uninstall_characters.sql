-- mod-retail-professions: undo the module's characters database changes. Run it by hand on the
-- characters database after removing the module; AzerothCore doesn't run it automatically.
--
-- Slotted profession equipment goes back to its owners by mail (from themselves, stationery
-- GM, 30 days), one mail per item, so nothing is lost; then the slot table goes. An account's
-- slots go to its first character (the lowest guid). Run it with the worldserver stopped.
-- Idempotent: safe to run again.

DROP TEMPORARY TABLE IF EXISTS `tmp_rpr_gear`;
CREATE TEMPORARY TABLE `tmp_rpr_gear` (
    `mail_id`    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_guid` INT UNSIGNED NOT NULL,
    `item_guid`  INT UNSIGNED NOT NULL,
    PRIMARY KEY (`mail_id`)
);

SET @first_mail := (SELECT COALESCE(MAX(`id`), 0) + 1 FROM `mail`);
SET @sql := CONCAT('ALTER TABLE `tmp_rpr_gear` AUTO_INCREMENT = ', @first_mail);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

INSERT INTO `tmp_rpr_gear` (`owner_guid`, `item_guid`)
SELECT o.`owner_guid`, o.`item_guid`
FROM (
    SELECT g.`item_guid`, IF(g.`owner_guid` <> 0, g.`owner_guid`,
        (SELECT MIN(c.`guid`) FROM `characters` c WHERE c.`account` = g.`account`)) AS `owner_guid`
    FROM `mod_retail_professions_gear_slot` g
    JOIN `item_instance` ii ON ii.`guid` = g.`item_guid`
    -- A row whose item is also in the bags or a mailbox lost a race; that copy is the real one.
    LEFT JOIN `character_inventory` ci ON ci.`item` = g.`item_guid`
    LEFT JOIN `mail_items` mi ON mi.`item_guid` = g.`item_guid`
    WHERE ci.`item` IS NULL AND mi.`item_guid` IS NULL
) o
-- An account with no character left has no one to get it.
WHERE o.`owner_guid` IS NOT NULL;

-- The account's items have no owner in item_instance while slotted.
UPDATE `item_instance` ii JOIN `tmp_rpr_gear` t ON t.`item_guid` = ii.`guid` SET ii.`owner_guid` = t.`owner_guid`;

INSERT INTO `mail` (`id`, `messageType`, `stationery`, `mailTemplateId`, `sender`, `receiver`, `subject`, `body`,
    `has_items`, `expire_time`, `deliver_time`, `money`, `cod`, `checked`)
SELECT t.`mail_id`, 0, 61, 0, t.`owner_guid`, t.`owner_guid`, 'Profession equipment',
    'Profession equipment slots were removed from the realm, so your slotted gear came back.',
    1, UNIX_TIMESTAMP() + 30 * 86400, UNIX_TIMESTAMP(), 0, 0, 4
FROM `tmp_rpr_gear` t;

INSERT INTO `mail_items` (`mail_id`, `item_guid`, `receiver`)
SELECT t.`mail_id`, t.`item_guid`, t.`owner_guid` FROM `tmp_rpr_gear` t;

DROP TEMPORARY TABLE `tmp_rpr_gear`;
DROP TABLE IF EXISTS `mod_retail_professions_gear_slot`;
