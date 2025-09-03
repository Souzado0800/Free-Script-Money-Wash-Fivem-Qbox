-- TABELA: Geradores persistentes
CREATE TABLE IF NOT EXISTS `aph_moneywash_generators` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `model` VARCHAR(64) NOT NULL DEFAULT 'prop_generator_03b',
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `remaining` INT NOT NULL DEFAULT 0,     -- segundos restantes de funcionamento
  `is_on` TINYINT(1) NOT NULL DEFAULT 0,  -- 1 ligado, 0 desligado
  `owner_license` VARCHAR(64) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX (`owner_license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABELA: Estações de lavagem persistentes
CREATE TABLE IF NOT EXISTS `aph_moneywash_stations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `model` VARCHAR(64) NOT NULL DEFAULT 'prop_cash_depot',
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `owner_license` VARCHAR(64) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX (`owner_license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- (Opcional) TABELA: Lavagens em andamento (para sobreviver a restart)
CREATE TABLE IF NOT EXISTS `aph_moneywash_washes` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_license` VARCHAR(64) NOT NULL,
  `clean_amount` INT NOT NULL,
  `end_time_unix` INT NOT NULL, -- os.time() quando estará pronto
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX (`owner_license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
