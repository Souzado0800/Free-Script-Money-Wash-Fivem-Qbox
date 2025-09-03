aph_moneywash

An advanced and immersive money wash system for FiveM servers (QBCore/Qbox compatible).
This resource introduces a realistic way to launder black money into clean money, combined with a generator system that powers the washing stations, adding risk, strategy, and immersion to your roleplay server.

✨ Features

Money Wash Stations

Placeable via moneywash_kit item.

Customizable tax percentage and processing time.

Interactive menu with gradient UI (purple/black) built with ox_lib.

Supports dirty money (black_money) → clean money (money) conversion.

Generators

Placeable via generator_kit item.

Requires fuel (gasoline) to operate.

Each fuel can = configurable minutes of runtime.

Start/stop functionality — when stopped, runtime is paused.

Real-time countdown displayed in 3D text above the generator.

Interactive target menu with options to refuel and toggle power.

Persistence

Full database integration via oxmysql.

Generators and money wash stations are saved in the database and automatically respawn after server restarts.

Ownership stored via player license.

(Optional) Persist ongoing washes in database for full restart-proof experience.

Inventory Integration

Built for ox_inventory.

Items (moneywash_kit, generator_kit, gasoline) are consumed properly when used.

Target Support

Seamless interaction with placed props using ox_target.

🛠️ Dependencies

ox_lib

ox_inventory

ox_target

oxmysql

⚙️ Configuration

Props: configurable in config.lua (prop_cash_depot, prop_generator_03b, etc).

Rates: washing tax %, processing time, minutes per fuel can.

Distances: max distance between generator and moneywash station.

📦 Installation

Import the SQL file (aph_moneywash.sql) into your database.

Place the resource in your server’s resources folder.

Add ensure aph_moneywash to your server.cfg.

Configure items in ox_inventory/data/items.lua.

Restart the server.

🕹️ Usage

Use a moneywash_kit item to place a wash station.

Use a generator_kit item to place a generator.

Add fuel (gasoline) to power the generator.

Approach the wash station while a powered generator is nearby to open the laundering menu.
