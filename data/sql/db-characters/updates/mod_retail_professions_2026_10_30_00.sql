-- mod-retail-professions: what each character has in its profession equipment slots. The item
-- itself stays in item_instance (enchants, durability and binding intact); this row replaces its
-- character_inventory row, the way mail holds items.
CREATE TABLE IF NOT EXISTS `mod_retail_professions_gear_slot` (
    `owner_guid` INT UNSIGNED      NOT NULL,
    `skill`      SMALLINT UNSIGNED NOT NULL,
    `slot`       TINYINT UNSIGNED  NOT NULL,
    `item_guid`  INT UNSIGNED      NOT NULL,
    PRIMARY KEY (`item_guid`),
    UNIQUE KEY `idx_owner_slot` (`owner_guid`, `skill`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
